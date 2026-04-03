# STASYS Flutter App - Development Guide

## Project Purpose

Mobile companion app for the STASYS shooter stability analyzer. Primary platform for live training sessions.

---

## Architecture

```
ssa_app/
├── lib/
│   ├── main.dart                    # App entry, MultiProvider setup
│   ├── providers/
│   │   ├── bluetooth_provider.dart   # Bluetooth connection, packet parsing (30 bytes), auth state machine
│   │   ├── sensor_data_provider.dart # UI state, isolate communication
│   │   ├── sensor_data_isolate.dart # Background processing, shot detection, scoring, calibration
│   │   ├── settings_provider.dart   # Firearm type, training mode, preferences
│   │   ├── session_provider.dart    # Session list management
│   │   └── session_logger.dart      # Save/load sessions to SharedPreferences
│   ├── screens/
│   │   ├── main_screen.dart         # Bottom nav + drawer navigation
│   │   └── tabs/
│   │       ├── home_tab.dart        # Home / dashboard
│   │       ├── graph_tab.dart       # Live gyro + muzzle trace (toggle), inline action buttons
│   │       ├── shot_timer_tab.dart  # Shot timer with countdown & splits
│   │       ├── analysis_tab.dart     # Post-shot analysis: big score + 3-phase chart + session history
│   │       ├── connection_tab.dart   # Bluetooth device selection
│   │       └── settings_tab.dart    # Firearm type, training mode, graph duration
│   ├── widgets/
│   │   ├── gyro_realtime_chart.dart # Syncfusion line chart (X/Y/Z gyro)
│   │   ├── muzzle_trace_widget.dart # CustomPainter XY muzzle trace
│   │   ├── control_panel.dart       # Record/Calibrate/Save buttons (deprecated — inline in graph_tab.dart)
│   │   └── status_bar.dart          # Connection status display (deprecated — removed from graph_tab.dart)
│   ├── models/
│   │   └── data_models.dart         # DataPoint, SessionLog, ShotResult, FirearmType, TrainingMode
│   └── Utils/
│       └── ring_buffer.dart          # Efficient circular buffer for sliding window
│
├── lib/theme/app_theme.dart         # Dark theme (on redesign/v1 branch only)
└── lib/screens/main_shell.dart       # 5-tab shell navigation (on redesign/v1 branch only)
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
    │ Auth state machine (AuthState enum)
    ▼
SensorDataProvider (sensor_data_provider.dart)
    │ Forwards to isolate, updates battery
    ▼
SensorDataIsolate (sensor_data_isolate.dart)
    │ Runs on separate Dart isolate (background)
    │ - Ring buffer management
    │ - Shot detection state machine
    │ - MantisX-style scoring
    │ - Calibration (50 samples → calibration_progress every 10)
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

### Authentication Protocol

```
Flutter -> ESP32: <16-char random challenge>\n
ESP32 -> Flutter: READY\n
ESP32 -> Flutter: 2.0-OVERSAMPLE\n  (Flutter sends challenge after READY received)
ESP32 -> Flutter: SHA256(challenge + SECRET_KEY) in hex\n
Flutter -> ESP32: AUTH_SUCCESS\n
```

**Secret Key**: `12ebaf10h12fa9123z21sti`

**Auth State Machine** (`bluetooth_provider.dart`):
```dart
enum AuthState {
  idle,           // Not in auth mode
  waitingForHash, // READY received, waiting for hash response
  done,           // Auth successful
  failed,         // Auth failed
}
```
- ESP32 may send "READY" multiple times (after reboot) — state machine handles this
- Completer only completed on 64-char hex hash response (NOT on every line)
- On disconnect: all auth state, buffers, and completer are reset for reconnect

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

## Calibration

- Collects 50 gyro samples while sensor is stationary
- Isolate sends `calibration_progress` every 10 samples
- Isolate sends `calibration_complete` with offsets when done
- UI shows: `Calibrating... (15/50)` countdown
- Calibration button requires `btProvider.isAuthenticated == true` before enabling
- Calibration offsets subtracted from raw gyro data in isolate processing

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
SensorDataMessage('ui_update', {...})              // Display data
SensorDataMessage('calibration_started')
SensorDataMessage('calibration_progress', {count, total})  // Every 10 samples
SensorDataMessage('calibration_complete', {offsets})
SensorDataMessage('shot_detected', {shot})           // New shot scored
SensorDataMessage('recording_started')
SensorDataMessage('recording_stopped')
SensorDataMessage('session_data', {...})             // Full session on save
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
- Uses `List.from()` copy to avoid concurrent modification during updates

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
- Wired to `SensorDataProvider.onShotDetected` callback

### AnalysisTab
- **Dedicated Analysis tab** in drawer navigation
- **Big score display**: Large centered score number, color-coded (green >90, yellow >70, red)
- **3-Phase Chart**: CustomPainter plotting Hold (red), Press (yellow), Recoil (cyan) curves normalized to break point. Auto-scales to max deviation.
- **Phase scores**: Hold, Press, Recoil, Elevation, Windage chips
- **Session history list**: Scrollable list of all shots — tap to select. Shows: shot number, time, split, score badge, phase scores
- **Session stats**: Shot count + average score
- `ShotResult` now includes `holdX/Y`, `pressX/Y`, `recoilX/Y` lists for plotting

---

## Graph Tab Layout

The graph tab uses inline widgets instead of imported sub-widgets:

```dart
// Control buttons at top (inline _ActionButton widget)
Record/Calibrate/Save → Consumer<SensorDataProvider> + Consumer<BluetoothProvider>
Chart toggle: Gyro (SfCartesianChart) | Trace (CustomPainter XY)

