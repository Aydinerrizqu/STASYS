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
| Device Name | `"STASYS-ONE"` |
| Version | STASYS_FW (`dylemmas/STASYSFW`) — **Modular with FreeRTOS** |

> **Migration (2026-05-05)**: Firmware di-update dari upstream `dylemmas/STASYSFW`.
> Features: FreeRTOS tasks, CRC16-CCITT, AHRS (Madgwick), ZUPT, Storage (NVS), OTA, LED patterns.
> Flutter app perlu update untuk kompatibel dengan protocol baru.

---

## Architecture

### Modular Structure (STASYS_FW)

```
Firmware_STASYS32/
├── src/
│   ├── main.cpp                  # Entry point, 4 FreeRTOS tasks
│   ├── storage/
│   │   ├── storage.h/cpp         # NVS config/stats/auth
│   │   ├── crc.h/cpp             # CRC16-CCITT implementation
│   │   ├── status_led.h/cpp      # LED pattern driver
│   │   └── ota.h/cpp             # OTA update manager
│   └── sensor/
│       ├── quaternion.h           # Header-only quaternion math
│       ├── madgwick.h/cpp         # AHRS filter
│       ├── calibration.h/cpp     # IMU calibration + ZUPT
│       └── i2c_bus_recovery.h/cpp # I2C bus recovery
├── partitions_ota.csv
└── platformio.ini
```

### FreeRTOS Tasks

| Task | Stack | Core | Description |
|------|-------|------|-------------|
| SensorTask | 8192 | 0 | Read MPU6050 @ 100Hz, detect shots |
| BtTask | 8192 | 1 | Bluetooth SPP, auth, packet TX |
| BatteryTask | 2048 | 0 | Monitor battery, LED patterns |
| WatchdogTask | 2048 | 0 | Feed watchdog, monitor health |

---

## Communication Protocol

### Binary Packet Format (STASYS_FW — 31 bytes)

```
[0xAA] [0xBB] [ax(float4)] [ay(float4)] [az(float4)] [gx(float4)] [gy(float4)] [gz(float4)] [piezo(uint16)] [battery(uint8)] [crc16_lo] [crc16_hi]
Total: 31 bytes
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
| 29 | 2 | crc16 | CRC16-CCITT (bytes 2..28) |

**CRC16-CCITT**: Initial `0xFFFF`, polynomial `0x1021`, no reflection, no final XOR.
Test vector: `'123456789'` → `0x29B1`

### Authentication (TEXT-BASED)

```
ESP32 → App: "READY\n"
App → ESP32: "AUTH_CHALLENGE\n"
ESP32 → App: SHA256(challenge + SECRET_KEY) as hex string\n
ESP32 → App: (starts streaming 31-byte packets @ 100Hz)
```

**Secret Key**: `12ebaf10h12fa9123z21sti`

---

## Build & Upload

### Build Firmware
```bash
cd Firmware_STASYS32
python -m platformio run -e esp32dev
```

### Upload to ESP32
```bash
# Find COM port
powershell -Command "[System.IO.Ports.SerialPort]::GetPortNames()"

# Upload
python -m platformio run -e esp32dev --target upload --upload-port COM12
```

### Monitor Serial Output
```bash
python -m platformio device monitor --port COM12 --baud 115200
```

---

## Key Modules

### Storage (`src/storage/storage.h`)
- **DeviceConfig**: deviceName, accel/gyro offsets, sampleRate, txPower, sessionTimeout
- **DeviceStats**: totalOperatingSeconds, deepSleepCount, resetCount, lastBattery, lastResetReason
- **NVS Namespaces**: `stasys`, `config`, `stats`, `auth`
- **Secret Key**: `12ebaf10h12fa9123z21sti`

### Calibration (`src/sensor/calibration.h`)
- Factory calibration: collect 500 samples, compute bias/stddev
- **ZUPT** (Zero-Velocity Update): detect static via accel magnitude variance
- Auto bias correction during operation

### Madgwick AHRS (`src/sensor/madgwick.h`)
- Sensor fusion: gyro + accel → quaternion orientation
- Beta parameter controls trust in accelerometer vs gyro
- Output: orientation quaternion → Euler angles (roll, pitch, yaw)

### OTA (`src/storage/ota.h`)
- WiFi-based firmware update
- SSID: `STASYS-OTA`, Password: `stasys_ota_update`
- HTTPS OTA via `esp_https_ota`

### LED Patterns (`src/storage/status_led.h`)
| Pattern | LED Behavior |
|---------|-------------|
| LED_IDLE | Slow blue blink (300ms on, 500ms off) |
| LED_CONNECTING | Fast blue blink (100ms on, 200ms off) |
| LED_STREAMING | Solid blue |
| LED_SENSOR_ERROR | Red blink |
| LED_LOW_BATTERY | Orange blink (blue+red together) |
| LED_CRITICAL_BAT | Solid red |
| LED_CHARGING | Slow blue blink |
| LED_OTA_UPDATE | Purple blink (blue+red) |

---

## Memory Usage

```
RAM:   22.0% (72156 / 327680 bytes)
Flash: 54.5% (1715037 / 3145728 bytes)
```

---

## Flutter App Compatibility

> ⚠️ **Protocol Change**: Firmware baru menggunakan CRC16 (31 bytes) bukan XOR (30 bytes).
> Flutter app `bluetooth_provider.dart` sudah di-update untuk CRC16 verification.

### Protocol Comparison

| Aspek | Old (single-file) | New (STASYS_FW) |
|-------|-------------------|------------------|
| Header | `0xAA 0xBB` | `0xAA 0xBB` |
| Checksum | XOR (1 byte) | CRC16-CCITT (2 bytes) |
| Packet size | 30 bytes | 31 bytes |
| Auth | Text SHA256 | Text SHA256 (sama) |
| Architecture | Polling loop | FreeRTOS 4 tasks |

---

## Known Issues / TODOs

### Pending
- [ ] Test dengan Flutter app — verify BT connection + data streaming
- [ ] Verify CRC16 packet verification works end-to-end

### Fixed (2026-05-05)
- [x] Firmware rebuild dari STASYS_FW GitHub
- [x] Fixed `storage.h`: missing `#include <stddef.h>` for `size_t`
- [x] Fixed `storage.h`: `storageLoadConfig` return type `void` not `bool`
- [x] Removed duplicate `quaternion.cpp` (header-only)
- [x] Build successful: RAM 22%, Flash 54.5%
- [x] Uploaded to ESP32 via COM12

---

## Development Notes

- Chip: ESP32-D0WD-V3 (revision v3.1)
- MAC: 78:1c:3c:f5:16:18
- CPU: 240MHz
- Platform: espressif32 v6.13.0
- Framework: arduino core 3.20017
- Build output: `.pio/build/esp32dev/firmware.bin`