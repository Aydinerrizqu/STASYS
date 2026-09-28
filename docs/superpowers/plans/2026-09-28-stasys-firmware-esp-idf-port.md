# STASYS Firmware ESP-IDF Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the local Arduino firmware with the upstream ESP-IDF sensor/protocol implementation while retaining dual-slot Bluetooth OTA and secure per-device provisioning.

**Architecture:** Copy the active upstream component architecture into `Firmware_STASYS32`, retaining its sensor HAL and 36-byte payload. Add bounded serial provisioning for a unique NVS key, a connection-generation field to the auth v2 greeting, a bounded discoverability window, and port the existing OTA text protocol onto ESP-IDF SPP with OTA operations isolated from sensor streaming.

**Tech Stack:** ESP-IDF 5.5 (via PlatformIO `espressif32@6.12.0`), FreeRTOS, Classic Bluetooth SPP, mbedTLS, Python unittest.

**Reference:** Upstream repo `https://github.com/dylemmas/STASYS_FW` at commit `4246dca` (clone path recorded during design: `/tmp/STASYS_FW_upstream`). Spec: `docs/superpowers/specs/2026-09-28-upstream-firmware-flutter-port-design.md`.

**Worktree:** All work happens in this worktree (`feature/figma-train-redesign`). Never touch the primary checkout. Never `git stash` (shared stash stack).

---

## Files and responsibilities

- Modify `Firmware_STASYS32/platformio.ini`: ESP-IDF framework, pinned platform, dual-slot partitions.
- Create `Firmware_STASYS32/CMakeLists.txt`, `Firmware_STASYS32/sdkconfig.defaults`, `Firmware_STASYS32/src/CMakeLists.txt`: ESP-IDF project wiring.
- Create `Firmware_STASYS32/components/app_protocol/`: upstream 36-byte serializer + HMAC auth v2 (from upstream, unmodified interface).
- Create `Firmware_STASYS32/components/sensors/`: upstream MPU/QMC/HMC/ADC HAL (verbatim from upstream).
- Create `Firmware_STASYS32/components/system_config/`: authoritative board pin map (from upstream).
- Create `Firmware_STASYS32/src/provisioning/{provisioning.h,provisioning.cpp}`: USB serial key provisioning, NVS-backed key provider (fail closed).
- Create `Firmware_STASYS32/src/ota/{bt_ota.h,bt_ota.cpp,bt_ota_commands.h}`: OTA text protocol on ESP-IDF SPP (port of local Arduino implementation).
- Replace `Firmware_STASYS32/src/main.cpp`: upstream `app_main` coordinator + generation greeting + enrollment discoverability window + OTA integration.
- Keep `Firmware_STASYS32/partitions_dual_ota.csv` (validate before flashing).
- Create `Firmware_STASYS32/scripts/validate_partitions.py`: partition overlap/flash-bounds validator (adapt from upstream script).
- Create `Firmware_STASYS32/scripts/check_release.py`: release gates (no fallback secrets, image fits slot).
- Create `Firmware_STASYS32/test/`: host tests (Python unittest — pure protocol/parser math only; no hardware).
- Create `Firmware_STASYS32/docs/provisioning.md`, `Firmware_STASYS32/docs/hardware-validation.md`.
- Delete: `Firmware_STASYS32/src/storage/*` (Arduino `Preferences`-based storage), `Firmware_STASYS32/src/sensor/*` (Arduino Wire-based sensor code), old `Firmware_STASYS32/.pio/` build output. Verify no remaining `#include <Arduino.h>` references first.

## Task 1: Freeze cross-language protocol contract with Python reference tests

**Files:**
- Create: `Firmware_STASYS32/test/test_protocol_contract.py`

The Dart side (Plan B) will implement the identical contract. These tests are the source of truth.

- [ ] **Step 1: Write the failing contract test.**

