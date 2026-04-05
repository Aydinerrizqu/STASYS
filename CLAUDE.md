# STASYS - Shooter Stability Analysis System

> **Note**: For Flutter app development, see `ssa_app/CLAUDE.md`.
> For firmware development, see `Firmware_STSYS32/README.md`.
> That file covers PlatformIO build, module architecture, and hardware pinout.

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: ESP32 + MPU6050 + Piezo sensor, Bluetooth Classic
- **Python App**: `Python Code (SSA)/STASYS.py` - Desktop analysis tool (PyQt5)
- **Flutter App**: `ssa_app/` - Mobile companion (Android/iOS)
- **Firmware**: `Firmware_STSYS32/` - Modular PlatformIO ESP32 firmware

**Goal**: Open-source alternative to MantisX for dry/live fire training with shot scoring, muzzle trace visualization, and session analysis.

---

## Architecture

```
d:\Aydiner\Projek Flutter SSA\
├── ssa_app/                         # Flutter mobile app (PRIMARY)
│   └── lib/
│       ├── providers/
│       │   ├── bluetooth_provider.dart   # 8-state packet parser, CRC16-CCITT, HMAC-SHA256 auth
│       │   ├── sensor_data_provider.dart
│       │   ├── sensor_data_isolate.dart   # Shot detection + 3-phase analysis
│       │   ├── settings_provider.dart
│       │   ├── session_provider.dart
│       │   └── session_logger.dart
│       ├── screens/tabs/
│       │   ├── graph_tab.dart       # Real-time gyro + muzzle trace + post-shot analysis
│       │   └── analysis_tab.dart    # Post-shot 3-phase chart + session history
│       └── widgets/
│           ├── muzzle_trace_widget.dart  # Real-time XY trace (2s rolling window)
│           ├── shot_analysis_panel.dart  # 3-phase chart + phase scores
│           └── shot_history_list.dart    # Session shot list
│
├── Firmware_STSYS32/                 # Modular PlatformIO ESP32 firmware
│   ├── platformio.ini
│   ├── partitions_ota.csv
│   └── src/
│       ├── main.cpp           # FreeRTOS tasks: recoveryTask, sensorTask, streamTask,
│       │                      #   shotDetectorTask, batteryMonitorTask, bluetoothTask, ledTask
│       ├── protocol.h/cpp     # Packet framing, CRC16-CCITT, packet types
│       ├── sensor.h/cpp       # MPU6050 ISR-driven reading, calibration, I2C recovery
│       ├── bluetooth.h/cpp     # SPP BT, command dispatch, packet TX/RX
│       ├── shot_detector.h/cpp # Adaptive threshold shot detection (state machine)
│       ├── security.h/cpp      # Auth stub (REQUIRE_AUTH disabled in security.cpp)
│       ├── session.h/cpp       # Session state: IDLE→STREAMING
│       ├── config.h/cpp        # NVS persistent config
│       ├── battery.h/cpp      # Battery monitoring
│       ├── led.h/cpp          # LED feedback
│       ├── storage.h/cpp      # Flash session storage (stub)
│       ├── ota.h/cpp          # OTA firmware update (stub)
│       └── coredump.h/cpp     # Crash dump (stub)
│
└── Python Code (SSA)/
    └── STASYS.py              # Desktop app with ProtocolDecoder class
    └── STASYS_Firmware_Oversampling.ino  # Old canonical firmware (legacy)
```

---

## Communication Protocol

