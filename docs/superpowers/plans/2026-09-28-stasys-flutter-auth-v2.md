# STASYS Flutter Auth v2 and 36-byte Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Flutter app to authenticate each STASYS device using its provisioned key, parse the upstream 36-byte sensor frame, and retain the current Bluetooth OTA workflow.

**Architecture:** Add a secure key-store interface and per-MAC key setting; replace the legacy shared-secret handshake and 31-byte CRC parser with upstream HMAC auth v2 and bounded 36-byte XOR frames. Preserve OTA text mode as a distinct parser state and continue routing verified sensor data through the existing `SensorDataProvider` API.

**Tech Stack:** Flutter 3.35/Dart 3.9, Provider, `flutter_secure_storage`, `crypto` HMAC-SHA256, `flutter_bluetooth_serial`, flutter_test.

**Reference:** Spec `docs/superpowers/specs/2026-09-28-upstream-firmware-flutter-port-design.md`; paired firmware contract and plan `docs/superpowers/plans/2026-09-28-stasys-firmware-esp-idf-port.md`.

**Worktree:** Execute only in the current `feature/figma-train-redesign` worktree. The redesign has many unrelated uncommitted changes; preserve them and stage only listed files.

---

## Files and responsibilities

- Modify `ssa_app/pubspec.yaml`, `ssa_app/pubspec.lock`, Android plugin config if needed: add compatible `flutter_secure_storage` dependency and ensure Android min SDK remains supported (current minSdk 24).
- Create `ssa_app/lib/services/device_key_store.dart`: secure key CRUD by normalized Bluetooth MAC, format validation, injectable storage interface.
- Modify `ssa_app/lib/main.dart`: register one key-store provider/service and inject into Settings/Bluetooth providers without disturbing existing redesign providers.
- Modify `ssa_app/lib/providers/settings_provider.dart`: current device key operations and settings state, only if this remains the existing owner of app settings; never save secrets in SharedPreferences.
- Modify `ssa_app/lib/providers/bluetooth_provider.dart`: load key by selected device address; implement auth v2, generation transcript, 36-byte stream parser, OTA parser isolation, and non-secret error status.
- Modify `ssa_app/lib/screens/settings_screen.dart`: key field for the selected/bonded device, save/replace/clear affordances, input validation, masked display.
- Modify `ssa_app/lib/screens/connection_screen.dart`: show actionable message on missing key/auth rejection; preserve existing scan/connect/calibration behavior.
- Modify `ssa_app/lib/services/firmware_service.dart`: update expected firmware version to 2.0.0; keep current 128-byte OTA asset chunking.
- Create `ssa_app/test/unit/services/device_key_store_test.dart`, `ssa_app/test/unit/providers/bluetooth_provider_test.dart`, `ssa_app/test/unit/services/stasys_protocol_test.dart`; add widget tests to settings/connection tests if supported by current fakes.
- Do not modify current uncommitted redesign tests/files except the explicitly named connection/settings/provider test files when adding targeted cases.

## Frozen protocol contract

### HMAC transcript

- Domain bytes: UTF-8/ASCII bytes `STASYS-AUTH/v2` followed by exactly one NUL byte (15 bytes total).
- Bluetooth identity: six bytes parsed from the selected device MAC in displayed MAC octet order, e.g. `78:1C:3C:F5:16:18` -> `78 1c 3c f5 16 18`.
- Connection generation: unsigned 32-bit integer encoded little-endian.
- Nonce: exactly 32 bytes from 64 hex characters.
- Transcript: domain || identity || generationLE32 || nonce.
- Proof: HMAC-SHA256 with exactly 32 key bytes.
- App sends `PROOF <lowercase-hex-proof>\n`; accepts `OK\n`; rejects `FAIL\n` and all other responses.
- Greeting: `READY v=2 gen=<uint32>\nAUTH <nonce-hex>\n` (firmware plan adds generation because upstream omits it from transmitted greeting).

### Sensor frame