```python
import hmac, hashlib, struct, unittest

DOMAIN = b"STASYS-AUTH/v2\0"  # 15 bytes incl. explicit NUL

def transcript(identity: bytes, generation: int, nonce: bytes) -> bytes:
    assert len(identity) == 6 and len(nonce) == 32
    return DOMAIN + identity + struct.pack("<I", generation) + nonce

class ContractTests(unittest.TestCase):
    def test_transcript_exact_bytes(self):
        t = transcript(bytes.fromhex("781c3cf51618"), 7, bytes(range(32)))
        self.assertEqual(len(t), 15 + 6 + 4 + 32)  # 57
        self.assertEqual(t[:15], DOMAIN)
        self.assertEqual(t[15:21], bytes.fromhex("781c3cf51618"))
        self.assertEqual(t[21:25], struct.pack("<I", 7))
        self.assertEqual(t[25:], bytes(range(32)))

    def test_proof_known_vector(self):
        # key = 32 bytes 0x00..0x1f
        key = bytes(range(32))
        proof = hmac.new(key, transcript(bytes.fromhex("010203040506"),
                         1, bytes(32)), hashlib.sha256).digest()
        self.assertEqual(len(proof), 32)
        self.assertEqual(proof.hex(), hmac.new(key, b"", hashlib.sha256).digest()[:0]
                         + hmac.new(key, DOMAIN + bytes.fromhex("010203040506")
                                    + struct.pack("<I", 1) + bytes(32),
                                    hashlib.sha256).digest())

    def test_frame_layout_36_bytes(self):
        # 0xAA 0xBB | 6*f32 LE | 3*i16 LE | u16 piezo | u8 battery | XOR(2..34)
        frame = bytearray(36)
        frame[0], frame[1] = 0xAA, 0xBB
        struct.pack_into("<6f", frame, 2, 1.0, -2.0, 3.0, 0.1, -0.2, 3.5)
        struct.pack_into("<3h", frame, 26, -32768, 0, 32767)
        struct.pack_into("<H", frame, 32, 4095)
        frame[34] = 88
        xor = 0
        for b in frame[2:35]:
            xor ^= b
        frame[35] = xor
        self.assertEqual(len(frame), 36)
        self.assertEqual(frame[35], xor)

    def test_greeting_grammar(self):
        # READY v=2 gen=<uint32>\nAUTH <64 hex>\n  (extension documented in spec)
        import re
        line = "READY v=2 gen=4294967295"
        m = re.fullmatch(r"READY v=(\d+) gen=(\d{1,10})", line)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), "2")
        self.assertEqual(int(m.group(2)), 0xFFFFFFFF)

    def test_frame_checksum_detects_single_bit_flip(self):
        frame = bytearray(36)
        frame[0], frame[1] = 0xAA, 0xBB
        frame[5] = 0x40
        xor = 0
        for b in frame[2:35]:
            xor ^= b
        frame[35] = xor
        frame[5] ^= 0x01
        corrupt_xor = 0
        for b in frame[2:35]:
            corrupt_xor ^= b
        self.assertNotEqual(corrupt_xor, frame[35])

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it passes (contract is self-consistent from day one).**

Run: `python -m unittest Firmware_STASYS32/test/test_protocol_contract.py -v` (from worktree root)
Expected: `OK` — 5 tests.

- [ ] **Step 3: Commit.**

```bash
git add Firmware_STASYS32/test/test_protocol_contract.py
git commit -m "test: freeze upstream auth and frame byte contract"
```

## Task 2: Replace build system with ESP-IDF and validate partitions

**Files:**
- Modify: `Firmware_STASYS32/platformio.ini`
- Create: `Firmware_STASYS32/CMakeLists.txt`, `Firmware_STASYS32/sdkconfig.defaults`, `Firmware_STASYS32/src/CMakeLists.txt`
- Create: `Firmware_STASYS32/scripts/validate_partitions.py`
- Keep: `Firmware_STASYS32/partitions_dual_ota.csv`

- [ ] **Step 1: Copy upstream build files.**

```bash
cp /tmp/STASYS_FW_upstream/CMakeLists.txt Firmware_STASYS32/CMakeLists.txt
cp /tmp/STASYS_FW_upstream/src/CMakeLists.txt Firmware_STASYS32/src/CMakeLists.txt
cp /tmp/STASYS_FW_upstream/sdkconfig.defaults Firmware_STASYS32/sdkconfig.defaults
cp /tmp/STASYS_FW_upstream/scripts/validate_partitions.py Firmware_STASYS32/scripts/validate_partitions.py
```

(If the `/tmp` clone was cleaned, re-clone: `git clone --depth 1 https://github.com/dylemmas/STASYS_FW /tmp/STASYS_FW_upstream`.)

- [ ] **Step 2: Write `platformio.ini` (replace existing content).**

```ini
[env:esp32dev]
platform = espressif32@6.12.0
board = esp32dev
framework = espidf
monitor_speed = 115200
board_build.f_cpu = 240000000L
board_build.partitions = partitions_dual_ota.csv
build_type = release
build_flags =
    -DCORE_DEBUG_LEVEL=3
```

