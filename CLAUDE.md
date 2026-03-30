# STASYS - Shooter Stability Analysis System

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: ESP32 + MPU6050 + Piezo sensor, Bluetooth Classic
- **Python App**: STASYS.py - Desktop analysis tool (PyQt5)
- **Flutter App**: ssa_app - Mobile companion (Android/iOS)
- **Firmware**: STASYS_Firmware_Oversampling.ino

**Goal**: Open-source alternative to MantisX for dry/live fire training with shot scoring, muzzle trace visualization, and session analysis.

---

## Architecture

```
d:\Aydiner\Projek Flutter SSA\
├── ssa_app/                    # Flutter mobile app (PRIMARY)
│   ├── lib/
│   │   ├── providers/         # State management
│   │   ├── screens/           # UI screens
│   │   ├── widgets/           # Reusable widgets
│   │   ├── models/            # Data models
│   │   └── main.dart          # App entry
│   └── STASYS_Firmware.ino    # ESP32 firmware (source)
│
└── Python Code (SSA)/          # Python desktop app (COMPANION)
    ├── STASYS.py              # Main Python app (v3.1)
    ├── STASYS_Firmware_Oversampling.ino  # Canonical firmware
    ├── STASYS_REPORTCARD.py  # Session viewer
    ├── shooter_data.db        # SQLite database
    └── venv/                  # Python dependencies
```

---

## Communication Protocol

### Binary Packet (30 bytes, 100Hz)

| Offset | Size | Field | Type | Notes |
|--------|------|-------|------|-------|
| 0-1 | 2 | Header | `0xAA 0xBB` | Sync bytes |
| 2-5 | 4 | ax | float | Accelerometer X (m/s²) |
| 6-9 | 4 | ay | float | Accelerometer Y (m/s²) |
| 10-13 | 4 | az | float | Accelerometer Z (m/s²) |
| 14-17 | 4 | gx | float | Gyroscope X (rad/s) |
| 18-21 | 4 | gy | float | Gyroscope Y (rad/s) |
| 22-25 | 4 | gz | float | Gyroscope Z (rad/s) |
| 26-27 | 2 | piezo | uint16 | Peak piezo ADC value |
| 28 | 1 | battery | uint8 | Battery percentage |
| 29 | 1 | checksum | uint8 | XOR of bytes 2-28 |

**Format string**: `'<ffffffHB'` (little-endian)
**Struct size**: 30 bytes

### Authentication Protocol

```
Python -> ESP32: <16-char random challenge>\n
ESP32 -> Python: SHA256(challenge + SECRET_KEY) in hex\n
Python -> ESP32: AUTH_SUCCESS\n
```

**Secret Key**: `12ebaf10h12fa9123z21sti`

### Firmware Version

Firmware sends version string after READY signal during handshake.
Current canonical version: `FIRMWARE_VERSION = "2.0-OVERSAMPLE"`

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

### Shot Detection State Machine
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

**Difficulty Multipliers**:
- Pistol: 1.0 (baseline)
- Rifle: 0.7 (more stable, stricter)
- Archery: 1.3 (most strict)
- Shotgun: 0.9 (follow-through focus)

**Training Mode**: Live Fire gets 0.8x multiplier (more forgiving)

---

## Critical Notes

### CRITICAL: Protocol Mismatch History

Flutter `bluetooth_provider.dart` previously parsed **28 bytes** while firmware sent **30 bytes** (with piezo uint16). This caused data corruption. All code now uses 30-byte protocol. If adding new code:

1. **Always use `packetSize = 30`** and format `'<ffffffHB'`
2. **Byte offsets**: battery at offset 28, checksum at offset 29
3. **Max gyro validation**: Firmware uses 500dps range → ~8.73 rad/s, use maxGyro = 10.0 for validation

### Flutter Isolate Message Types

The isolate (`sensor_data_isolate.dart`) sends `'ui_update'` message type. The provider listens for:
- `'ui_update'` - used for both full sync and diff updates
- `'calibration_started'`, `'calibration_complete'`
- `'shot_detected'` - new shot scored
- `'recording_started'`, `'recording_stopped'`
- `'session_data'` - full session data on save
- `'reset_complete'`

### Python vs Flutter State

Python STASYS.py uses **Hardcore** scoring (Travel=1200, Jerk=5000 penalties).
Flutter app uses **MantisX-style** soft curve scoring.
Both apps can read the same SQLite database but use different scoring algorithms.

---

## Development Workflow

### Testing Python App (no hardware)
```bash
cd "d:\Aydiner\Projek Flutter SSA\Python Code (SSA)"
python STASYS.py
# Automatically falls back to MockSerial simulation mode
```

### Flashing Firmware
1. Open `STASYS_Firmware_Oversampling.ino` in Arduino IDE
2. Select ESP32 board (e.g., NodeMCU-32S)
3. Set CPU frequency to 240MHz in code (`setCpuFrequencyMhz(240)`)
4. Upload

### Testing Flutter App
```bash
cd "d:\Aydiner\Projek Flutter SSA\ssa_app"
flutter run
```

### Pairing ESP32
1. Flash firmware to ESP32
2. ESP32 broadcasts as `STASYS-V2-XXXX` (based on chip MAC)
3. Pair ESP32 with PC/phone via Bluetooth settings
4. Note COM port (Windows) or device name (mobile)

---

## Dependencies

### Python
```
PyQt5
pyqtgraph
pyserial
```

### Flutter
```
flutter_bluetooth_serial: ^0.4.0
syncfusion_flutter_charts: ^30.2.7
fl_chart: ^1.0.0
provider: ^6.1.2
shared_preferences: ^2.2.2
permission_handler: ^12.0.1
path_provider: ^2.1.1
crypto: ^3.0.3
intl: ^0.19.0
```

### Arduino / ESP32
```
Adafruit_MPU6050
mbedtls/sha256.h (built-in ESP32)
BluetoothSerial (built-in ESP32)
Wire (built-in)
```

---

## Known Issues / TODOs

- Python uses Hardcore scoring, Flutter uses MantisX-style — consider unifying
- Shot timer in Flutter (`shot_timer_tab.dart`) has `_onShotDetected` that is not yet connected to sensor data provider
- STASY_V4.py is a duplicate of STASYS.py with different defaults (COM4, PIEZO 400/2500) — merge or delete
- Battery monitoring only in firmware, not yet surfaced in Flutter UI consistently
- Export service (`export_service.dart`) not yet implemented in Flutter

---

## Contact / Support

This is a DIY project. ESP32 + MPU6050 + Piezo hardware required for full functionality.
