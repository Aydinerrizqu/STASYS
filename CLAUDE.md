# STASYS - Shooter Stability Analysis System

> **Note**: For Flutter app development, see `ssa_app/CLAUDE.md`.
> For firmware development, see `Firmware_STSYS32_XIAO/CLAUDE.md` (new XIAO nRF52840 firmware).
> For legacy ESP32 firmware, see `Firmware_STSYS32/CLAUDE.md`.

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic, BLE
- **Python App**: `Python Code (SSA)/STASYS.py` - Desktop analysis tool (PyQt5)
- **Flutter App**: `ssa_app/` - Mobile companion (Android/iOS)
- **Firmware**: `Firmware_STSYS32_XIAO/` - PlatformIO nRF52840 firmware

**Goal**: Open-source alternative to MantisX for dry/live fire training with shot scoring, muzzle trace visualization, and session analysis.

---

## Architecture

```
d:\Aydiner\Projek Flutter SSA\
├── ssa_app/                         # Flutter mobile app (PRIMARY)
│   └── lib/
│       ├── main.dart                    # App entry, MultiProvider + GoRouter
│       ├── router/app_router.dart       # GoRouter ShellRoute (3-tab nav)
│       ├── theme/app_theme.dart         # Dark STSYS theme (#FFB693 primary, #131313 bg)
│       ├── services/
│       │   ├── database_helper.dart    # SQLite singleton, schema creation, migrations
│       │   ├── database_service.dart   # CRUD operations, binary BLOB encoding
│       │   └── export_service.dart     # CSV export via Share Sheet (all sessions)
│       ├── providers/
│       │   ├── bluetooth_provider.dart  # BLE GATT provider (flutter_blue_plus)
│       │   ├── sensor_data_provider.dart # UI state, isolate communication, demo mode
│       │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis
│       │   ├── settings_provider.dart    # + isDemoMode, setDemoMode()
│       │   ├── session_provider.dart
│       │   └── session_logger.dart       # Delegates to DatabaseService (SQLite)
│       ├── screens/
│       │   ├── splash_screen.dart        # STSYS branding, 2s auto-navigate
│       │   ├── connection_screen.dart     # BLE scan/connect + Explore App
│       │   ├── main_shell.dart          # 3-tab NavigationBar shell
│       │   ├── tracking_screen.dart     # Mode selection (4 firearm cards)
│       │   ├── tracking_mode_view.dart   # Live graph + mode change dialog
│       │   ├── history_screen.dart      # Session list + clear all + refresh
│       │   ├── settings_screen.dart     # BLE scan overlay + settings
│       │   └── session_detail_screen.dart # POST SHOT 3-phase + shot chips
│       └── widgets/
│           ├── muzzle_trace_widget.dart  # MantisX-style live trace
│           ├── shot_analysis_panel.dart  # 3-phase post-shot chart
│           └── gyro_realtime_chart.dart  # Real-time gyro chart
│
├── Firmware_STSYS32_XIAO/          # NEW: PlatformIO nRF52840 firmware
│   └── src/
│       ├── main.cpp           # setup() + loop() entry point
│       ├── IMU.cpp           # LSM6DS3 + Madgwick filter + BLE streaming
│       ├── state.cpp          # FSM, shot detection, recoil & draw analysis
│       ├── PDM.cpp            # PDM microphone + audio shot detection
│       ├── power.cpp          # Battery monitoring, LED state machine, deep sleep
│       ├── math.cpp           # Quaternion math, stability metrics
│       ├── globals.cpp        # Global variable definitions
│       └── include/
│           ├── config.h       # Compile-time constants (IMU, shot detection, BLE UUIDs)
│           ├── data.h         # Structs (ImuSample, BleTraceSample, ShotScore, etc.)
│           └── globals.h      # Forward declarations, extern globals
│
└── Python Code (SSA)/
    └── STASYS.py               # Desktop app with ProtocolDecoder class
```

---

## Hardware: Seeed XIAO nRF52840 Sense

| Component | Detail |
|-----------|--------|
| **Board** | Seeed XIAO nRF52840 Sense |
| **Platform** | nordicnrf52 (Nordic nRF52840) |
| **CPU** | ARM Cortex-M4 @ 64 MHz |
| **RAM** | 248 KB |
| **Flash** | 811 KB |
| **Connectivity** | Bluetooth 5/BLE (Nordic SoftDevice S140) |
| **IMU** | LSM6DS3 (104Hz, +-16g accel, +-2000 dps gyro) |
| **Microphone** | PDM mono @ 16kHz (on-board) |
| **LED** | On-board RGB (Red=11, Green=13, Blue=12) |
| **Battery** | LiPo with voltage monitoring (BAT_ENABLE_PIN=14) |