Notes: keep `CORE_DEBUG_LEVEL=3` during bring-up (downgrade to 0 before release-task run). Delete the old `[env:native]` section (its referenced `test/` files do not exist in this worktree).

- [ ] **Step 3: Verify partition geometry.**

Current `partitions_dual_ota.csv`: app0 `0x10000..0x1C0000` (0x1B0000 = 1769472 B), app1 `0x1C0000..0x370000`, spiffs `0x370000..0x3F0000`, coredump `0x3F0000..0x400000` → total 0x400000 = 4 MB.

Run: `python Firmware_STASYS32/scripts/validate_partitions.py --help` to learn the script's expected arguments, then run it against `partitions_dual_ota.csv` with `--flash-size 4194304`.
Expected: PASS (no overlap, ends exactly at 4 MB).

If validation fails or measured flash differs: STOP and report; do not edit partition sizes without user approval (the spec makes measured flash a hard gate).

- [ ] **Step 4: Run baseline build (expected FAIL until Task 4).**

Run: `python -m platformio run -d Firmware_STASYS32 -e esp32dev`
Expected: FAIL with missing `components/` — confirms ESP-IDF toolchain engages and the old Arduino sources error out. Record the exact error type (missing component vs. old `.cpp` compile error); if the error is a toolchain/network problem instead, resolve that first (PlatformIO will download `espressif32@6.12.0` + IDF 5.5 on first run — this can take minutes).

- [ ] **Step 5: Commit.**

```bash
git add Firmware_STASYS32/platformio.ini Firmware_STASYS32/CMakeLists.txt \
        Firmware_STASYS32/src/CMakeLists.txt Firmware_STASYS32/sdkconfig.defaults \
        Firmware_STASYS32/scripts/validate_partitions.py
git commit -m "build: switch firmware to ESP-IDF with dual-slot partitions"
```

## Task 3: Port upstream components (app_protocol, sensors, system_config)

**Files:**
- Create: `Firmware_STASYS32/components/app_protocol/{CMakeLists.txt,app_protocol.cpp,include/app_protocol.h}`
- Create: `Firmware_STASYS32/components/sensors/{CMakeLists.txt,sensor_hal.cpp,sensor_hal.h}`
- Create: `Firmware_STASYS32/components/system_config/{CMakeLists.txt,system_config.c,system_config.h}`
- Create: `Firmware_STASYS32/components/system_config/include/` only if upstream layout requires; mirror upstream exactly.

- [ ] **Step 1: Copy upstream components verbatim.**

```bash
cp -r /tmp/STASYS_FW_upstream/components/app_protocol Firmware_STASYS32/components/
cp -r /tmp/STASYS_FW_upstream/components/sensors      Firmware_STASYS32/components/
cp -r /tmp/STASYS_FW_upstream/components/system_config Firmware_STASYS32/components/
cp /tmp/STASYS_FW_upstream/components/system_config.h Firmware_STASYS32/components/system_config.h
```

Verify afterwards: `diff -r` between upstream `components/` and the copied tree must be empty.

- [ ] **Step 2: Remove the duplicate system_config header.** Upstream CLAUDE.md documents `components/system_config.h` and `components/system_config/system_config.h` as duplicates that must be kept in sync. Check whether both are actually included anywhere (`grep -rn "system_config.h"` in the copied tree); if one is unused, delete it and note the choice in the commit message. If both are needed, keep both and add a comment cross-referencing them.

- [ ] **Step 3: Confirm the frame serializer matches Task 1's contract.** Run `python -m unittest Firmware_STASYS32/test/test_protocol_contract.py -v`.
Expected: `OK`. Do not modify `app_protocol.cpp` serializer.

- [ ] **Step 4: Port pure battery-percentage logic check.** `staysys_battery_percentage` lives in `sensor_hal.cpp` (uses `isfinite`, no ESP-IDF deps except headers) — covered indirectly; no change needed. Verify it rejects NaN/inf (upstream code does; contract test documents expectation).

- [ ] **Step 5: Commit.**

```bash
git add Firmware_STASYS32/components/
git commit -m "feat: port upstream sensor HAL and app protocol components"
```

## Task 4: Replace `main.cpp` with upstream coordinator (auth v2 + generation greeting + enrollment window)