// StatusBar widget is REMOVED from graph_tab.dart
// ControlPanel widget is DEPRECATED — use inline _ActionButton pattern
```

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
- Flutter app: Real device required for Bluetooth
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

## Active Branches

| Branch | Status | Description |
|--------|--------|-------------|
| `develop` | Active (main dev) | Original UI + auth/calibration fixes |
| `redesign/v1` | Separate | Professional dark theme, new navigation shell |
| `main` | Base | Initial commit only |

**Workflow**: Test Bluetooth hardware on `develop` branch. Apply redesign from `redesign/v1` once validated.

---

## Known Issues / TODOs

### Done / Fixed
- [x] **Buffer overflow** — removed `MAX_PACKETS_PER_CYCLE = 5` limit. All packets now processed per cycle.
- [x] **Bluetooth auth state machine** — added `AuthState` enum, fixed "Future already completed" bug, fixed reconnect.
- [x] **Graph tab redesign** — StatusBar removed, inline `_ActionButton` for Record/Calibrate/Save.
- [x] **Calibration progress UI** — isolate sends `calibration_progress` every 10 samples, countdown displayed.
- [x] **Isolate SendPort race condition** — listener attached BEFORE isolate spawned to prevent lost messages.
- [x] **Calibration SendPort type mismatch** — isolate sent `SensorDataMessage('send_port', {port})` but provider checked `if (message is SendPort)`. Fixed: isolate now sends raw `SendPort` directly. **Confirmed fixed by user testing.**
- [x] **Session save not working** — isolate `_stopRecording()` now sends `session_data` immediately before clearing. Provider now calls `notifyListeners()` after `_handleSessionData`. `_clearSessionData()` no longer called in `_stopRecording()`.
- [x] **Shot timer not detecting shots** — `sensor_data_provider.dart` now has `onShotDetected` callback. `shot_timer_tab.dart` wires it up in `initState` and clears in `dispose`.
- [x] **Gyro graph duration hardcoded 5s** — `updateDependencies()` now sends `displayWindowSeconds` to isolate. `_handleDiffUpdate()` uses `_settingsProvider.maxSamples` instead of hardcoded 5. Isolate rebuilds buffers on window change.
- [x] **Muzzle trace showing full session (too long)** — trace widget now filters gyro data to 2-second rolling window (`_traceWindowMs = 2000`). Reintegrates from windowed data to prevent drift. **Confirmed fixed by user testing.**
- [x] **Post-shot analysis tab** — Added dedicated Analysis tab (drawer navigation) with: big score display, 3-phase CustomPainter chart (Hold/Press/Recoil curves), session history list with tappable shots, session stats. `ShotResult` model extended with `holdX/Y`, `pressX/Y`, `recoilX/Y` trace lists. Isolate sends phase trace data on shot detection.

### In Progress
- _None currently_

### Pending
- [ ] **Trace window sync with Python** — Flutter trace shows 2s window (absolute coords). Python shows 0.5s (cursor-normalized). May want to align.
- [ ] **Demo mode not implemented**: "Explore App" button for testing without hardware not yet built.
- [ ] **Battery monitoring**: Battery percentage received in packets but not consistently displayed in UI.
- [ ] **Export service**: `export_service.dart` not yet implemented.
- [ ] **Redesign branch not merged**: Dark theme (`app_theme.dart`) and new navigation shell (`main_shell.dart`) exist only on `redesign/v1` branch — not yet merged to `develop`.
- [ ] Python uses Hardcore scoring, Flutter uses MantisX-style — consider unifying.

### Debug Logging (for calibration troubleshooting)
All debug logs use `[PROVIDER]` and `[GRAPH]` tags:
```
[PROVIDER] Listener attached, spawning isolate...
[PROVIDER] Isolate spawned, waiting for SendPort...
[PROVIDER] ✅ Received SendPort from isolate! Isolate is READY.    ← Should appear
[PROVIDER] 🔄 Flushing N pending message(s)...                      ← If messages were queued
[PROVIDER] startCalibration() called, _isolateSendPort: OK/NULL     ← KEY CHECK
[PROVIDER] ⚠️ Isolate not ready, queuing calibration message       ← If port not ready
[PROVIDER] Received calibration_started from isolate
[PROVIDER] Calibration progress: 10/50 ... 20/50 ... 50/50
[PROVIDER] Calibration COMPLETE!
[GRAPH] Calibrate button tapped — isAuth: true/false
```

### Calibration Data Flow
```
User taps Calibrate
  → graph_tab.dart: sensorData.startCalibration()
    → sensor_data_provider.dart: _isolateSendPort?.send('start_calibration')
      → sensor_data_isolate.dart: _handleMessage('start_calibration') → _startCalibration()
        → isolate sets _isCalibrating = true, sends 'calibration_started'
          → provider receives 'calibration_started' → _isCalibrating = true, notifyListeners()
            → UI shows "Calibrating..." button
        → isolate accumulates 50 gyro samples
          → every 10 samples: sends 'calibration_progress'
          → at 50 samples: sends 'calibration_complete' with offsets
            → provider receives 'calibration_complete' → _isCalibrated = true, notifyListeners()
              → UI shows calibrated state
```

### Calibration Requirements
1. `_isolateSendPort` must be non-null (SendPort received from isolate)
2. Calibration message must reach isolate
3. Isolate must receive binary sensor data (gyro samples) during calibration
4. 50 samples collected → offsets applied → `_isCalibrated = true`
