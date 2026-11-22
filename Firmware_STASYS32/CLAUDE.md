# STASYS ESP32 Firmware — Development Guide

> **Note**: This is the firmware-specific companion to the root `CLAUDE.md`.
> For Flutter app development, see `ssa_app/CLAUDE.md`.

## Project Overview

ESP32 firmware for the STASYS shooter stability analyzer.

| Component | Details |
|-----------|---------|
| MCU | ESP32 DEVKIT V1 (ESP32-D0WD-V3, rev v3.1) |
| IMU | MPU6050 (6-axis accel+gyro, I2C 0x68) + QMC5883L (0x2c) + HMC5883L (0x1e) |
| Comm | Bluetooth Classic SPP (ESP-IDF `bt` component, `ESP_SPP_SEC_NONE`) |
| Device Name | `STASYS-%04X` (upper 4 hex of the BT MAC) |
| Framework | **ESP-IDF** (`platform = espressif32@6.12.0`, `framework = espidf`) |
| Version | STASYS_FW v2 (`FIRMWARE_VERSION "2.0.0"`, `src/main.cpp:22`) |
| MAC | 78:1c:3c:f5:16:18 |

> **History**: 2026-05-05 migrated from Arduino to the modular `dylemmas/STASYSFW`
> (FreeRTOS, CRC16-CCITT, Madgwick AHRS, ZUPT, NVS storage).
> 2026-09-28 ported to **ESP-IDF** (`components/` layout) and adopted the
> auth-free 36-byte XOR protocol from upstream `5f955e8`.
> **The Arduino-era files described in older revisions of this file
> (`src/storage/`, `src/sensor/`, `madgwick.h`, `quaternion.h`, `calibration.h`)
> no longer exist.**

---

## Architecture

### Layout (ESP-IDF)

```
Firmware_STASYS32/
├── src/
│   ├── main.cpp                  # app_main, SPP setup, 2 FreeRTOS tasks
│   └── ota/                      # DEAD CODE — not in src/CMakeLists.txt SRCS
│       ├── bt_ota_commands.h     # OTA command IDs, structs
│       ├── bt_ota.h
│       └── bt_ota.cpp
├── components/
│   ├── app_protocol/
│   │   ├── include/app_protocol.h   # 36-byte packet layout + payload struct
│   │   └── app_protocol.cpp        # staysys_packet_serialize() — XOR checksum
│   ├── sensors/
│   │   ├── sensor_hal.h           # HAL init + read API
│   │   └── sensor_hal.cpp         # MPU6050 + mag + ADC, I2C recovery
│   └── system_config/
│       ├── system_config.h       # pinout (STASYS_*_GPIO) + HAL handles
│       └── system_config.c
├── components/system_config.h          # DUPLICATE of the header above — keep both in sync
├── partitions_dual_ota.csv
├── platformio.ini                        # espressif32@6.12.0, framework = espidf
├── sdkconfig.defaults / sdkconfig.esp32dev
├── test/                                 # Python contract tests (see below)
├── tools/stasys_packet.py                # reference packet builder
└── scripts/validate_partitions.py
```

> **The duplicate `components/system_config.h` and
> `components/system_config/system_config.h` must be kept in sync** — edit both
> together (or delete one only after updating all includes).

### FreeRTOS Tasks

Only **two** tasks are created in `app_main` (`src/main.cpp:334-335`):

| Task | Stack | Prio | Core | Description |
|------|-------|------|------|-------------|
| `sensor` | 6144 | 1 | 1 | Read IMU @ 100Hz, build + send 36-byte frames |
| `battery` | 3072 | 1 | 0 | Monitor battery voltage / piezo ADC |

The Bluetooth SPP callback runs on the BT task (not a dedicated app task).

---

## Communication Protocol

### Binary Packet Format (STASYS_FW v2 — 36 bytes, XOR checksum)