**Files:**
- Modify: `Firmware_STASYS32/src/CMakeLists.txt` (add `provisioning` to REQUIRES/priv requires if made a component — instead keep provisioning as part of `src` to avoid extra component)
- Create: `Firmware_STASYS32/src/provisioning/provisioning.h`, `Firmware_STASYS32/src/provisioning/provisioning.cpp`
- Replace: `Firmware_STASYS32/src/main.cpp`
- Delete after reference check: `Firmware_STASYS32/src/storage/`, `Firmware_STASYS32/src/sensor/`, `Firmware_STASYS32/src/ota/bt_ota*` (old Arduino versions — OTA re-added in Task 5)

- [ ] **Step 1: Write failing Python test for provisioning command parser grammar.** Add to a new `Firmware_STASYS32/test/test_provisioning_grammar.py`: `PROVISION_KEY:<64 hex>\n` accepted (upper and lower hex); rejected: 63/65 chars, non-hex, empty, missing prefix. Note: this tests the grammar Dart/serial operator must follow; firmware parser is C++ and is validated by the same vectors printed in docs/provisioning.md.

```python
import re, unittest

PATTERN = re.compile(r"PROVISION_KEY:([0-9a-fA-F]{64})")

class ProvisioningGrammar(unittest.TestCase):
    def test_accepts_64_hex(self):
        self.assertIsNotNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 32))
        self.assertIsNotNone(PATTERN.fullmatch("PROVISION_KEY:" + "AB" * 32))
    def test_rejects_bad_input(self):
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 31))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "ab" * 33))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:" + "zz" * 32))
        self.assertIsNone(PATTERN.fullmatch("PROVISION_KEY:"))

if __name__ == "__main__":
    unittest.main()
```

Run: `python -m unittest Firmware_STASYS32/test/test_provisioning_grammar.py -v` → PASS (grammar is defined by this test).

- [ ] **Step 1b: Port upstream host handshake tests and extend with generation grammar.** Copy `/tmp/STASYS_FW_upstream/test/test_stasys_packet.py` to `Firmware_STASYS32/test/test_stasys_packet.py` (it already covers packet round-trip, fragmentation, noise resync, auth fragments, coalesced first frame, and wrong proof). Then adapt `SppReceiver.authenticate()` in `tools`-equivalent imports for this layout and extend the greeting parser from `READY v=2` to also accept `READY v=2 gen=<uint32>`, reading generation from the greeting instead of the constructor default. Add three new tests: (a) generation parsed from greeting is used in transcript; (b) missing `gen=` field rejected; (c) two different generations with same nonce produce different proofs. Run: `python -m unittest discover -s Firmware_STASYS32/test -v` → all OK.

- [ ] **Step 2: Copy upstream `main.cpp` as the base.**

```bash
cp /tmp/STASYS_FW_upstream/src/main.cpp Firmware_STASYS32/src/main.cpp
```

- [ ] **Step 3: Add `src/provisioning/provisioning.h`.**

```cpp
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Load the provisioned 32-byte device key from NVS.
 * Returns 0 and sets *key/*key_len on success; -1 when absent/invalid. */
int staysys_provisioned_key(const uint8_t **key, size_t *key_len);

/* Handle one newline-terminated provisioning line from USB serial.
 * Returns true if the line was a provisioning command (handled). */
bool provisioning_handle_line(const char *line);

/* Human-readable provisioning status for serial output (never the key). */
void provisioning_print_status(void);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 4: Implement `src/provisioning/provisioning.cpp`.**

```cpp
#include "provisioning.h"
#include <stdio.h>
#include <string.h>
#include "nvs.h"
#include "esp_log.h"

static const char *TAG = "provision";
static const char *NVS_NS = "auth";
static const char *NVS_KEY = "device_key";
static const int KEY_LEN = 32;

static uint8_t s_key[KEY_LEN];
static bool s_key_loaded = false;
static bool s_key_valid = false;

static bool hex_decode_32(const char *hex, uint8_t out[KEY_LEN]) {
    if (strlen(hex) != KEY_LEN * 2) return false;
    for (int i = 0; i < KEY_LEN; ++i) {
        char pair[3] = {hex[i * 2], hex[i * 2 + 1], 0};
        char *end = nullptr;
        long v = strtol(pair, &end, 16);
        if (end == nullptr || *end != 0 || (pair[0] == 0)) return false;
        if (!((pair[0] >= '0' && pair[0] <= '9') || (pair[0] >= 'a' && pair[0] <= 'f') ||
              (pair[0] >= 'A' && pair[0] <= 'F'))) return false;
        out[i] = (uint8_t)v;
    }
    return true;
}

