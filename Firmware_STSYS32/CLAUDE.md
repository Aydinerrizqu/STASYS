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
| Version | Upstream original (`dylemmas/STASYSESP32`) |

> **Migration (2026-04-22)**: Firmware di-reset ke versi awal/original dari upstream `dylemmas/STASYSESP32`. Branch: `migrasi_firmware_awal`.

---

## Remote Firmware Sync

### Repository Setup

This firmware directory is synchronized with the upstream repo:

| Role | Repo | URL |
|------|------|-----|
| **Local** (this project) | Aydinerrizqu/STASYS | https://github.com/Aydinerrizqu/STASYS |
| **Upstream (original)** | dylemmas/STASYSESP32 | https://github.com/dylemmas/STASYSESP32 |
| **Upstream (modular)** | dylemmas/STSYS32 | https://github.com/dylemmas/STSYS32 |

Remote `firmware` sudah di-configure saat setup. Cek dengan:

```bash
git remote -v
```

Jika belum ada, tambah dengan:

```bash
git remote add firmware https://github.com/dylemmas/STSYS32.git
git fetch firmware
```

### Sync Workflow (Cara Update Firmware)

Setiap kali partner push update ke `dylemmas/STSYS32`:

```bash
# 1. Fetch commits terbaru dari upstream
git fetch firmware

# 2. Lihat commits yang mau diambil
git log --oneline firmware/main -10

# 3. Pull firmware files dari upstream (overwrite file lokal)
git checkout firmware/main -- src/ platformio.ini partitions_ota.csv

# 4. Verify build
pio run

# 5. Commit hasil merge
git add Firmware_STSYS32/
git commit -m "chore: sync firmware from dylemmas/STSYS32"
git push origin develop-migrasi-firmware-v3

# 6. Upload ke ESP32
pio run --target upload --upload-port COM8
pio device monitor --port COM8 --baud 115200
```

Untuk lihat port COM:
```bash
python -c "import serial.tools.list_ports; [print(p.device) for p in serial.tools.list_ports.comports()]"
```

---

## Build & Flash

```bash
pio run                    # Build firmware
pio run --target upload   # Upload via USB
pio run --target upload --upload-port COM8  # Upload ke port spesifik
pio device monitor        # Serial monitor (115200 baud)
```

### Build Flags

| Flag | Value | Description |
|------|-------|-------------|
| `BUILD_VERSION_MAJOR` | 3 | Local versioning scheme |
| `BUILD_VERSION_MINOR` | 1 | |
| `BUILD_VERSION_PATCH` | 0 | |
| `CONFIG_FREERTOS_HZ` | 1000 | FreeRTOS tick rate |
| `configCHECK_FOR_STACK_OVERFLOW` | 2 | Stack overflow detection |
| `configUSE_STACK_CHECKING` | 1 | Stack usage monitoring |

---

## Architecture

> **2026-04-22**: Simplified to single-file upstream original. No longer uses modular architecture.

### Single-File Structure (from upstream)

```
src/
└── main.cpp   (~810 lines) — Everything in one file: sensor reading, Bluetooth,
                          authentication, data transmission
```

No separate modules for protocol, sensor, bluetooth, shot_detector, session, config,
battery, led, storage, ota, security, coredump. All inline in main.cpp.

---

## Communication Protocol

> **Full details**: See root `CLAUDE.md` → **Communication Protocol**

> **⚠️ PROTOCOL BREAKING CHANGE**: Upstream original menggunakan protokol yang SANGAT BERBEDA dari modular firmware. Flutter app saat ini hanya compatible dengan modular firmware (CRC16-CCITT, binary packets). Perlu adapter/middleware atau update Flutter app untuk menerima data dari upstream.

### Binary Packet Format (upstream original)

```
[0xAA] [0xBB] [ax(float4)] [ay(float4)] [az(float4)] [gx(float4)] [gy(float4)] [gz(float4)] [piezo(uint16)] [battery(uint8)] [xor_checksum(uint8)]
Total: 34 bytes
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
- [ ] **Flutter app incompatible** — upstream original uses text-based auth + float packets (34 bytes, 0xAA/0xBB header, XOR checksum). Flutter app only supports modular firmware protocol. Need middleware/adapter or Flutter update.
- [ ] No modular features (OTA, storage, LED, session mgmt) — stripped to single-file original

### Fixed (modular firmware era)
- [x] CRC scope mismatch — `encodePacket()` fixed to `3+len`
- [x] MPU6050 not responding → degraded mode fallback
- [x] RecoveryTask watchdog timeout — `esp_task_wdt_reset()` in loop
- [x] CMD_START_SESSION auth guard blocking Flutter — removed `__isAuthenticated` check
- [x] PktRawSample sizeof mismatch — confirmed 24 bytes

---

## Flutter App Compatibility

> **BREAKING CHANGE**: Flutter app (`ssa_app/`) only compatible with modular firmware (`dylemmas/STSYS32`). **Not compatible** with upstream original (`dylemmas/STASYSESP32`) due to protocol differences.

### Protocol Comparison

| Aspek | Modular (STSYS32) | Upstream Original (STASYSESP32) |
|-------|------------------|----------------------------------|
| Header | `0xAA 0x55` | `0xAA 0xBB` |
| Checksum | CRC16-CCITT | XOR |
| Auth | Binary HMAC-SHA256 (binary challenge-response) | Text SHA256 via println |
| Data packet | 24 bytes (int16 scaled) | ~34 bytes (float direct) |
| Architecture | FreeRTOS 8 tasks | Single polling loop |

---

## Development Notes

- Firmware: upstream original single-file (`dylemmas/STASYSESP32`)
- Build output: `.pio/build/esp32dev/firmware.bin`
- CPU: 240MHz
- Partition: `min_spiffs.csv`
- Sensor: 4G accel / 500dps gyro / 260Hz DLPF / 1kHz polling
