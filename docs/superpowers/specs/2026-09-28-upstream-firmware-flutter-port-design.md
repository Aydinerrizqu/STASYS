# Design: Upstream STASYS Firmware and Flutter Protocol Port

**Date:** 2026-09-28
**Target branch:** `feature/figma-train-redesign` worktree
**Status:** Design approved in conversation; written specification pending user review

## Goal

Port the current upstream `dylemmas/STASYS_FW` architecture and wire protocol into this project while retaining the existing Bluetooth OTA capability. Update Flutter to authenticate with the new per-device protocol, parse the upstream sensor frame, and preserve its OTA workflow. Work directly in the existing `.worktrees/figma-train-redesign` worktree; do not switch or edit the primary worktree.

## Decisions

- Adopt upstream ESP-IDF firmware architecture, sensor HAL, 36-byte sensor frame, and authentication v2.
- Preserve local Bluetooth OTA, adapted for ESP-IDF SPP.
- Provision unique device keys through USB/serial. Flutter accepts a per-device key and stores it in secure storage associated with the Bluetooth MAC.
- Keep Bluetooth connectable and discoverable for a bounded enrollment window after boot, then disable discoverability. Bonded devices remain usable afterward.
- Port currently implemented upstream behavior only. Do not add unimplemented security-roadmap features such as per-frame MAC/replay protection, secure boot, flash encryption, or OTA-speed redesign.
- Do not carry over local LED patterns, factory reset button, power management, AHRS/calibration modules, or I2C recovery in this port. Reassess separately if needed.
- Work in the existing redesign worktree and preserve its current uncommitted UI changes.

## Firmware Design

Use upstream ESP-IDF components and `app_main` coordinator as the baseline: `components/sensors`, `components/app_protocol`, `components/system_config`, `src/main.cpp`, ESP-IDF SDK configuration, and partition table. Retain and adapt the local dual-slot OTA partition layout rather than upstream's single application slot, so interrupted updates can continue booting the prior image. Validate that ESP32 flash geometry and image size support the resulting partition map before considering OTA production-ready.

The upstream source currently has no Bluetooth OTA implementation. Port the existing local text-command OTA protocol (`GET_VERSION`, `OTA_START`, `OTA_DATA`, `OTA_FINISH`, `OTA_ABORT`, `REBOOT`) onto ESP-IDF SPP. Keep chunk size and ACK/retry behavior unchanged initially. OTA commands are accepted only after auth v2 succeeds. Sensor transmission pauses during OTA. Disconnect, timeout, invalid sequence, size mismatch, hash mismatch, and write failure abort the pending image without selecting it for boot. Preserve upstream sensor HAL and QMC5883P-first/HMC5883L-fallback behavior.

Add a physical enrollment/discoverability window after boot. Its duration is bounded and explicit in implementation. Pairing uses upstream authenticated/encrypted SPP security; after enrollment the device becomes non-discoverable without disabling already bonded connections.

Provisioning uses a serial command that accepts a validated 32-byte per-device key, writes it to NVS, verifies the stored value, and never logs the key. Authentication fails closed when the key is absent or invalid. Document the command and recovery/re-provisioning procedure. This does not claim hardware-backed key protection; flash encryption is out of scope.

## Protocol and Flutter Design

### Handshake

Firmware sends `READY v=2\n`, followed by `AUTH <64 hex nonce>\n`. Extend the greeting with a connection generation field, for example `READY v=2 gen=<uint32>`, because upstream includes generation in the HMAC transcript but does not transmit it to the client. Confirm exact grammar in shared tests before implementation. Flutter computes `HMAC-SHA256(key, b"STASYS-AUTH/v2\0" + bt_mac_bytes + generation_u32_le + nonce)` and sends `PROOF <64 hex chars>\n`. Firmware responds `OK\n` or `FAIL\n`; malformed proofs, absent keys, and repeated failures are rejected. Preserve any sensor or OTA response bytes coalesced after a handshake line instead of discarding them.

Store the key as a 32-byte hex string in platform secure storage, indexed by normalized Bluetooth MAC. Add a per-device key entry/edit action in Settings, with validation and no secret value in logs. Missing key blocks authentication and gives a clear setup message. Do not put keys in source, app assets, ordinary preferences, or firmware binaries. No old shared-secret fallback remains.

### Sensor packets