int staysys_provisioned_key(const uint8_t **key, size_t *key_len) {
    if (s_key_valid) { *key = s_key; *key_len = KEY_LEN; return 0; }
    if (s_key_loaded) return -1;
    s_key_loaded = true;
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return -1;
    size_t len = KEY_LEN;
    int rc = nvs_get_blob(h, NVS_KEY, s_key, &len);
    nvs_close(h);
    s_key_valid = (rc == ESP_OK && len == KEY_LEN);
    if (!s_key_valid) memset(s_key, 0, sizeof(s_key));
    *key = s_key_valid ? s_key : NULL;
    *key_len = s_key_valid ? KEY_LEN : 0;
    return s_key_valid ? 0 : -1;
}

bool provisioning_handle_line(const char *line) {
    const char prefix[] = "PROVISION_KEY:";
    if (strncmp(line, prefix, sizeof(prefix) - 1) != 0) return false;
    const char *hex = line + sizeof(prefix) - 1;
    uint8_t decoded[KEY_LEN];
    if (!hex_decode_32(hex, decoded)) {
        ESP_LOGW(TAG, "provisioning rejected: malformed key (expected 64 hex chars)");
        printf("PROVISION_ERR:malformed\n");
        return true;
    }
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) {
        printf("PROVISION_ERR:nvs\n");
        return true;
    }
    esp_err_t err = nvs_set_blob(h, NVS_KEY, decoded, KEY_LEN);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    memset(decoded, 0, sizeof(decoded));
    if (err != ESP_OK) {
        printf("PROVISION_ERR:write\n");
        return true;
    }
    /* Invalidate cache so next auth read uses new key. */
    memset(s_key, 0, sizeof(s_key));
    s_key_loaded = false;
    s_key_valid = false;
    printf("PROVISION_OK\n");
    return true;
}

void provisioning_print_status(void) {
    const uint8_t *k; size_t n;
    const char *status =
        staysys_provisioned_key(&k, &n) == 0 ? "ok" : "absent";
    printf("PROVISION_STATUS:%s\n", status);
}
```

Note: after `staysys_provisioned_key` fails once it caches `s_key_loaded=true` — provisioning resets the cache, so a provision-then-connect sequence in one boot works.

- [ ] **Step 5: Wire the generation greeting in `main.cpp`.** In the upstream `ESP_SPP_SRV_OPEN_EVT` branch, change the greeting construction:

```cpp
char greeting[sizeof(nonce_hex) + 40];
int greeting_len = snprintf(greeting, sizeof(greeting),
    "READY v=%u gen=%u\nAUTH %s\n",
    STASYS_AUTH_VERSION, (unsigned)spp_generation, nonce_hex);
```

(`spp_generation` is already incremented before this point in upstream code.) Update Task 1's contract test to also assert `gen=` grammar — already present.

- [ ] **Step 6: Wire the weak key provider.** Upstream `main.cpp` already declares the weak `staysys_provisioned_key` and fails closed when null. Since Task 4 now provides a strong definition in `provisioning.cpp`, the weak default is overridden — keep upstream's weak-declaration code as-is (it compiles either way), and ensure `src/CMakeLists.txt` SRCS includes `provisioning/provisioning.cpp`:

```cmake
idf_component_register(
    SRCS "main.cpp" "provisioning/provisioning.cpp"
    INCLUDE_DIRS "." "provisioning"
    REQUIRES app_protocol sensors system_config bt nvs_flash
)
```

- [ ] **Step 7: Add enrollment discoverability window in `main.cpp`.** Replace upstream's immediate `ESP_BT_NON_DISCOVERABLE` call:

```cpp
#define ENROLLMENT_WINDOW_MS (5 * 60 * 1000)  // documented in docs/provisioning.md

// in bt_init(), after esp_bt_dev_set_device_name:
ESP_ERROR_CHECK(esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_DISCOVERABLE));