### Binary Packet Format

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0x55` |
| 2 | 1 | Type | Packet type (see table below) |
| 3 | 1 | LenLo | Payload length (LSB) |
| 4 | 1 | LenHi | Payload length (MSB) |
| 5..N | N | Payload | Packet-type-specific data |
| N+1 | 1 | CrcLo | CRC16-CCITT over TYPE(1)+LEN_LO(1)+LEN_HI(1)+payload(N) |
| N+2 | 1 | CrcHi | Total scope = 3+N bytes, not 2+N |

**CRC16-CCITT**: Initial `0xFFFF`, polynomial `0x1021`, no reflection, no final XOR.
Verified with test vector `'123456789'` → `0x29B1`.

### Packet Types

| Type | Name | Direction | Description |
|------|------|-----------|-------------|
| 0x01 | `CMD_START_SESSION` | App→Firmware | Start sensor streaming + trigger auth |
| 0x02 | `CMD_STOP_SESSION` | App→Firmware | Stop sensor streaming |
| 0x03 | `CMD_GET_INFO` | App→Firmware | Request device info |
| 0x04 | `CMD_GET_CONFIG` | App→Firmware | Request current config |
| 0x05 | `CMD_SET_CONFIG` | App→Firmware | Set config values |
| 0x06 | `CMD_AUTH` | App→Firmware | HMAC-SHA256 auth response |
| 0x10 | `EVT_SESSION_STARTED` | Firmware→App | Session started, session_id included |
| 0x11 | `EVT_SESSION_STOPPED` | Firmware→App | Session summary |
| 0x12 | `EVT_SHOT_DETECTED` | Firmware→App | Shot detected with peaks (info only) |
| 0x13 | `EVT_SENSOR_HEALTH` | Firmware→App | Sensor health heartbeat @ ~10Hz (8 bytes) |
| 0x14 | `EVT_AUTH_CHALLENGE` | Firmware→App | 16-byte challenge + session_id |
| 0x15 | `EVT_AUTH_SUCCESS` | Firmware→App | Auth successful |
| 0x1F | `EVT_ERROR` | Firmware→App | Error with code + message |
| 0x20 | `DATA_RAW_SAMPLE` | Firmware→App | Sensor data @ 100Hz (24 bytes) |
| 0x81 | `RSP_INFO` | Firmware→App | Device info response |
| 0x82 | `RSP_CONFIG` | Firmware→App | Config response |
| 0x83 | `RSP_ACK` | Firmware→App | Command acknowledgment |
| 0x85 | `RSP_SHOT_STATS` | Firmware→App | Shot statistics response |

### DATA_RAW_SAMPLE Payload (24 bytes — compiler-aligned)

| Offset | Size | Field | Type | Conversion |
|--------|------|-------|------|-----------|
| 0 | 4 | counter | uint32 | — |
| 1 | 4 | timestamp_us | uint32 | — |
| 2 | 2 | ax | int16 | raw / 8192.0 * 9.81 → m/s² |
| 3 | 2 | ay | int16 | raw / 8192.0 * 9.81 → m/s² |
| 4 | 2 | az | int16 | raw / 8192.0 * 9.81 → m/s² |
| 5 | 2 | gx | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 6 | 2 | gy | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 7 | 2 | gz | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 8 | 2 | piezo | uint16 | ADC peak value |
| 9 | 2 | reserved | uint16 | was: temperature (unused) |

> ⚠️ **Struct alignment**: `sizeof(PktRawSample) = 24 bytes` (compiler packs). This was verified empirically — struct fields are NOT padded to 4-byte boundaries. ESP32 is little-endian.

### Authentication Protocol

```
Flutter → ESP32: CMD_START_SESSION (0x01)
ESP32 → Flutter: EVT_AUTH_CHALLENGE (0x14) [session_id(4) + challenge(16) = 20 bytes]
Flutter → ESP32: CMD_AUTH (0x06) [session_id(4) + HMAC-SHA256(32) = 36 bytes]
ESP32 → Flutter: EVT_AUTH_SUCCESS (0x15) [session_id(4) = 4 bytes]
ESP32 → Flutter: EVT_SESSION_STARTED (0x10) [17 bytes]
ESP32 → Flutter: DATA_RAW_SAMPLE (0x20) @ 100Hz [24 bytes + 2 CRC = 31 bytes total frame]
```

**Secret Key**: `12ebaf10h12fa9123z21sti`
**HMAC Input**: challenge(16 bytes) + session_id(4 bytes LE)
**HMAC Output**: 32-byte digest, sent as-is (not hex-encoded)

> ⚠️ **Known issue**: DATA_RAW_SAMPLE CRC mismatch still under investigation.
> Auth packets (AUTH_CHALLENGE, AUTH_SUCCESS, SESSION_STARTED) verify correctly.
> DATA_RAW_SAMPLE frames fail CRC despite struct size verified at 24 bytes.

---

## Database Schema (shooter_data.db)

### Table: `recordings`
```sql
id INTEGER PRIMARY KEY
timestamp DATETIME
session_id TEXT
stability_score REAL
battery_percentage REAL
elev REAL
wind REAL
cant REAL
firearm_type TEXT  -- Pistol/Rifle/Shotgun/Archery
training_mode TEXT  -- dryFire/liveFire
```

### Table: `shots`
```sql
id INTEGER PRIMARY KEY
timestamp DATETIME
session_id TEXT
score REAL
cant REAL
mode TEXT
firearm_type TEXT
training_mode TEXT
press_score REAL
hold_score REAL
recoil_score REAL
elevation_score REAL
windage_score REAL
```

---

## Key Algorithms

### Shot Detection State Machine (Firmware + Flutter Isolate)
`IDLE → ARMING → ARMED → POST_GATHER → COOLDOWN`

- **IDLE**: Waiting for stability (gyro < 4.0 rad/s)
- **ARMING**: Gyro stable for 200ms
- **ARMED**: Ready to detect shot trigger
- **POST_GATHER**: Collecting recoil data (10 samples @ 100Hz)
- **COOLDOWN**: 500ms cooldown before next shot

### Trigger Detection
- **Dry Fire**: Piezo ADC > 100 (configurable) while gyro stable
- **Live Fire**: Accelerometer jerk > threshold

### MantisX-Style Scoring (Soft Curve)

Uses `sqrt`-based penalties for gradual score drop-off:

```
score = 100 - sqrt(total_travel) * 30 * difficulty_multiplier
       - sqrt(peak_jerk) * 25 * difficulty_multiplier
       - sqrt(avg_hold_delta) * 10 * difficulty_multiplier
       - sqrt(avg_press_delta) * 15 * difficulty_multiplier
       - sqrt(avg_recoil_delta) * 5 * difficulty_multiplier
       - sqrt(elev_travel) * 15 * difficulty_multiplier
       - sqrt(wind_travel) * 15 * difficulty_multiplier
