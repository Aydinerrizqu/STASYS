# STASYS Flutter App - Development Guide

## Project Purpose

Mobile companion app for the STASYS shooter stability analyzer. Primary platform for live training sessions.

---

## GitHub Repository

**URL**: https://github.com/Aydinerrizqu/STASYS
**Current Branch**: `develop` (Phase 1 MVP completed)
**Parent Project**: `d:\Aydiner\Projek Flutter SSA\`

---

## Architecture

```
ssa_app/
├── lib/
│   ├── main.dart                    # App entry, MultiProvider setup
│   ├── providers/
│   │   ├── bluetooth_provider.dart   # Bluetooth connection, packet parsing (30 bytes)
│   │   ├── sensor_data_provider.dart # UI state, isolate communication
│   │   ├── sensor_data_isolate.dart # Background processing, shot detection, scoring
│   │   ├── settings_provider.dart   # Firearm type, training mode, preferences
│   │   ├── session_provider.dart    # Session list management
│   │   └── session_logger.dart      # Save/load sessions to SharedPreferences
│   ├── screens/
│   │   ├── main_screen.dart         # Bottom nav + drawer navigation
│   │   └── tabs/
│   │       ├── home_tab.dart        # Home / dashboard
│   │       ├── graph_tab.dart       # Live gyro + muzzle trace (toggle)
│   │       ├── shot_timer_tab.dart  # Shot timer with countdown & splits
│   │       ├── connection_tab.dart   # Bluetooth device selection
│   │       └── settings_tab.dart    # Firearm type, training mode, graph duration
│   ├── widgets/
│   │   ├── gyro_realtime_chart.dart # Syncfusion line chart (X/Y/Z gyro)
│   │   ├── muzzle_trace_widget.dart # CustomPainter XY muzzle trace
│   │   ├── control_panel.dart       # Record/Calibrate/Save buttons
│   │   └── status_bar.dart          # Connection status display
│   ├── models/
│   │   └── data_models.dart         # DataPoint, SessionLog, ShotResult, FirearmType, TrainingMode
│   └── Utils/
│       └── ring_buffer.dart          # Efficient circular buffer for sliding window
```

---

## Data Flow

```
ESP32 (Bluetooth)
    │
    │ Binary 30-byte packets @ 100Hz
    ▼
BluetoothProvider (bluetooth_provider.dart)
    │ Parses packet: ax,ay,az,gx,gy,gz,piezo,battery
    │ Validates checksum, sensor ranges
    ▼
SensorDataProvider (sensor_data_provider.dart)
    │ Forwards to isolate, updates battery
    ▼
SensorDataIsolate (sensor_data_isolate.dart)
    │ Runs on separate Dart isolate (background)
    │ - Ring buffer management
    │ - Shot detection state machine
    │ - MantisX-style scoring
    │ - Calibration
    ▼
UI (Consumer widgets)
    │ Listens to SensorDataProvider via ChangeNotifier
    │ Reacts to notifyListeners() calls
    ▼