// new task started from app_main:
static void enrollment_task(void *) {
    vTaskDelay(pdMS_TO_TICKS(ENROLLMENT_WINDOW_MS));
    esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_NON_DISCOVERABLE);
    ESP_LOGW(TAG, "enrollment window closed; device no longer discoverable");
    vTaskDelete(NULL);
}
// xTaskCreatePinnedToCore(enrollment_task, "enroll", 2048, NULL, 1, NULL, 0);
```

Pairing security (`ESP_SPP_SEC_AUTHENTICATE | ESP_SPP_SEC_ENCRYPT`) stays untouched.

- [ ] **Step 8: Add USB serial provisioning reader in `app_main` (before BT init).** Use the ESP-IDF UART0 driver reads rather than `fgetc(stdin)`, so the provisioning task never blocks or competes with the SPP tasks. Support CR, LF, or CRLF line endings, discard overlong lines with an error response, and handle `PROVISION_STATUS` as an exact command that prints only `PROVISION_STATUS:ok` or `PROVISION_STATUS:absent`.

```cpp
static void provisioning_task(void *) {
    uint8_t c;
    char line[96];
    size_t pos = 0;
    bool dropping = false;
    printf("PROVISION_READY\n");
    for (;;) {
        int n = uart_read_bytes(UART_NUM_0, &c, 1, pdMS_TO_TICKS(100));
        if (n <= 0) continue;
        if (c == '\n' || c == '\r') {
            if (dropping) {
                printf("PROVISION_ERR:line_too_long\n");
            } else if (pos > 0) {
                line[pos] = '\0';
                if (strcmp(line, "PROVISION_STATUS") == 0) {
                    provisioning_print_status();
                } else {
                    provisioning_handle_line(line);
                }
            }
            pos = 0;
            dropping = false;
        } else if (!dropping && pos < sizeof(line) - 1) {
            line[pos++] = (char)c;
        } else {
            dropping = true;
        }
    }
}
// xTaskCreatePinnedToCore(provisioning_task, "provision", 4096, NULL, 1, NULL, 0);
// start before bt_init(); include driver/uart.h and add uart to REQUIRES.
```

Include `driver/uart.h` and add the UART driver component to `src/CMakeLists.txt` `REQUIRES`. Zeroize `line` buffers after command handling where a key may be present (`provisioning_handle_line` already zeroes its decoded temp; clear `line` after dispatch in this task too). The command accepts CR, LF, or CRLF and emits exactly one response per completed command. Keep serial provisioning available during normal operation, but never route Bluetooth SPP bytes into it.

- [ ] **Step 9: Delete obsolete Arduino sources after confirming no references.**

```bash
grep -rn "storage/storage.h\|sensor/madgwick\|sensor/calibration\|sensor/quaternion\|sensor/i2c_bus_recovery\|status_led\|Arduino.h" Firmware_STASYS32/src/ Firmware_STASYS32/components/ || echo "no stale references"
# then:
git rm -r Firmware_STASYS32/src/storage Firmware_STASYS32/src/sensor
git rm Firmware_STASYS32/src/ota/bt_ota.cpp Firmware_STASYS32/src/ota/bt_ota.h Firmware_STASYS32/src/ota/bt_ota_commands.h
```

(OTA is re-implemented in Task 5 — do not run this step's `git rm` for `ota/` until Task 5 replacement is ready if Task 4 must build standalone; preferred order: perform OTA port (Task 5) first in the working tree, delete all at once. If tasks execute strictly in order, keep old `ota/` files excluded from build via `src/CMakeLists.txt` SRCS list instead of deleting, then delete in Task 5.)

- [ ] **Step 10: Build.**

Run: `python -m platformio run -d Firmware_STASYS32 -e esp32dev`
Expected: PASS. Record RAM/Flash. Fail the task if flash image > smallest OTA slot (0x1B0000).

- [ ] **Step 11: Commit.**

```bash
git add -A Firmware_STASYS32/
git commit -m "feat: ESP-IDF app_main with auth v2, provisioning, enrollment window"
```

## Task 5: Port Bluetooth OTA to ESP-IDF SPP

**Files:**
- Create: `Firmware_STASYS32/src/ota/bt_ota_commands.h`, `Firmware_STASYS32/src/ota/bt_ota.h`, `Firmware_STASYS32/src/ota/bt_ota.cpp`
- Modify: `Firmware_STASYS32/src/main.cpp` (SPP data routing + OTA pause of sensor TX)
- Modify: `Firmware_STASYS32/src/CMakeLists.txt` (add OTA source)
- Delete: old Arduino OTA files (if not deleted in Task 4 Step 9)
- Create: `Firmware_STASYS32/test/test_ota_grammar.py`

The protocol text commands, chunk size (128), and responses are frozen by the existing Flutter client: `GET_VERSION`→`VERSION=`, `OTA_START:size=N`→`OTA_READY`, `OTA_DATA:seq=N:base64=...`→`OTA_ACK:seq=N`, `OTA_FINISH:sha256=<64hex>`→`OTA_COMPLETE`, `OTA_ABORT`→`OTA_ABORTED`, `REBOOT`→`REBOOT_ACK` then restart.

- [ ] **Step 1: Write failing grammar test** `Firmware_STASYS32/test/test_ota_grammar.py`.

```python
import re, unittest