```

**Difficulty Multipliers**: Pistol: 1.0, Rifle: 0.7, Archery: 1.3, Shotgun: 0.9
**Training Mode**: Live Fire gets 0.8x multiplier (more forgiving)

---

## Development Workflow

### Building & Uploading Firmware (PlatformIO)
```bash
# Find ESP32 COM port first
python -c "import serial.tools.list_ports; [print(p.device) for p in serial.tools.list_ports.comports()]"

# Upload to ESP32 (note: COM port may change — verify with above)
cd Firmware_STSYS32
pio run --target upload --upload-port COM8     # Upload to ESP32
pio device monitor --port COM8 --baud 115200     # Serial monitor

# Serial monitor shows: [BT TX] [CRC] [PROTO sizeof] messages
```

### Testing Flutter App
```bash
cd ssa_app
flutter build apk --debug
# Install APK from build/app/outputs/flutter-apk/app-debug.apk
```

### Pairing ESP32
1. Flash firmware to ESP32 via PlatformIO
2. ESP32 broadcasts as `STASYS-V2-XXXX` (based on chip MAC)
3. Pair ESP32 with phone via Bluetooth settings
4. Note device name for connection

---

## Dependencies

### Flutter
```
flutter_bluetooth_serial: ^0.4.0  # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7
fl_chart: ^1.0.0
provider: ^6.1.2
shared_preferences: ^2.2.2
permission_handler: ^12.0.1
path_provider: ^2.1.1
crypto: ^3.0.3  # SHA256 for HMAC auth
intl: ^0.19.0
```

### Arduino / ESP32 (PlatformIO)
```
framework: arduino (ESP32 arduino core 3.20017)
BluetoothSerial (built-in ESP32)
Wire (built-in)
Preferences (built-in)
ESP32 built-in BT/SPI/HTTPD
```

---

## Known Issues / TODOs

### Pending
- [ ] **Android BT fragmentation** — DATA_RAW_SAMPLE CRC errors ~0.01% (1 in ~9400 packets).
  Caused by Android BT buffer delivering partial packets across multiple `onDataReceived` chunks.
  Parser starts mid-frame on chunk boundary, causing one invalid CRC per ~10s of streaming.
  Non-critical — sensor data still flows at 99.99% integrity.

### Migration Status

| Component | Protocol | Status |
|-----------|---------|--------|
| `Firmware_STSYS32/` | New (CRC16-CCITT) | Complete, uploaded to ESP32 |
| `Python Code (SSA)/STASYS.py` | New | ProtocolDecoder class added |
| `ssa_app/` Flutter | New | bluetooth_provider.dart updated, APK built |
| Legacy Arduino `.ino` | Old (XOR) | Still exists (legacy) |

### Historical / Fixed
- [x] esp_bt_gap.h not found in PlatformIO — GAP callback removed
- [x] Preferences::getString() wrong args — fixed in config.cpp
- [x] sensor.cpp goto crosses initialization — declarations moved to top
- [x] BUILD_TIMESTAMP macro type mismatch — simplified to `#define BUILD_TIMESTAMP 0`
- [x] mbedtls/hmac.h not found — security.cpp stubbed (auth disabled in security.cpp, bypassed in dispatchCommand)
- [x] RecoveryTask watchdog timeout — added `esp_task_wdt_reset()` in recoveryTask loop
- [x] CMD_START_SESSION guard blocking Flutter auth — removed `_isAuthenticated` check from `startSession()`
- [x] Firmware not sending EVT_AUTH_CHALLENGE — added to CMD_START_SESSION handler in dispatchCommand
- [x] PktRawSample sizeof mismatch — changed to 24 bytes (was: temperature field, compiler-packed to 24 not 26)
- [x] ESP32 TX serial debug flooding — limited to first 3 packets to prevent watchdog issues
- [x] **CRC scope mismatch** — Firmware computed CRC over `TYPE+LEN(2 bytes only)+payload` (2+N).
  Flutter computed over `TYPE+LEN_LO+LEN_HI+payload` (3+N). Fixed firmware `encodePacket()` to use `3+len`.
  Verified: AUTH_CHALLENGE(0x14), AUTH_SUCCESS(0x15), SESSION_STARTED(0x10), RSP_CONFIG(0x82) all pass CRC.
- [x] **EVT_SENSOR_HEALTH (0x13) unknown packet** — Added handler in Flutter `_handlePacket()`.
  Firmware sends this heartbeat ~10Hz. No UI display yet, just silent consumption.

### Flutter Pending
- Demo mode not implemented
- Battery monitoring: Battery percentage received but not consistently displayed
- Export service (`export_service.dart`) not yet implemented
- Python uses Hardcore scoring, Flutter uses MantisX-style — consider unifying

---

## Contact / Support

This is a DIY project. ESP32 + MPU6050 + Piezo hardware required for full functionality.