```
[0xAA] [0xBB] [ax f32] [ay f32] [az f32] [gx f32] [gy f32] [gz f32]
[mag_x i16] [mag_y i16] [mag_z i16] [piezo u16] [battery u8] [xor u8]
Total: 36 bytes
```

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0xBB` |
| 2 | 4 | ax | float (m/s²) |
| 6 | 4 | ay | float (m/s²) |
| 10 | 4 | az | float (m/s²) |
| 14 | 4 | gx | float (rad/s) |
| 18 | 4 | gy | float (rad/s) |
| 22 | 4 | gz | float (rad/s) |
| 26 | 2 | mag_x | int16 raw magnetometer |
| 28 | 2 | mag_y | int16 raw |
| 30 | 2 | mag_z | int16 raw |
| 32 | 2 | piezo | uint16 ADC peak |
| 34 | 1 | battery | uint8 percentage |
| 35 | 1 | checksum | **XOR over bytes 2..34** |

Serializer: `components/app_protocol/app_protocol.cpp` →
`staysys_packet_serialize()`. The checksum loop is
`for (i = 2; i < 35; ++i) output[35] ^= output[i];`.

### Handshake (no authentication)

```
ESP32 → App: "READY v=2\n"   (sent once, when SPP opens)
App → ESP32: (nothing — the firmware ignores inbound data)
ESP32 → App: streams 36-byte frames @ 100Hz
```

- SPP runs with `ESP_SPP_SEC_NONE` — no pairing, no encryption, no key.
- **Anyone within Bluetooth range can connect and read the stream.** This is a
  conscious decision (see Progress 2026-10-18 in the root `CLAUDE.md`).
- The greeting is sent from the SPP open callback (`src/main.cpp`, ~line 77).
- The app parser only accepts exactly `READY v=2`
  (`ssa_app/lib/services/stasys_protocol.dart` → `parseGreeting`).
- The firmware does **not** answer `GET_VERSION` — the app waits out a ~3 s
  timeout before skipping the OTA prompt.

---

### OTA Firmware Update via Bluetooth — implemented 2026-05-23, **currently dead code**

> ⚠️ `src/ota/*` is **not compiled** (not in `src/CMakeLists.txt` SRCS), so this
> flow does not run on the current firmware. It is documented here because the
> Flutter side still implements the protocol and the design is worth keeping.
> Before reviving it: replace the stale `extern isAuthenticated` guard with
> `g_state != BT_OTA_IDLE`, and re-check the 128-byte chunk size against the
> current BT RX buffer.

**Text Commands** (terminated by `\n`):

| Command | Direction | Response |
|---------|-----------|----------|
| `GET_VERSION` | App → ESP32 | `VERSION=X.Y.Z` |
| `OTA_START:size=N` | App → ESP32 | `OTA_READY` or `OTA_ERR:reason` |
| `OTA_DATA:seq=N:base64=...` | App → ESP32 | `OTA_ACK:seq=N` or `OTA_NAK:seq=N:err` |
| `OTA_FINISH:sha256=HASH` | App → ESP32 | `OTA_COMPLETE` or `OTA_ERR:reason` |
| `OTA_ABORT` | App → ESP32 | `OTA_ABORTED` |
| `REBOOT` | App → ESP32 | (reboots, no response) |

**Protocol flow**:
1. App connects + authenticates (existing challenge-response)
2. App sends `GET_VERSION` → compare with assets version
3. If update needed: `OTA_START:size=N` → `OTA_READY`
4. For each 128-byte chunk: base64 encode → `OTA_DATA:seq=X:base64=...` → wait `OTA_ACK:seq=X`
5. After all chunks: `OTA_FINISH:sha256=HASH` → ESP32 verifies SHA256 → `OTA_COMPLETE`
6. App sends `REBOOT` → ESP32 calls `esp_ota_set_boot_partition()` + `esp_restart()`
7. ESP32 boots new firmware from alternate partition (dual-bank OTA)

**State Machine** (`BtOtaState_t` in `bt_ota_commands.h`):
- `BT_OTA_IDLE` — default state
- `BT_OTA_RECEIVING` — receiving chunks
- `BT_OTA_WRITING` — (same as RECEIVING, for future use)
- `BT_OTA_VERIFYING` — after OTA_FINISH, computing SHA256
- `BT_OTA_COMPLETE` — ready to reboot
- `BT_OTA_ERROR` — error occurred

**Files**:
- `src/ota/bt_ota_commands.h` — BtOtaState_t enum, OTA_CHUNK_SIZE=128
- `src/ota/bt_ota.h` — declarations: btOtaInit(), btOtaReset(), btOtaTask(), btOtaGetState(), btOtaIsActive()
- `src/ota/bt_ota.cpp` — Dual-task FreeRTOS (drain + write), base64 decoder, SHA256 streaming, command parser
- `src/main.cpp` — FIRMWARE_VERSION macro (now `"2.0.0"`, line 22).
  The `storage.h` / `storage.cpp` NVS helpers these files used to call **no longer exist**.

**Implementation details (2026-05-23)**:
- **Dual-task architecture**: drain task (priority 2, Core 0) + write task (priority 1, Core 0)
- **Drain task**: reads SerialBT byte-by-byte, parses text commands, sends ACKs. `taskYIELD()` after EVERY byte prevents BT RX buffer overflow.
- **Write task**: receives chunks from FreeRTOS queue (size 4), calls `esp_ota_write()` (~500ms blocking), updates SHA256
- **Binary semaphore**: write task signals drain task when chunk is done (non-blocking ACK)
- **Queue size**: 4 entries × 128 bytes = 512 bytes total buffer
- **Chunk size**: 128 bytes raw → ~172 bytes base64 → ~200 bytes BT transfer (fits ESP32 BT RX buffer)
- **Speed**: ~13,500 chunks @ 200ms Flutter delay + 500ms esp_ota_write = ~45 minutes for 1.7MB
- `isAuthenticated` (main.cpp, non-static volatile) guards btOtaTask from reading SerialBT during auth phase
- `btOtaTask()` loops: `if (!isAuthenticated) { btOtaReset() if needed; delay(50); continue; }`
- `btOtaReset()` — properly aborts OTA handle, frees SHA context, resets state. Called on disconnect.
- `GET_VERSION` always allowed (no state check). Other commands require `BT_OTA_IDLE`.
- Version stored in NVS (`config` namespace, key `fw_version`) and compile-time `FIRMWARE_VERSION` macro.
- After `OTA_COMPLETE`, ESP32 saves version to NVS via `storageSetFirmwareVersion()`.
- `btOtaIsActive()` flag pauses sensor task during OTA to prevent BT buffer contention

**Status**: ✅ Production-ready, tested E2E with 1.7MB firmware. See `ssa_app/CLAUDE.md` for Flutter-side implementation.

---

## Build & Upload

### Build Firmware
```bash
cd Firmware_STASYS32
python -m platformio run -e esp32dev
```

> ⚠️ **The build path must not contain spaces.** The repo lives in
> `d:\Aydiner\Projek Flutter SSA\` and ESP-IDF's CMake tools reject that.
> Copy `Firmware_STASYS32/` to a space-free path (e.g. `D:\fw\`) and build there.
> `IDF_PATH` is normally unset in the shell — PlatformIO supplies its own
> `framework-espidf` package, but the CMake step still needs the space-free cwd.

### Upload to ESP32
```bash
# Find COM port
powershell -Command "[System.IO.Ports.SerialPort]::GetPortNames()"

# Upload (COM3 detected 2026-05-23)
python -m platformio run -e esp32dev --target upload --upload-port COM3
```

### Monitor Serial Output
```bash
python -m platformio device monitor --port COM3 --baud 115200
```

---

## Key Modules

### `components/app_protocol/` — packet format
- `include/app_protocol.h`: `STASYS_PACKET_SIZE 36`, `STASYS_PACKET_PAYLOAD_SIZE 33`,
  header bytes `0xAA` / `0xBB`, payload struct, `staysys_packet_serialize()`.
- `app_protocol.cpp`: little-endian float/int writers + XOR checksum over bytes 2..34.

### `components/sensors/` — sensor HAL
- `sensor_hal.h/.cpp`: MPU6050 (0x68) + QMC5883L (0x2c) + HMC5883L (0x1e) over I2C,
  plus ADC for the piezo channel and the battery divider.
- I2C bus recovery on init failure.

### `components/system_config/` — pinout + handles
- `system_config.h`: `STASYS_BATTERY_GPIO 39`, `STASYS_PIEZO_GPIO 35`,
  `STASYS_I2C_SDA 21`, `STASYS_I2C_SCL 22`, MPU/mag addresses,
  `STASYS_PACKET_PERIOD_US 10000` (100 Hz), battery thresholds 3.0–4.2 V,
  `STASYS_VOLTAGE_DIVIDER_RATIO 2.0f`.
- `system_config.c`: HAL handle struct + init.
- **Duplicate header**: `components/system_config.h` mirrors
  `components/system_config/system_config.h` — keep both in sync.

### Dead code — `src/ota/`
`src/ota/bt_ota.cpp` / `.h` / `bt_ota_commands.h` are **not compiled** (they are not
in `src/CMakeLists.txt` SRCS). They still reference `extern volatile bool
isAuthenticated`, which no longer exists — enabling them would fail to link.
Replace the guard with `g_state != BT_OTA_IDLE` before reviving Bluetooth OTA.

---

## Memory Usage

Last measured on the Arduino-era build:
```
RAM:   22.1% (72580 / 327680 bytes)
Flash: 97.3% (1721769 / 1769472 bytes)
```
> The ESP-IDF port has not been re-measured since the 2026-09-28 migration.
> Re-run `pio run` and read the size report from the build output before
> relying on these numbers.

---

## Flutter App Compatibility

The app and the firmware must agree byte-for-byte on the wire format.
Three places define it — keep all three in sync:

| Where | File |
|-------|------|
| Firmware | `Firmware_STASYS32/components/app_protocol/app_protocol.cpp` |
| Firmware reference tool | `Firmware_STASYS32/tools/stasys_packet.py` |
| App | `ssa_app/lib/services/stasys_protocol.dart` |

`Firmware_STASYS32/test/test_protocol_contract.py` asserts that the three agree
and that the checksum covers exactly bytes 2..34.

### Protocol history

| Aspek | Arduino era | STASYS_FW v1 | STASYS_FW v2 (current) |
|-------|-------------|--------------|------------------------|
| Header | `0xAA 0xBB` | `0xAA 0xBB` | `0xAA 0xBB` |
| Checksum | XOR (1 byte) | CRC16-CCITT (2 bytes) | **XOR (1 byte)** |
| Packet size | 30 bytes | 31 bytes | **36 bytes** |
| Magnetometer | — | — | **3 × int16** |
| Auth | Text SHA256 | Text SHA256 | **None** |
| Architecture | Polling loop | FreeRTOS 4 tasks | **ESP-IDF, 2 tasks** |
| Framework | Arduino | Arduino | **ESP-IDF** |

---

## Known Issues / TODOs

### Pending
- [ ] **OTA Speed Optimization** — Current: 45 min for 1.7MB. Target: 10-15 min. Approaches: larger chunks (256 bytes), burst mode (batched ACKs), reduced Flutter delay. Needs incremental testing.
- [ ] **Bluetooth OTA is not compiled** — `src/ota/*` is dead code; reviving it needs the `isAuthenticated` guard replaced with `g_state != BT_OTA_IDLE`.
- [ ] **`GET_VERSION` is not implemented** on the firmware — the app waits ~3 s on every connect before skipping the OTA prompt.
- [ ] **Hardware acceptance** — the current 36-byte/XOR ESP-IDF firmware has never been flashed to hardware. Flash → reboot → connect to `STASYS-XXXX` → immediate stream, no key.

### Fixed (2026-05-05)
- [x] Firmware rebuild dari STASYS_FW GitHub
- [x] Fixed `storage.h`: missing `#include <stddef.h>` for `size_t`
- [x] Fixed `storage.h`: `storageLoadConfig` return type `void` not `bool`
- [x] Removed duplicate `quaternion.cpp` (header-only)
- [x] Build successful: RAM 22%, Flash 54.5%

### Fixed (2026-05-23) ✅
- [x] **OTA Bluetooth Firmware Update** — Full E2E working! See OTA Firmware Update section above.
  - `bt_ota.cpp` — dual-task FreeRTOS (drain + write), semaphore ACK, taskYIELD per byte
  - `main.cpp` — `btOtaIsActive()` pauses sensor task during OTA
  - `isAuthenticated` (non-static volatile) guards btOtaTask from consuming auth bytes
  - Partition table: `partitions_dual_ota.csv` (app0=ota_0, app1=ota_1, ~1.7MB each)
  - Tested E2E with 1.7MB firmware via COM3, uploaded successfully
- [x] Uploaded to ESP32 via COM12

---

## Development Notes

- Chip: ESP32-D0WD-V3 (revision v3.1)
- MAC: 78:1c:3c:f5:16:18
- CPU: 240MHz
- Platform: espressif32 v6.12.0
- Framework: **espidf**
- Build output: `.pio/build/esp32dev/firmware.bin`
- **Build path must not contain spaces** — ESP-IDF's CMake tools reject
  `d:\Aydiner\Projek Flutter SSA\`. Copy the folder to a space-free path to build.

### Firmware tests

`pytest` is not installed on this machine. Run each file directly — they are
`unittest` modules with a `__main__` block:

```bash
cd Firmware_STASYS32
python test/test_protocol_contract.py   # 5 tests
python test/test_sens_log.py            # 13 tests
python test/test_stasys_packet.py       # 8 tests
python test/test_validate_partitions.py # 13 tests
```
39 tests total, all passing as of 2026-11-22.