36 bytes: `AA BB` at 0..1; `ax,ay,az,gx,gy,gz` IEEE float32 little-endian at 2..25; `mag_x,mag_y,mag_z` signed int16 little-endian at 26..31; piezo uint16 little-endian at 32..33; battery uint8 at 34; XOR of bytes 2..34 at 35. Upstream XOR can miss even-bit corruptions; retain as protocol compatibility and do not claim cryptographic frame integrity.

## Task 1: Add secure key-store service and tests

**Files:**
- Modify: `ssa_app/pubspec.yaml`, `ssa_app/pubspec.lock`
- Create: `ssa_app/lib/services/device_key_store.dart`
- Create: `ssa_app/test/unit/services/device_key_store_test.dart`

- [ ] **Step 1: Add dependency and resolve packages.** Add `flutter_secure_storage: ^9.2.4` (compatible API; validate latest compatible release before applying) under dependencies; run `flutter pub get` from `ssa_app/`. Do not stage generated platform registrant changes unrelated to Android; keep pub's generated changes only when they are required by the selected package.
- [ ] **Step 2: Define injectable secure store interface.** In `device_key_store.dart`, implement `abstract interface class SecureKeyBackend { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`, `FlutterSecureKeyBackend` wrapping `FlutterSecureStorage`, and `DeviceKeyStore`.
- [ ] **Step 3: Implement key validation and per-MAC indexing.** Normalize MAC by removing `:`/`-`, requiring exactly 12 hex chars, uppercase to lowercase, and store under `stasys.device_key.<12-lower-hex>`. Keys are exactly 64 hex characters, normalized to lowercase before storage. Expose `saveForAddress`, `readForAddress`, `deleteForAddress`, `hasKeyForAddress`; never include key content in exceptions or logs.
- [ ] **Step 4: Add failing-then-passing tests with an in-memory backend.** Test MAC normalization, malformed MAC rejection, 64-hex acceptance, short/long/non-hex rejection, save/read/delete isolation for two MAC addresses, case normalization, and that fake backend receives only normalized names.
- [ ] **Step 5: Run service tests.** Run `flutter test test/unit/services/device_key_store_test.dart` from `ssa_app/`; expected PASS.
- [ ] **Step 6: Commit only dependency, service, lock, and test.** `git add ssa_app/pubspec.yaml ssa_app/pubspec.lock ssa_app/lib/services/device_key_store.dart ssa_app/test/unit/services/device_key_store_test.dart && git commit -m "feat: add per-device secure key storage"`.

## Task 2: Implement and test 36-byte frame codec

**Files:**
- Create: `ssa_app/lib/services/stasys_protocol.dart`
- Create: `ssa_app/test/unit/services/stasys_protocol_test.dart`

- [ ] **Step 1: Add packet model and frame encoder for tests.** Define immutable `StasysSensorPacket` with six motion values, three magnetometer ints, piezo and battery; implement pure `decodeFrame(Uint8List frame)` validating exact 36-byte frame, AA BB header, XOR, and finite/range-checked motion fields. Choose bounds aligned with current `_isValidSensorData`: acceleration abs ≤100 m/s², gyro abs ≤50 rad/s, battery ≤100 (confirm firmware percentage), piezo is full uint16.
- [ ] **Step 2: Write tests before decoder implementation.** Cases: known-byte vector with all fields, wrong length/header/checksum, NaN/Infinity, acceleration/gyro bounds, battery 101, signed magnetometer extremes. Expected initial failures identify absent codec.
- [ ] **Step 3: Implement incremental bounded parser.** `StasysFrameParser(maxBufferBytes: 36 * 4)` accepts arbitrary byte chunks and returns valid packets; resynchronize on `AA BB`, retain trailing `AA`, discard noise/corrupt candidates one byte at a time; never extend buffer beyond the configured cap. Track `checksumErrors` and `discardedBytes`.
- [ ] **Step 4: Test fragmentation and concatenation.** Feed 1-byte, partial-frame, two concatenated frames, noise before frame, corrupt frame containing an embedded header, and input chunk larger than buffer cap. Assert bounded buffer after every feed and correct next-frame recovery.
- [ ] **Step 5: Run protocol unit tests.** Run `flutter test test/unit/services/stasys_protocol_test.dart`; expected PASS.
- [ ] **Step 6: Commit codec and tests.** Commit only new service and test.

