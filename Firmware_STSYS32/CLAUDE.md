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
| Device Name | `"STASYS"` |
| Version | v3.1.0 (`BUILD_VERSION_MAJOR=3`) |

---

## Remote Firmware Sync

### Repository Setup

This firmware directory is synchronized with the upstream repo:

| Role | Repo | URL |
|------|------|-----|
| **Local** (this project) | Aydinerrizqu/STASYS | https://github.com/Aydinerrizqu/STASYS |
| **Upstream** (partner: dylemmas) | dylemmas/STSYS32 | https://github.com/dylemmas/STSYS32 |

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

### FreeRTOS Tasks

| Task | Core | Priority | Stack | Description |
|------|------|----------|-------|-------------|
| `SensorTask` | 1 | 3 | 4096 | MPU6050 ISR-driven reads → `sampleQueue` |
| `ShotDetector` | 1 | 2 | 4096 | Consumes `sampleQueue` → shot events |
| `RecoveryTask` | 1 | 2 | 2048 | Async I2C bus recovery |
| `StreamTask` | 0 | 1 | 2048 | `DATA_RAW_SAMPLE` packets @ streaming rate |
| `BatteryMonitor` | 0 | 1 | 1024 | Battery monitoring @ 30s intervals |
| `BluetoothTask` | 0 | 2 | 4096 | SPP RFCOMM read/write + command dispatch |
| `LEDTask` | 0 | 1 | 2048 | LED/LEDC PWM patterns + haptic feedback |

### Data Flow

```
MPU6050 ISR (Core 1)
    → sampleQueue (64 samples)
        → ShotDetector → shot events → txQueue → BluetoothTask → SPP
        → StreamTask → raw samples → txQueue → BluetoothTask → SPP

Commands: BluetoothTask RX → dispatchCommand → session/sensor/config handlers
I2C Error → recoveryQueue → RecoveryTask → recoverI2CBus() → reinit MPU6050
```

### Module Structure

```
src/
├── main.cpp          # FreeRTOS tasks + command dispatch + setup()
├── protocol.cpp/h    # CRC16-CCITT, packet encoder/decoder
├── bluetooth.cpp/h   # SPP BT, TX queue, sendPacket functions
├── sensor.cpp/h      # MPU6050 ISR-driven reading
├── shot_detector.cpp/h  # Adaptive threshold shot detection
├── session.cpp/h     # Session state machine: IDLE→STREAMING
├── config.cpp/h      # NVS persistent config
├── battery.cpp/h    # Battery monitoring
├── led.cpp/h        # LED PWM + haptic feedback patterns
├── storage.cpp/h    # Flash session storage
├── ota.cpp/h        # OTA firmware update
├── security.cpp/h   # HMAC-SHA256 auth stub
├── coredump.cpp/h   # Exception coredump storage
└── (sensor.h)      # SensorSample struct, calibration functions
```

---

## Communication Protocol

> **Full details**: See root `CLAUDE.md` → **Communication Protocol**

### Binary Packet Format

```
[0xAA] [0x55] [TYPE] [LEN_LO] [LEN_HI] [PAYLOAD...] [CRC_LO] [CRC_HI]
```

**CRC16-CCITT**: poly=0x1021, init=0xFFFF, xor_out=0x0000.
Verified: `"123456789"` → `0x29B1`.

### Key Packet Types

| Type | Name | Direction | Notes |
|------|------|-----------|-------|
| 0x01 | `CMD_START_SESSION` | App→FW | Start streaming + auth challenge |
| 0x06 | `CMD_AUTH` | App→FW | HMAC-SHA256 auth response |
| 0x10 | `EVT_SESSION_STARTED` | FW→App | Session started |
| 0x12 | `EVT_SHOT_DETECTED` | FW→App | Shot event with peaks |
| 0x13 | `EVT_SENSOR_HEALTH` | FW→App | Heartbeat @ ~10Hz |
| 0x14 | `EVT_AUTH_CHALLENGE` | FW→App | 16-byte challenge |
| 0x15 | `EVT_AUTH_SUCCESS` | FW→App | Auth confirmed |
| 0x20 | `DATA_RAW_SAMPLE` | FW→App | Sensor data @ streaming_rate_hz |