START = re.compile(r"OTA_START:size=(\d{1,10})")
DATA = re.compile(r"OTA_DATA:seq=(\d{1,6}):base64=([A-Za-z0-9+/]+={0,2})")
FINISH = re.compile(r"OTA_FINISH:sha256=([0-9a-fA-F]{64})")

class OtaGrammar(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(START.fullmatch("OTA_START:size=1728480").group(1), "1728480")
        m = DATA.fullmatch("OTA_DATA:seq=13499:base64=SGVsbG8=")
        self.assertEqual(m.group(1), "13499")
        self.assertIsNotNone(FINISH.fullmatch("OTA_FINISH:sha256=" + "ab" * 32))
    def test_invalid(self):
        self.assertIsNone(START.fullmatch("OTA_START:size="))
        self.assertIsNone(START.fullmatch("OTA_START:size=-1"))
        self.assertIsNone(DATA.fullmatch("OTA_DATA:seq=1:base64=@@@"))
        self.assertIsNone(DATA.fullmatch("OTA_DATA:seq=1:"))
        self.assertIsNone(FINISH.fullmatch("OTA_FINISH:sha256=" + "zz" * 32))

if __name__ == "__main__":
    unittest.main()
```

Run: `python -m unittest Firmware_STASYS32/test/test_ota_grammar.py -v` → PASS (grammar defined).

- [ ] **Step 2: Implement `bt_ota_commands.h`** — copy local file unchanged (state enum, `OTA_CHUNK_SIZE 128`, `OtaDataChunk_t`).

- [ ] **Step 3: Implement `bt_ota.h`.**

```cpp
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef enum {
    BT_OTA_IDLE, BT_OTA_RECEIVING, BT_OTA_WRITING,
    BT_OTA_VERIFYING, BT_OTA_COMPLETE, BT_OTA_ERROR
} BtOtaState_t;

#ifdef __cplusplus
extern "C" {
#endif

void btOtaInit(void);
void btOtaReset(void);
/* Feed one newline-terminated text line (already decoded ASCII). */
void btOtaHandleLine(const char *line);
/* True while an OTA transfer owns the link (sensor TX must pause). */
bool btOtaIsActive(void);
BtOtaState_t btOtaGetState(void);
#ifdef __cplusplus
}
#endif
```

- [ ] **Step 4: Implement `bt_ota.cpp`** as an ESP-IDF port of the local logic: `esp_ota_begin` (target = OTA partition != running), streaming `mbedtls_sha256`, base64 decoder (copy the existing table from local `bt_ota.cpp`), `xQueueCreate(4, entry)` + write task + binary semaphore for ACK, 60 s idle timeout via `esp_timer_get_time()`, strict `seq == expected_seq` monotonic check, `totalReceived + chunkLen <= expectedSize`, `esp_ota_end` + SHA compare + `esp_ota_set_boot_partition(target)` on success, `esp_ota_abort` on any failure/disconnect. Replace `SerialBT.printf(...)` with an injected TX function:

```cpp
// bt_ota.cpp
static char (*s_tx)(const char *fmt, ...) = nullptr;  // set by main.cpp
void btOtaSetTx(void (*tx)(const char *line));        // stores wrapper that prints "line\n"
```

Simplest concrete form: `void btOtaSetTx(void (*fn)(const char*));` where `main.cpp` passes a function that appends `\n` and calls `esp_spp_write` on the current handle. All OTA responses go through it.

- [ ] **Step 5: Route SPP data in `main.cpp`.** Upstream discards client bytes after auth (`if (state == AUTHENTICATED) break;`). Add: while authenticated, printable ASCII bytes (32..126, `\n`, `\r`) are accumulated into a 256-byte line buffer and dispatched to `btOtaHandleLine()` on newline; non-printable bytes are dropped (sensor traffic is TX-only; RX carries only OTA text). `GET_VERSION` allowed anytime when authenticated; other commands only in OTA-appropriate states (mirrors local behavior).

- [ ] **Step 6: Pause sensor TX during OTA.** In `sensor_task`'s send branch: `if (btOtaIsActive()) skip send this period` (keep sampling). Also skip the `SENS` diagnostic log spam during OTA (it goes to UART, harmless, but keep parity with local behavior of quiet BT).

- [ ] **Step 7: Build + size check.**

Run: `python -m platformio run -d Firmware_STASYS32 -e esp32dev`
Expected: PASS; image ≤ 0x1B0000 − margin (report actual bytes). If over: report (do NOT silently enlarge slots — flash geometry is user-gated).

- [ ] **Step 8: Run all firmware host tests.**

Run: `python -m unittest discover -s Firmware_STASYS32/test -v`
Expected: all OK.

- [ ] **Step 9: Commit.**

```bash
git add -A Firmware_STASYS32/
git commit -m "feat: port Bluetooth OTA to ESP-IDF SPP"
```

## Task 6: Release gates, docs, gitignore

**Files:**
- Create: `Firmware_STASYS32/scripts/check_release.py`, `Firmware_STASYS32/docs/provisioning.md`, `Firmware_STASYS32/docs/hardware-validation.md`
- Modify: `Firmware_STASYS32/.gitignore`, `Firmware_STASYS32/CLAUDE.md` (protocol/version updates)

- [ ] **Step 1: Implement `check_release.py`** — fail (exit 1) when: (a) any source file under `src/`/`components/` contains the string `12ebaf10h12fa9123z21sti` or any `PROVISION_KEY:` literal containing a valid 64-hex (i.e., real keys committed); (b) `FIRMWARE_VERSION` != expected release (`2.0.0`); (c) built `firmware.bin` missing when `--require-bin` passed. Print only file:line of findings, never key material.

- [ ] **Step 2: Bump version.** `Firmware_STASYS32/src/main.cpp` — add `#define FIRMWARE_VERSION "2.0.0"` near top (the Arduino `storage.h` that defined it was deleted in Task 4); `GET_VERSION` handler in `bt_ota.cpp` uses this macro. Log it at boot with `ESP_LOGI`.

- [ ] **Step 3: Write `docs/provisioning.md`**: generate a key (`python -c "import secrets; print(secrets.token_hex(32))"`), open serial monitor (`python -m platformio device monitor -d Firmware_STASYS32 --baud 115200`), send `PROVISION_KEY:<hex>` line, expect `PROVISION_OK`, verify with `PROVISION_STATUS` command (add trivial handler: `PROVISION_STATUS` → `PROVISION_STATUS:ok|absent`). Recovery: re-send a new key anytime; key never logged. Enrollment window: 5 minutes discoverable after boot, then bonded-only. Warn: key storage is plaintext NVS (no flash encryption in scope).

- [ ] **Step 4: Write `docs/hardware-validation.md`** as unchecked checklist: flash size via `esptool.py flash_id` (must be ≥ 4 MB for current table), I2C scan shows MPU 0x68 + QMC 0x2C or HMC 0x1E, pairing within window, auth with correct key OK / wrong key FAIL×3 disconnect, reconnect bonded after window, `GET_VERSION`→`VERSION=2.0.0`, full OTA success → reboot into new image, OTA disconnect mid-transfer → old image boots, interrupted power during OTA → old image boots. No pre-checked boxes.

- [ ] **Step 5: Update `.gitignore`** — ensure `.pio/`, `*.bin`, `*.elf`, `*.map`, `sdkconfig` (generated) are ignored; keep `sdkconfig.defaults` and `sdkconfig.esp32dev` tracked if upstream tracks them.

- [ ] **Step 6: Update `Firmware_STASYS32/CLAUDE.md`**: architecture section (ESP-IDF components), protocol section (36-byte XOR frame, auth v2 handshake with `gen=`, provisioning command), build commands, version 2.0.0, and note removed local features (LED/AHRS/power/factory-reset) with pointer to spec.

- [ ] **Step 7: Run full verification + release checks.**

```bash
python -m unittest discover -s Firmware_STASYS32/test -v
python Firmware_STASYS32/scripts/check_release.py --version 2.0.0
python -m platformio run -d Firmware_STASYS32 -e esp32dev
python Firmware_STASYS32/scripts/validate_partitions.py --flash-size 4194304  # adjust args to script
```

Expected: all PASS (partition flash-size value pending physical measurement — if unmeasured, run with 4194304 and note in hardware-validation.md as provisional).

- [ ] **Step 8: Commit.**

```bash
git add Firmware_STASYS32/scripts/ Firmware_STASYS32/docs/ Firmware_STASYS32/.gitignore Firmware_STASYS32/CLAUDE.md Firmware_STASYS32/src/
git commit -m "chore: firmware release gates, provisioning docs, version 2.0.0"
```

## Hardware validation gate (manual, not automatable here)

Run `docs/hardware-validation.md` on the physical ESP32 before claiming OTA-ready. Report every checkbox result honestly; unchecked items stay unchecked.