## Task 3: Implement auth v2 proof utility with cross-language vectors

**Files:**
- Modify: `ssa_app/lib/services/stasys_protocol.dart`
- Modify: `ssa_app/test/unit/services/stasys_protocol_test.dart`
- Dependency already present: `crypto: ^3.0.3`.

- [ ] **Step 1: Add exact transcript/HMAC tests.** Use key bytes 0..31, identity `010203040506`, generation 1, nonce 32 zero bytes. Assert transcript has length 57 and exact byte boundaries; compare proof hex to Python `hmac.new(key, transcript, hashlib.sha256).hexdigest()` generated from the firmware plan's `test_protocol_contract.py`. Keep one literal golden vector in Dart tests after computing it from that Python reference, not by calling the Dart helper under test.
- [ ] **Step 2: Implement `buildAuthTranscript` and `computeAuthProof`.** Parse MAC to six bytes in display order; write generation using `ByteData.setUint32(0, generation, Endian.little)`; encode domain with `ascii.encode('STASYS-AUTH/v2')` plus `0`; use `Hmac(sha256, key).convert(transcript).bytes`; return lowercase hex. Reject malformed MAC, generation outside uint32, nonce not exactly 32 bytes, key not exactly 32 bytes.
- [ ] **Step 3: Run protocol tests and verify golden equality.** Run focused Flutter test and Python vector; expected transcript/proof bytes match exactly.
- [ ] **Step 4: Commit auth utility with its tests.** `git add ssa_app/lib/services/stasys_protocol.dart ssa_app/test/unit/services/stasys_protocol_test.dart && git commit -m "feat: add STASYS auth v2 and frame codec"`.

## Task 4: Refactor BluetoothProvider handshake and sensor stream

**Files:**
- Modify: `ssa_app/lib/providers/bluetooth_provider.dart`
- Modify: `ssa_app/lib/services/stasys_protocol.dart`
- Create: `ssa_app/test/unit/providers/bluetooth_provider_test.dart`
- Modify: `ssa_app/main.dart` (key-store DI only; path is `ssa_app/lib/main.dart`)

- [ ] **Step 1: Add test seams.** Inject `DeviceKeyStore` into `BluetoothProvider`, with required constructor parameter and setter/constructor wiring in `main.dart`. Make transport input and output testable through a narrow internal interface or public `handleIncomingBytesForTest` guarded by `@visibleForTesting`; do not introduce a generic Bluetooth framework.
- [ ] **Step 2: Write handshake test cases.** A fake byte stream supplies fragmented `READY v=2 gen=7`, `AUTH <nonce>`, and `OK`, captures proof output, then sends packet bytes. Test valid proof, wrong/missing key (no proof write, auth remains false and clear error set), unsupported version, invalid MAC/nonce/generation, `FAIL`, oversized line, reconnect clears parser/buffers/auth, and `OK\n` coalesced with first binary packet retains packet bytes.
- [ ] **Step 3: Replace shared secret and old auth phases.** Remove `_secretKey`, SHA256(shared secret) comparison, old `AUTH_CHALLENGE` message and `waitingForHash` phase. New phases: `waitingForGreeting`, `waitingForNonce`, `waitingForAuthResult`, `streaming`, `otaMode`. On connect, fetch secure key using normalized `device.address`; if absent, stop auth promptly, set `lastConnectionError` to a non-secret setup message, disconnect, and return `false`.
- [ ] **Step 4: Implement bounded line reader preserving trailing bytes.** Parse CRLF/LF with 160-byte auth max. Require exact `READY v=2 gen=<0..4294967295>` then exact `AUTH <64 hex>`. Preserve any bytes remaining in `_textBuffer` after `OK\n` by feeding them to binary parser. Reject after three `FAIL`/malformed attempts or firmware timeout; never log key, proof, or nonce.
- [ ] **Step 5: Parse stream frames with `StasysFrameParser`.** Remove local `_PACKET_SIZE=31`, `_verifyCrc16`, and duplicate byte synchronization code. For each `StasysSensorPacket`, call current `SensorDataProvider.updateAllData(ax,ay,az,gx,gy,gz,battery,piezo)`; magnetometer remains represented by packet but has no current provider consumer. Update `checksumErrorsCount` getter to codec stats and preserve packet counts/loss semantics.
- [ ] **Step 6: Keep OTA text isolated.** In `otaMode`, feed only `_otaTextBuffer`; in streaming, continue extracting ASCII OTA replies without feeding those bytes into frame parser only as existing implementation requires. Confirm outgoing `GET_VERSION` and OTA commands remain usable only after auth. Reset parser on exit/reconnect.
- [ ] **Step 7: Run provider tests and app analyzer.** Run `flutter test test/unit/providers/bluetooth_provider_test.dart` and `flutter analyze`; expected all new tests pass, no source errors.
- [ ] **Step 8: Commit provider integration.** Commit only provider, protocol service if changed, main DI, and tests.