Screen updates: charts, score display, shot list
```

---

## Bluetooth Protocol (CRITICAL)

**Packet Size**: 30 bytes
**Format**: `'<ffffffHB'` (little-endian)

| Byte Offset | Field | Type | Notes |
|-------------|-------|------|-------|
| 2-5 | ax | float | m/s² |
| 6-9 | ay | float | m/s² |
| 10-13 | az | float | m/s² |
| 14-17 | gx | float | rad/s (500dps / 65.5 * 0.01745) |
| 18-21 | gy | float | rad/s |
| 22-25 | gz | float | rad/s |
| 26-27 | piezo | uint16 | Peak ADC value (little-endian) |
| 28 | battery | uint8 | Percentage |
| 29 | checksum | uint8 | XOR of bytes 2-28 |

**Max gyro validation**: 10.0 rad/s (500 dps ≈ 8.73 rad/s with margin)

---

## Scoring System

### MantisX-Style Soft Curve

Located in `providers/sensor_data_isolate.dart` → `ScoringConfig` class.

Uses `sqrt`-based penalties for gradual, forgiving score distribution:
- Score 95-100: Elite (near-perfect)
- Score 85-94: Expert
- Score 70-84: Advanced
- Score 50-69: Intermediate
- Score 0-49: Beginner

### Firearm Types & Multipliers

| Type | Difficulty Multiplier | Notes |
|------|---------------------|-------|
| Pistol | 1.0 | Baseline |
| Rifle | 0.7 | More stable platform |
| Archery | 1.3 | Most strict |
| Shotgun | 0.9 | Follow-through focus |

### Training Modes

| Mode | Adjustment | Trigger Method |
|------|-----------|---------------|
| Dry Fire | 1.0x | Piezo ADC > threshold |
| Live Fire | 0.8x (more forgiving) | Accelerometer jerk > threshold |

---

## Shot Detection State Machine

```
IDLE → ARMING → ARMED → POST_GATHER → COOLDOWN → IDLE
```

Located in `providers/sensor_data_isolate.dart` → `ShotDetector` class.

### Thresholds
- **Stability Window**: 200ms
- **Gyro Limit**: 4.0 rad/s (ARMING state)
- **Trigger**: Piezo > 100 (dry fire) or jerk > 12.0 (live fire)
- **Cooldown**: 500ms

---

## Provider Communication

### BluetoothProvider → SensorDataProvider

```dart
// BluetoothProvider calls:
sensorDataProvider.updateAllData(
  ax: ax, ay: ay, az: az,
  gx: gx, gy: gy, gz: gz,
  battery: battery,
  piezo: piezo,  // uint16 from firmware
);
```

### SensorDataProvider → Isolate

Uses `SensorDataMessage` class:
```dart
SensorDataMessage('sensor_data', {ax, ay, az, gx, gy, gz, piezo, battery})
SensorDataMessage('start_calibration')
SensorDataMessage('start_recording')
SensorDataMessage('stop_recording')
SensorDataMessage('update_settings', {firearmType, trainingMode})
SensorDataMessage('request_full_sync')
```

### Isolate → SensorDataProvider

```dart
SensorDataMessage('ui_update', {...})         // Display data
SensorDataMessage('calibration_started')
SensorDataMessage('calibration_complete', {offsets})
SensorDataMessage('shot_detected', {shot})    // New shot scored
SensorDataMessage('recording_started')
SensorDataMessage('recording_stopped')
SensorDataMessage('session_data', {...})      // Full session on save
SensorDataMessage('reset_complete')
```

---

## Settings Persistence

- **SharedPreferences** for app settings
- **SessionLogger** stores `SessionLog` objects as JSON in SharedPreferences
- **Key strings**:
  - `firearmType`: 'pistol', 'rifle', 'shotgun', 'archery'
  - `trainingMode`: 'dryFire', 'liveFire'
  - `maxSamples`: graph window duration (3-15 seconds)

---

## Session & Shot Data

### SessionLog (session_logger.dart)
Stores per-session data: gyro/accel time series, firearm type, training mode, list of shots.

### ShotResult (data_models.dart)
Per-shot scoring:
- `totalScore`, `holdScore`, `pressScore`, `recoilScore`
- `elevationScore`, `windageScore`
- `travelDistance`, `peakJerk`
- `firearmType`, `trainingMode`, `timestamp`

---

## Widgets

### GyroRealtimeChart
- Syncfusion `SfCartesianChart`
- 3 lines: X (blue), Y (red), Z (green) gyro data
- 5-second sliding window
- Score indicator badge

### MuzzleTraceWidget
- Custom `CustomPainter` for real-time XY plot
- Integrated gyro trace (X = -Gz, Y = -Gx)
- 3-phase coloring: Hold (red), Press (yellow), Recoil (cyan)
- Concentric circle grid
- Current position dot with glow effect

### ShotTimerTab
- Countdown: 3s, 5s, 10s selectable
- Running timer with millisecond precision
- Shot split times list
- Color-coded split performance (green < 500ms, red > 2000ms)

---

## Common Tasks

### Adding a new shot metric
1. Add field to `ShotResult` class in `data_models.dart`
2. Calculate in `ShotDetector._analyzeShot()` in `sensor_data_isolate.dart`
3. Display in `muzzle_trace_widget.dart` score chips or `gyro_realtime_chart.dart`

### Adding a new drill
1. Add to `Drill` model (create if not exists)
2. Add drill list to `drills_tab.dart`
3. Pass drill parameters to `SensorDataIsolate` via `SensorDataMessage`

### Changing Bluetooth packet format
1. Update `bluetooth_provider.dart` byte offsets
2. Update `SensorDataProvider.updateAllData()` signature
3. Update `sensor_data_isolate.dart` `_processSensorData()`
4. Update firmware `.ino` to match
5. Update protocol docs in parent CLAUDE.md

---

## Testing Without Hardware

- Python app: Auto-falls back to `MockSerial` when connection fails
- Flutter app: Use simulator/emulator, real device required for Bluetooth
- Shot detection: MockSerial generates random sensor data

---

## Dependencies (pubspec.yaml)

```yaml
flutter_bluetooth_serial: ^0.4.0      # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7   # Charts
fl_chart: ^1.0.0                      # Alternative charts
provider: ^6.1.2                      # State management
shared_preferences: ^2.2.2            # Local storage
permission_handler: ^12.0.1            # Android permissions
path_provider: ^2.1.1                  # File paths
crypto: ^3.0.3                        # SHA256 auth
intl: ^0.19.0                          # Formatting
```

---

## Phase 1 Completed Features

- Protocol fix: 30-byte packet parsing with piezo uint16
- MantisX-style scoring: sqrt-based soft curve, per-phase (hold/press/recoil), per-axis (elevation/windage)
- Shot detection state machine: IDLE→ARMING→ARMED→POST_GATHER→COOLDOWN
- Firearm type & training mode selectors with persistence
- Real-time XY muzzle trace widget (CustomPainter, 3-phase coloring)
- Shot timer with countdown (3s/5s/10s) and split times
- Session logging with shot history
- Isolate-based background processing for non-blocking UI

## Phase 2 Pending

- Drill library (drill_model.dart + drills_tab.dart)
- Coaching analysis engine (coaching_service.dart)
- Data export: PNG, CSV, JSON (export_service.dart)
- Shot timer `_onShotDetected` integration with sensor data provider
- Session-over-session improvement dashboard
- Gamification: badges, streaks, daily challenges