### Auth Flow (3-way handshake)

```
Flutter → ESP32: CMD_START_SESSION (0x01)
ESP32 → Flutter: EVT_AUTH_CHALLENGE (0x14) [session_id(4) + challenge(16)]
Flutter → ESP32: CMD_AUTH (0x06) [session_id(4) + HMAC-SHA256(32)]
ESP32 → Flutter: EVT_AUTH_SUCCESS (0x15) [session_id(4)]
ESP32 → Flutter: EVT_SESSION_STARTED (0x10)
ESP32 → Flutter: DATA_RAW_SAMPLE (0x20) @ 50Hz default
```

**Secret Key**: `12ebaf10h12fa9123z21sti`
**HMAC Input**: challenge(16 bytes) + session_id(4 bytes LE)
**HMAC Output**: 32-byte digest, sent as-is

---

## Shot Detection State Machine

`IDLE → ARMING → ARMED → POST_GATHER → COOLDOWN`

| State | Condition |
|-------|-----------|
| IDLE | Waiting for stability (gyro < 4.0 rad/s) |
| ARMING | Gyro stable for 200ms |
| ARMED | Ready to detect shot trigger |
| POST_GATHER | Collecting recoil data (10 samples @ 100Hz) |
| COOLDOWN | 500ms before next shot |

**Dry Fire**: Piezo ADC > threshold while gyro stable
**Live Fire**: Accelerometer jerk > threshold

---

## OTA Firmware Update

Firmware mendukung update via Bluetooth:

| Command | Type | Description |
|---------|------|-------------|
| `CMD_OTA_START` | 0x0C | Begin OTA update |
| `CMD_OTA_DATA` | 0x0D | Firmware chunk |
| `CMD_OTA_END` | 0x0E | Finalize OTA |
| `CMD_OTA_ABORT` | 0x0F | Abort OTA |
| `CMD_OTA_STATUS` | 0x11 | Get progress |

OTA partition table: `partitions_ota.csv`

---

## Known Issues / TODOs

### Pending
- [ ] **OTA app integration** — Flutter app belum implementasi OTA command flow
- [ ] **Encrypted packets** — `PKT_TYPE_ENCRYPTED (0xF0)` support belum dipakai
- [ ] **Calibration command** — `CMD_CALIBRATE_START` stub ada tapi belum test full flow
- [ ] **Storage session mgmt** — `CMD_GET_SESSIONS / GET_SESSION_DATA / DELETE_SESSION` belum dipakai Flutter

### Fixed
- [x] CRC scope mismatch — `encodePacket()` fixed to `3+len`
- [x] MPU6050 not responding → degraded mode fallback
- [x] RecoveryTask watchdog timeout — `esp_task_wdt_reset()` in loop
- [x] CMD_START_SESSION auth guard blocking Flutter — removed `_isAuthenticated` check
- [x] PktRawSample sizeof mismatch — confirmed 24 bytes

---

## Flutter App Compatibility

Flutter app (`ssa_app/`) **terbukti compatible** dengan firmware upstream tanpa perubahan:

- CRC16-CCITT ✅ (identical)
- Packet types 0x01-0x85 ✅ (identical)
- Auth flow (challenge→auth→success) ✅ (identical)
- DATA_RAW_SAMPLE sizeof ✅ (24 bytes)
- EVT_SHOT_DETECTED sizeof ✅ (30 bytes)
- PKT_TYPE_ENCRYPTED ✅ (Flutter ignore unused packets)

**Jangan ubah packet format core** tanpa konfirmasi ke partner & update Flutter app juga.

---

## Development Notes

- Firmware versioning: **v3.1.0** (local scheme, berbeda dari upstream yang v1.0.1)
- Build output: `.pio/build/esp32dev/firmware.bin`
- Default streaming rate: **50Hz** (dari upstream, was 100Hz)
- Data modes: 0=both, 1=raw-only, 2=events-only
- Priority TX queue: control packets bypass sample stream (upstream feature)