## Task 5: Add secure per-device key UI and connection errors

**Files:**
- Modify: `ssa_app/lib/screens/settings_screen.dart`
- Modify: `ssa_app/lib/screens/connection_screen.dart`
- Modify: `ssa_app/lib/providers/bluetooth_provider.dart` (error getter only if not already added)
- Create/modify: `ssa_app/test/unit/screens/device_key_settings_test.dart` or current screen test.

- [ ] **Step 1: Add settings UI tests.** Cover a masked key status for selected/bonded STASYS device, empty state, exact 64-hex validation, save success, invalid input rejection, clear confirmation, and ensure saved key does not render as plaintext after submit.
- [ ] **Step 2: Add a device picker for bonded/selected STASYS units.** Reuse `BluetoothProvider.devicesList`, selected device and `FlutterBluetoothSerial.getBondedDevices()`; only show addresses/names, not secrets. Keep the user's uncommitted redesign layout intact and add a focused key section (suggested placement: directly after the existing `_buildBluetoothSection()` entry in the ListView, wrapped in `_buildSectionHeader('DEVICE KEY')` following the existing section pattern).
- [ ] **Step 3: Implement the key entry UI.** A `TextField` (obscured while editing, `InputFormatters` limiting to hex chars, max 64) with SAVE/CLEAR buttons; on save call `DeviceKeyStore.saveForAddress(mac, key)`; show masked display (`a1b2…9f00` style: first 4 + last 4 of stored key) plus status (KEY SET / NO KEY). On invalid input show an inline error using `StsysTheme.error`; never keep the raw value in state after save (clear the controller).
- [ ] **Step 4: Surface missing-key and auth-rejection errors in connection flow.** `BluetoothProvider` exposes `String? lastConnectionError` (non-secret, set by Task 4: e.g. `no_key`, `auth_rejected`, `bad_greeting`). In `connection_screen.dart` `_connectDevice` (the branch after `await btProvider.connectToDevice(device)` where `btProvider.isConnected && btProvider.isAuthenticated` is false), replace silent fall-through with a `ScaffoldMessenger` SnackBar mirroring the existing error style (see the `Firmware check error` SnackBar at ~line 218): message text `Kunci perangkat belum diisi atau ditolak. Simpan kunci di Settings → Device Key, lalu coba lagi.` with `backgroundColor: StsysTheme.error`.
- [ ] **Step 5: Widget tests.** Run `flutter test test/unit/screens/device_key_settings_test.dart` (or the nearest existing settings-screen test file if the project pattern prefers extending it); expected PASS.
- [ ] **Step 6: Commit UI and error surfacing.** Commit only settings_screen, connection_screen, provider error getter if touched, and their tests.