---

## BLE Communication Protocol

### GATT Service & Characteristics

**Service UUID**: `19B10000-E8F2-537E-4F6C-D104768A1214`

| Characteristic | UUID | Direction | Purpose | Format |
|----------------|------|-----------|---------|--------|
| traceChar | `...1214` | Device→App | Raw 6-DoF @ 100Hz | 20 bytes |
| aimTraceChar | `...1215` | Device→App | Aim deviation @ 20Hz | 6 bytes |
| scoreChar | `...1216` | Device→App | Shot score | variable |
| stabilityChar | `...1217` | Device→App | Stability metrics | 10 bytes |
| drawChar | `...1218` | Device→App | Draw stroke metrics | 20 bytes |
| cmdChar | `...1219` | App→Device | Commands | 4 bytes |

### BLE Packet Structs

**BleTraceSample** (20 bytes):
```
Offset  Size  Field     Scale
0       2     gx        int16 / 10.0 → rad/s
2       2     gy        int16 / 10.0 → rad/s
4       2     gz        int16 / 10.0 → rad/s
6       2     ax        int16 / 1000.0 → m/s²
8       2     ay        int16 / 1000.0 → m/s²
10      2     az        int16 / 1000.0 → m/s²
12      1     phase     0=BLUE, 1=YELLOW, 2=RED
13      1     reserved  0
```

**BleAimTrace** (6 bytes):
```
Offset  Size  Field      Scale
0       2     dPitch     int16 / 100.0 → degrees
2       2     dRoll      int16 / 100.0 → degrees
4       1     phase      ShotPhase
5       1     sampleIdx  rolling counter
```

**BleStabilityScore** (10 bytes):
```
Offset  Size  Field            Scale
0       1     score            0-100
1       2     rmsDeviationDeg  int16 / 100.0 → degrees
3       2     maxDeviationDeg  int16 / 100.0 → degrees
5       2     stdDevPitchDeg   int16 / 100.0 → degrees
7       2     stdDevRollDeg    int16 / 100.0 → degrees
```

**BLE Commands** (cmdChar):
```
0x01 = PISTOL mode
0x02 = RIFLE mode
0x10 = Session reset
0x20 = Enter deep sleep
```

---

## Firmware State Machine

```
IDLE → AIMING → TRIGGER → SHOT → RECOIL → AIMING
          ↓
        DRAW → (draw stroke analysis)
```

### State Descriptions

| State | Description |
|-------|-------------|
| IDLE | Waiting for motion (accel > 0.3g or az > 1.5g). Deep sleep after 120s idle. |
| AIMING | Reference quaternion established (20 calm samples). Live aim trace streaming. |
| TRIGGER | Gyro magnitude drops < 2.0 dps (trigger press detected). |
| SHOT | Accel spike > 2.5g + peak > 3.0g within 50ms. Shot finalization. |
| RECOIL | Track peak pitch delta, lateral min/max. 500ms follow-through. |
| DRAW | Draw stroke analysis: grip/pull/rotation/acquisition timing. |

### Shot Detection

- **Pre-filter**: az > 2.5g
- **Peak confirmation**: peak > 3.0g within 50ms window
- **Audio confirmation**: PDM spike within 15ms = live fire, else dry fire
- **Debounce**: 500ms between shots

---

## Scoring System (Angular Deviation)

Uses quaternion-based angular deviation instead of jerk-based:

```
score = 100 - (deviationDeg / precisionDeg) * scaling
```

**Precision thresholds**:
- Pistol: 0.125 degrees
- Rifle: 0.0625 degrees

**Stability score** (during AIMING):
- RMS deviation 0.3° = score 100
- RMS deviation 2.0° = score 0

---

## Database Schema (SQLite — stsys_sessions.db)

> **Implemented**: 2026-04-14 — migrated from SharedPreferences (JSON) to SQLite.
> Storage location: `getDatabasesPath() + '/stsys_sessions.db'` (Android internal storage).

### Table: `sessions`
```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  date INTEGER NOT NULL,          -- Unix timestamp (ms)
  duration REAL NOT NULL,          -- seconds
  firearm_type TEXT NOT NULL,
  training_mode TEXT NOT NULL,
  gyro_x BLOB, gyro_y BLOB, gyro_z BLOB,
  accel_x BLOB, accel_y BLOB, accel_z BLOB
);
CREATE INDEX idx_sessions_date ON sessions(date DESC);
```

