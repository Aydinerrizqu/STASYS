# STASYS ESP32 Firmware — Development Guide

> **Note**: This is the firmware-specific companion to the root `CLAUDE.md`.
> For Flutter app development, see `ssa_app/CLAUDE.md`.

## Project Overview

ESP32 firmware for the STASYS shooter stability analyzer.

| Component | Details |
|-----------|---------|
| MCU | ESP32 DEVKIT V1 |
| IMU | MPU6050 (6-axis accel+gyro, I2C 0x68) |
| Comm | Bluetooth Classic SPP |
| Device Name | `"STASYS-XXXX"` (chip MAC-based) |
| Version | Upstream original (`dylemmas/STASYSESP32`) — **single-file, polling-based** |

> **Migration (2026-04-22)**: Firmware di-reset ke versi awal/original dari upstream `dylemmas/STASYSESP32`.
> Branch: `migrasi_firmware_awal` (single-file `src/main.cpp`, ~297 lines).
> Flutter app **fully compatible** — text auth + dual-mode parser handles upstream protocol.

---

## Architecture

> **2026-04-22**: Simplified to single-file upstream original. No modular architecture.

### Single-File Structure (upstream original)

```
Firmware_STSYS32/
├── src/
│   └── main.cpp   (~297 lines) — sensor reading, Bluetooth, authentication, data transmission
└── platformio.ini
```

No separate modules — all inline in main.cpp. Uses simple polling loop (not FreeRTOS tasks).

---

## Communication Protocol

> Flutter app is **fully compatible** with upstream original protocol (text auth + 30-byte float binary with XOR checksum).

### Binary Packet Format (upstream original)

```
[0xAA] [0xBB] [ax(float4)] [ay(float4)] [az(float4)] [gx(float4)] [gy(float4)] [gz(float4)] [piezo(uint16)] [battery(uint8)] [xor_checksum(uint8)]
Total: 30 bytes
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
| 26 | 2 | piezo | uint16 ADC raw |
| 28 | 1 | battery | uint8 percentage |
| 29 | 1 | checksum | XOR of bytes 2..28 |

### Authentication (upstream original — TEXT-BASED, BREAKING CHANGE)

```
Flutter/PC → ESP32: (connect)
ESP32 → Flutter/PC: "READY\n"
Flutter/PC → ESP32: (send text challenge string)
ESP32 → Flutter/PC: SHA256(challenge + SECRET_KEY) as hex string\n
ESP32 → Flutter/PC: (starts streaming if valid)
```

**Auth is text-based via println/readStringUntil**, bukan binary HMAC-SHA256.
**Secret Key**: `12ebaf10h12fa9123z21sti`

### Oversampling

- Sensor read: 1000Hz (1kHz) internal
- Data send: 100Hz (10ms interval)
- 10 samples per packet window — peak accel, average gyro, peak piezo

---

## Known Issues / TODOs

### Pending
- [ ] No modular features (OTA, storage, LED, session mgmt) — stripped to single-file original

### Fixed (modular firmware era)
- [x] CRC scope mismatch — `encodePacket()` fixed to `3+len`
- [x] MPU6050 not responding → degraded mode fallback
- [x] RecoveryTask watchdog timeout — `esp_task_wdt_reset()` in loop
- [x] CMD_START_SESSION auth guard blocking Flutter — removed `__isAuthenticated` check
- [x] PktRawSample sizeof mismatch — confirmed 24 bytes

---

## Flutter App Compatibility

> **Synced** (2026-04-22): Flutter app (`ssa_app/`) now supports upstream original protocol. **Fully compatible** with `dylemmas/STASYSESP32`.

### Protocol Comparison

| Aspek | Modular (STSYS32) | Upstream Original (STASYSESP32) |
|-------|------------------|----------------------------------|
| Header | `0xAA 0x55` | `0xAA 0xBB` |
| Checksum | CRC16-CCITT | XOR |
| Auth | Binary HMAC-SHA256 (binary challenge-response) | Text SHA256 via println |
| Data packet | 24 bytes (int16 scaled) | 30 bytes (float direct) |
| Architecture | FreeRTOS 8 tasks | Single polling loop |

---

## Development Notes

- Firmware: upstream original single-file (`dylemmas/STASYSESP32`)
- Build output: `.pio/build/esp32dev/firmware.bin`
- CPU: 240MHz
- Partition: `min_spiffs.csv`
- Sensor: 4G accel / 500dps gyro / 260Hz DLPF / 1kHz polling