## Task 6: Align firmware version, OTA asset, and OTA flow with ported firmware

**Files:**
- Modify: `ssa_app/lib/services/firmware_service.dart`
- Modify: `ssa_app/lib/providers/ota_provider.dart` (only if flow changes are required by Task 4 results)
- Verify: `ssa_app/lib/providers/ota_provider.dart`, `ssa_app/lib/screens/ota_update_screen.dart` unchanged behavior otherwise

- [ ] **Step 1: Update expected firmware version.** In `firmware_service.dart` change `static const String expectedVersion = '1.4.0';` to `'2.0.0'`. This must match `FIRMWARE_VERSION` from the firmware plan (Task 6 Step 2).
- [ ] **Step 2: Keep chunking contract.** Confirm `chunkSize = 128` remains (firmware OTA parser assumes ≤128 raw bytes per `OTA_DATA`); no change expected — verify by reading `firmware_service.dart`, do not edit.
- [ ] **Step 3: Replace the bundled firmware asset.** After the firmware plan produces `Firmware_STASYS32/.pio/build/esp32dev/firmware.bin`, copy it to `ssa_app/assets/firmware/stasys_fw.bin` (the pubspec asset path already exists). If the firmware build is not yet available, leave the old asset in place and note it as a blocking hand-off item — the OTA prompt would offer a stale image otherwise.
- [ ] **Step 4: Verify OTA is gated on auth.** In `ota_provider.startOta` / `bluetooth_provider` OTA methods, confirm `sendOtaStart` etc. already require `_isConnected` (they do) — add an explicit `isAuthenticated` guard to `sendOtaStart`, `getFirmwareVersion`, `sendRebootCommand` if absent, returning an error string rather than sending.
- [ ] **Step 5: Run existing provider/service tests.** Run `flutter test test/unit/providers test/unit/services` from `ssa_app/`; expected PASS (no existing tests target firmware_service; new failures = regression to fix).
- [ ] **Step 6: Commit version/asset/guard changes.** Commit `firmware_service.dart`, any `ota_provider.dart`/`bluetooth_provider.dart` guard edits, and `ssa_app/assets/firmware/stasys_fw.bin` (binary asset — ensure not gitignored before staging).

## Task 7: Full application verification

- [ ] **Step 1: Analyzer.** Run `flutter analyze` from `ssa_app/`; expected: no errors (existing warnings unrelated to this change are reported, not fixed).
- [ ] **Step 2: Full unit suite.** Run `flutter test` from `ssa_app/`; expected PASS, including the redesign's existing uncommitted tests (they must not be modified by this work).
- [ ] **Step 3: Debug build.** Run `flutter build apk --debug`; expected PASS. Note: root `CLAUDE.md` documents a pub-cache patch requirement for `flutter_bluetooth_serial` on release builds — debug build does not need it; release build verification is out of scope here.
- [ ] **Step 4: Commit any analyzer/test fixes** with `fix:` prefix, staged files only.

## Hardware validation gate (manual)

The paired firmware plan's `docs/hardware-validation.md` checklist covers device side. App-side hardware checks (report honestly, do not pre-check):

- [ ] Pair STASYS inside enrollment window; scan in app finds it.
- [ ] Save correct key in Settings → Device Key; connect authenticates; muzzle trace updates.
- [ ] Wrong key: connect fails with the settings-guidance error, no auth bypass.
- [ ] Reconnect after 5-minute window (bonded) still authenticates.
- [ ] OTA prompt appears for 1.4.0→2.0.0 and completes (128-byte chunks, ~45 min budget unchanged).
- [ ] Mid-OTA disconnect: device aborts, app shows failure state, old firmware still boots.
- [ ] Magnetometer fields decode without rejecting packets (visual: no packet-loss spike).

## Out of scope (from spec — do not implement here)

Per-frame authenticated MAC/replay protection, secure boot, flash encryption, hardware-backed key storage, OTA chunk-size/speed changes, Wi-Fi OTA, restoring LED/factory-reset/power/AHRS features, Figma redesign changes.