### Table: `shots`
```sql
CREATE TABLE shots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,       -- FK → sessions.id
  timestamp INTEGER NOT NULL,
  total_score REAL NOT NULL,
  hold_score REAL, press_score REAL, recoil_score REAL,
  elevation_score REAL, windage_score REAL,
  travel_distance REAL, peak_jerk REAL,
  firearm_type TEXT NOT NULL,
  training_mode TEXT NOT NULL,
  hold_x BLOB, hold_y BLOB, press_x BLOB, press_y BLOB, recoil_x BLOB, recoil_y BLOB
);
CREATE INDEX idx_shots_session ON shots(session_id);
```

### Binary BLOB Encoding
**Time series**: `pointCount(int32)` + `[relTimestamp(float32) + value(float32)] * N`
**Phase traces**: `count(int32)` + `[value(float64)] * N`

---

## Development Workflow

### Building & Uploading Firmware (PlatformIO)
```bash
# Build firmware
cd Firmware_STSYS32_XIAO
pio run -e xiaoblesense

# Upload to device
pio run -e xiaoblesense -t upload

# Open serial monitor
pio run -e xiaoblesense -t monitor

# Run unit tests (no hardware needed)
pio test -e native
```

### Testing Flutter App
```bash
cd ssa_app
flutter build apk --debug
```

---

## Dependencies

### Flutter
```
flutter_blue_plus: ^1.31.0      # BLE (migrated from flutter_bluetooth_serial)
syncfusion_flutter_charts: ^30.2.7
fl_chart: ^1.0.0
provider: ^6.1.2
shared_preferences: ^2.2.2        # App settings only
sqflite: ^2.3.2                   # Session/shots persistence
path: ^1.9.0
share_plus: ^10.0.0               # CSV export via Share Sheet
permission_handler: ^12.0.1
path_provider: ^2.1.1
crypto: ^3.0.3
intl: ^0.19.0
go_router: ^15.1.0
```

### Arduino / nRF52840 (PlatformIO)
```
platform: nordicnrf52
framework: arduino
lib_deps:
    seeed-studio/Seeed Arduino LSM6DS3@^2.0.5
    adafruit/Adafruit Bluefruit nRF52@^1.8.2
    arduino-libraries/Madgwick@^1.2.0
    adafruit/Adafruit Zero PDM Library@^1.2.4
```

---

## Migration History

### 2026-04-18: XIAO nRF52840 Migration

**Hardware change**: ESP32 DEVKIT V1 + MPU6050 + Piezo → Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic

**Changes**:
- [x] New firmware directory: `Firmware_STSYS32_XIAO/` (ported from dylemmas/STASYS_SEEEDXIAO)
- [x] BLE GATT protocol replaces BT Classic SPP
- [x] flutter_blue_plus replaces flutter_bluetooth_serial
- [x] BluetoothProvider rewritten for BLE GATT
- [x] ConnectionScreen updated for BLE scan
- [x] SettingsScreen updated for BLE scan overlay
- [x] Quaternion-based scoring (angular deviation) replaces jerk-based scoring

**Key differences from ESP32 version**:
| Aspect | ESP32 | XIAO nRF52840 |
|--------|-------|---------------|
| Bluetooth | Classic SPP | BLE GATT |
| IMU | MPU6050 | LSM6DS3 |
| Shot detection | Piezo + accel | Accel + audio spike |
| Scoring | Jerk/travel (m/s²) | Angular deviation (degrees) |
| Processing | FreeRTOS multi-task | Single-thread Arduino |
| Session storage | SPIFFS (stub) | None (streaming only) |

---

## Known Issues / TODOs

### Firmware (Firmware_STSYS32_XIAO/)
- [ ] **LED tidak menyala setelah upload** (2026-04-18) — Firmware DFU upload berhasil, tapi LED RGB mati setelah restart. Kemungkinan LED pin conflict atau IMU init failure. Lihat `Firmware_STSYS32_XIAO/CLAUDE.md` untuk detail debugging.

### Pending
- [ ] **Frame freeze / gralloc4 GPU buffer failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.

### Done (2026-04-18)
- [x] **Flutter BleTraceSample parsing fix** — 14-byte struct mismatch (firmware) vs 20-byte (Flutter). Fixed data.length check, accel range (16g), gyro range (200 dps).
- [x] **BLE connection data streaming** — Data successfully received from STASYS-1 device.

---

## UI/UX Design Mockups

HTML mockups exist for visual reference. See `UI UX Design/` directory.

---

## Contact / Support

This is a DIY project. Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic hardware required for full functionality.