Parse upstream's 36-byte little-endian frame: `AA BB`, six float32 values (`ax`, `ay`, `az`, `gx`, `gy`, `gz`), three signed int16 magnetometer values, uint16 piezo, uint8 battery, and XOR of payload bytes 2 through 34. Keep the parser bounded and robust to fragmented/coalesced SPP reads. Reject invalid header/checksum and non-finite or out-of-range motion values before updating sensor state. Map magnetometer fields into protocol/model representation without changing existing scoring semantics unless a concrete consumer needs them.

### Bluetooth OTA integration

Keep the current Flutter OTA command flow and firmware asset delivery. Preserve dedicated OTA text parsing and isolate it from binary sensor parsing. Keep authentication active throughout OTA; query firmware version only on an authenticated link. Align firmware version reporting and Flutter expected version to the first port release, `2.0.0`. OTA abort/reboot responses must not be mistaken for sensor bytes.

## Error Handling and Recovery

- Missing, malformed, or wrong device key: do not authenticate; expose a corrective message without logging key or proof.
- Unsupported auth version, invalid nonce/generation, proof timeout, or repeated invalid proof: disconnect and return to a clean unauthenticated state.
- SPP disconnect during OTA: abort the active OTA handle; keep the previously bootable image selected.
- Partition too small, invalid image size, SHA-256 mismatch, or write failure: reject/abort without switching boot partition.
- Mandatory MPU/ADC HAL initialization failure: fail visibly at startup. Magnetometer absence follows upstream fallback/degraded behavior and emits zero magnetometer fields if neither supported device is present.
- Bluetooth discoverability ends after the enrollment window; bonded connections remain available.

## Test and Acceptance Criteria

1. Firmware builds with pinned ESP-IDF PlatformIO configuration and local dual-slot OTA partitions; partition validation confirms no overlap and fits confirmed flash geometry.
2. Host tests verify exact HMAC transcript bytes and proof vectors shared with Dart, successful auth, wrong-key rejection, malformed/fragmented/coalesced handshake input, timeout, and reconnect generation changes.
3. Dart unit tests verify secure per-MAC key CRUD/validation and protocol frame parsing for fragmentation, concatenation, checksum failures, NaN/infinity, and all sensor fields.
4. Flutter analysis and app tests pass; app retains live sensor updates and OTA state transitions.
5. OTA firmware-side host tests cover command parsing, chunk sequencing/bounds, SHA-256 verification, abort, and boot-partition selection behavior where feasible.
6. On hardware, verify MPU + QMC/HMC reads, pairing/discovery window, valid/invalid authentication, reconnect after window, Bluetooth OTA success, disconnect abort, reboot into updated image, and old-image fallback after interrupted update. Hardware checks must be explicitly reported; source/build tests alone do not establish them.

## Scope Boundaries

This change does not implement the upstream security roadmap beyond current upstream protocol behavior. Telemetry frames remain checksum-protected rather than cryptographically authenticated; Classic Bluetooth pairing and authenticated HMAC handshake are not a substitute for per-frame replay defense. Secure boot, flash encryption, hardware key protection, OTA chunk-size changes, OTA speed optimization, Wi-Fi OTA, local LED/power/AHRS features, and unrelated Figma redesign changes are excluded.

## Implementation Staging

1. Freeze and test shared frame/auth contracts; establish ESP-IDF build baseline and partition validation.
2. Port upstream firmware and sensor HAL; add provisioning and discoverability-window behavior.
3. Port Bluetooth OTA and test dual-slot recovery.
4. Add Flutter secure per-device key management, auth v2, 36-byte parser, and OTA compatibility.
5. Run static analysis, host tests, clean builds, then hardware validation.

## Risks and Explicit Assumptions

- The ESP32 board's actual flash capacity must be confirmed. The local partition map assumes space for two large app slots; upstream documents an unresolved 2 MB versus 3 MB discrepancy. No release claim is made until measured.
- Existing upstream handshake transcript binds the BT MAC and per-connection generation, but the generation is not sent by upstream. Adding it to the greeting is a narrowly scoped protocol extension and requires exact cross-language tests.
- `flutter_secure_storage` must support the app's Android target configuration and should not disrupt in-progress UI plugin registration changes in this worktree.
- Changing frame checksum from CRC16 to upstream XOR reduces accidental-error detection strength. The port follows upstream as requested; stronger authenticated frames remain separately scoped.
- Upstream acceleration semantics differ from local calibration/AHRS processing. Preserve upstream semantics for protocol compatibility and test real sensor behavior before adjusting scoring.
