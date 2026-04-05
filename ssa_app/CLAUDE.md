# STASYS Flutter App - Development Guide

> **Note**: This is the Flutter-specific companion to the root `CLAUDE.md`.
> For firmware architecture, communication protocol details, and firmware build
> instructions, see the parent `CLAUDE.md` at the project root.

## Project Purpose

Mobile companion app for the STASYS shooter stability analyzer. Primary platform for live training sessions.

---

## Architecture

```
ssa_app/
├── lib/
│   ├── main.dart                    # App entry, MultiProvider setup
│   ├── providers/
│   │   ├── bluetooth_provider.dart   # 8-state packet parser, CRC16-CCITT, HMAC-SHA256 auth
│   │   ├── sensor_data_provider.dart  # UI state, isolate communication
│   │   ├── sensor_data_isolate.dart # Shot detection + 3-phase analysis (hold/press/recoil)
│   │   ├── settings_provider.dart     # Firearm type, training mode, preferences
│   │   ├── session_provider.dart      # Session list management
│   │   └── session_logger.dart        # Save/load sessions to SharedPreferences
│   ├── screens/tabs/
│   │   ├── home_tab.dart            # Home / dashboard
│   │   ├── graph_tab.dart           # Real-time gyro + muzzle trace + post-shot inline
│   │   ├── shot_timer_tab.dart      # Shot timer with countdown & splits
│   │   ├── analysis_tab.dart         # Post-shot analysis: big score + 3-phase chart + history
│   │   ├── connection_tab.dart        # Bluetooth device selection
│   │   └── settings_tab.dart         # Firearm type, training mode, graph duration
│   ├── widgets/
│   │   ├── muzzle_trace_widget.dart  # Real-time XY trace (2s rolling window, 3-phase coloring)
│   │   ├── shot_analysis_panel.dart  # 3-phase chart CustomPainter + phase scores
│   │   └── shot_history_list.dart     # Session shot list with tappable cards
│   └── models/
│       └── data_models.dart          # DataPoint, SessionLog, ShotResult, FirearmType, TrainingMode
│
├── lib/theme/app_theme.dart          # Dark theme (on redesign/v1 branch only)
└── lib/screens/main_shell.dart       # 5-tab shell navigation (on redesign/v1 branch only)
```

---

## Communication Protocol (NEW: Packet-Based)

> **See parent CLAUDE.md: Communication Protocol > Binary Packet Format**

### Packet Format
```
[0xAA][0x55][TYPE:1][LEN_LO:1][LEN_HI:1][payload:N][CRC_LO:1][CRC_HI:1]
  CRC16-CCITT over TYPE(1)+LEN_LO(1)+LEN_HI(1)+payload(N) = 3+N bytes (init=0xFFFF, poly=0x1021)
```

### Parser State Machine (8 states)
`waitSync0 → waitSync1 → readType → readLenLo → readLenHi → readPayload → readCrcLo → readCrcHi`

Located in `bluetooth_provider.dart`:
- `_ParserState` enum (8 values)
- `_recvBuffer` — accumulates bytes
- `_feedParserByte()` — byte-level state machine
- `_crc16Ccitt()` / `_updateCrc()` — running CRC computation
- Debug logging active: `[RX]` raw chunks, `[BT] CRC FAIL` with byte dump (first mismatch only)

### DATA_RAW_SAMPLE Handling
- Payload **must be 24 bytes** (verified: `sizeof(PktRawSample) = 24` on ESP32)
- Length field: `0x18, 0x00` (little-endian 24)
- Offsets: counter(0-3), timestamp(4-7), accel_x/y/z(8-13), gyro_x/y/z(14-19), piezo(20-21), reserved(22-23)
- Conversion: accel(raw int16) / 8192.0 * 9.81 → m/s², gyro(raw int16) / 65.5 * 0.0174533 → rad/s

### Auth State Machine (4 states)
```
idle → waitingForChallenge → authenticated/failed
```

Flow:
1. Flutter connects → ESP32 sends EVT_AUTH_CHALLENGE (0x14)
2. Flutter: HMAC-SHA256(challenge + session_id) → CMD_AUTH (0x06)
3. ESP32: EVT_AUTH_SUCCESS (0x15) → Flutter authenticated
4. Flutter calls `startSession()` → CMD_START_SESSION → ESP32 sends EVT_SESSION_STARTED (0x10)
5. ESP32 streams DATA_RAW_SAMPLE (0x20) @ 100Hz

5. ESP32 streams DATA_RAW_SAMPLE (0x20) @ 100Hz — All packets now pass CRC.

---

## Scoring System

> **See parent CLAUDE.md: Key Algorithms > MantisX-Style Scoring**
>
> Flutter app uses **MantisX-style soft curve** scoring (sqrt-based penalties).
> Python app uses **Hardcore** scoring (hard penalties). Both can read the same SQLite DB.

---

## Shot Detection State Machine

> **See parent CLAUDE.md: Key Algorithms > Shot Detection State Machine**
>
> Flutter implementation: `providers/sensor_data_isolate.dart` → `ShotDetector` class.
>
> ### Thresholds
> - **Stability Window**: 200ms
> - **Gyro Limit**: 4.0 rad/s (ARMING state)
> - **Trigger**: Piezo > 100 (dry fire) or jerk > 12.0 (live fire)
> - **Cooldown**: 500ms

> **Note**: Shot detection runs in **Flutter isolate**, NOT in firmware.
> Firmware sends `EVT_SHOT_DETECTED` (0x12) with peaks for logging/debugging only.
> Full 3-phase analysis (hold/press/recoil) requires full time-series — computed in isolate.

---

## Calibration

Located in `providers/sensor_data_isolate.dart` → `_startCalibration()`.

- Collects 50 gyro samples while sensor is stationary
- Isolate sends `calibration_progress` every 10 samples
- Isolate sends `calibration_complete` with offsets when done
- UI shows: `Calibrating... (15/50)` countdown
- Calibration button requires `btProvider.isAuthenticated == true` before enabling
- Calibration offsets subtracted from raw gyro data in isolate processing

**Calibration Requirements:**
1. `_isolateSendPort` must be non-null (SendPort received from isolate)
2. Calibration message must reach isolate
3. Isolate must receive binary sensor data (gyro samples) during calibration
4. 50 samples collected → offsets applied → `_isCalibrated = true`

---

## Provider Communication

### BluetoothProvider → SensorDataProvider
```dart
sensorDataProvider.updateAllData(
  ax, ay, az, gx, gy, gz, battery, piezo  // from DATA_RAW_SAMPLE (24 bytes)
);
```

### SensorDataProvider ↔ Isolate
```dart
// Provider → Isolate
SensorDataMessage('sensor_data', {ax, ay, az, gx, gy, gz, piezo, battery})
SensorDataMessage('start_calibration')
SensorDataMessage('start_recording')
SensorDataMessage('stop_recording')
SensorDataMessage('update_settings', {firearmType, trainingMode})
SensorDataMessage('request_full_sync')

// Isolate → Provider
SensorDataMessage('ui_update', {...})
SensorDataMessage('calibration_started')
SensorDataMessage('calibration_progress', {count, total})  // Every 10 samples
SensorDataMessage('calibration_complete', {offsets})
SensorDataMessage('shot_detected', {shot})
SensorDataMessage('recording_started')
SensorDataMessage('recording_stopped')
SensorDataMessage('session_data', {...})
SensorDataMessage('reset_complete')
```

---

## Settings Persistence

- **SharedPreferences** for app settings
- **SessionLogger** stores `SessionLog` objects as JSON in SharedPreferences
- **Key strings**: `firearmType`, `trainingMode`, `maxSamples`

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
- `holdX/Y`, `pressX/Y`, `recoilX/Y` trace lists for 3-phase analysis plotting

---

## Widgets

### GyroRealtimeChart
- Syncfusion `SfCartesianChart`, 3 lines: X/Y/Z gyro
- Configurable sliding window (3-15 seconds)
- Score indicator badge

### MuzzleTraceWidget
- Custom `CustomPainter` for real-time XY plot
- 3-phase coloring: Hold (red), Press (yellow), Recoil (cyan)
- 2-second rolling window
- Concentric circle grid + current position dot

### ShotAnalysisPanel
- 3-phase CustomPainter chart (Hold/Press/Recoil curves)
- Phase scores chips + big score display

### ShotHistoryList
- Scrollable shot cards with tappable selection
- Session stats: shot count + average score

### ShotTimerTab
- Countdown: 3s, 5s, 10s selectable
- Color-coded split performance

---

## Common Tasks

### Changing Bluetooth packet format
1. Update `bluetooth_provider.dart` parser state machine + offsets
2. Update `_handleRawSample()` data conversion
3. Update `SensorDataProvider.updateAllData()` signature
4. Update `sensor_data_isolate.dart` `_processSensorData()`
5. Update firmware `protocol.h/cpp` and `DATA_RAW_SAMPLE` packet format
6. Update protocol docs in parent `CLAUDE.md`

---

## Testing Without Hardware

- Flutter app: Real device required for Bluetooth
- No mock mode currently implemented

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
| `develop` | Active | New packet protocol + PlatformIO firmware |
| `redesign/v1` | Separate | Dark theme, new navigation shell |
| `main` | Base | Initial commit only |

---

## Known Issues / TODOs

### Done / Fixed
- [x] **Buffer overflow** — removed `MAX_PACKETS_PER_CYCLE = 5` limit.
- [x] **Bluetooth auth state machine** — added `AuthState` enum, fixed reconnect.
- [x] **Graph tab redesign** — StatusBar removed, inline `_ActionButton`.
- [x] **Calibration progress UI** — isolate sends `calibration_progress` every 10 samples.
- [x] **Isolate SendPort race condition** — listener attached BEFORE isolate spawned.
- [x] **Calibration SendPort type mismatch** — isolate sends raw `SendPort` directly.
- [x] **Session save not working** — isolate sends `session_data` before clearing.
- [x] **Shot timer not detecting shots** — `onShotDetected` callback wired.
- [x] **Gyro graph duration hardcoded 5s** — uses `_settingsProvider.maxSamples`.
- [x] **Muzzle trace too long** — 2-second rolling window (`_traceWindowMs = 2000`).
- [x] **Post-shot analysis tab** — 3-phase chart + shot history list.
- [x] **Protocol migration** — 8-state CRC16-CCITT parser in `bluetooth_provider.dart`.
- [x] **PlatformIO firmware scaffold** — all modules, uploaded to ESP32.
- [x] **Extracted widgets** — `ShotAnalysisPanel` and `ShotHistoryList`.
- [x] **esp_bt_gap.h not found** — GAP callback removed.
- [x] **Preferences::getString() wrong args** — fixed in config.cpp.
- [x] **sensor.cpp goto crosses initialization** — declarations moved.
- [x] **mbedtls/hmac.h not found** — security.cpp stubbed.
- [x] **RecoveryTask watchdog timeout** — added `esp_task_wdt_reset()` in loop.
- [x] **CMD_START_SESSION guard blocking auth** — removed `_isAuthenticated` check.
- [x] **Firmware not sending EVT_AUTH_CHALLENGE** — added to dispatchCommand.
- [x] **PktRawSample sizeof mismatch** — changed to 24 bytes (was: temperature → compiler-packed to 24 not 26).
- [x] **ESP32 TX serial debug flooding** — limited to first 3 packets.
- [x] **CRC scope mismatch** — Firmware computed CRC over `2+len`, Flutter over `3+len`. Fixed firmware `encodePacket()`.
- [x] **EVT_SENSOR_HEALTH (0x13) unknown** — Added handler in `_handlePacket()` switch.

### In Progress
- [ ] **Android BT fragmentation** — ~0.01% CRC error on DATA_RAW packets from Android BT buffer chunking.

### Pending
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
- [ ] **Demo mode not implemented** — testing without hardware not yet built.
- [ ] **Battery monitoring** — battery % received but not displayed consistently.
- [ ] **Export service** — `export_service.dart` not yet implemented.
- [ ] **Redesign branch not merged** — dark theme not in `develop`.

---

## Debug Logging

Bluetooth debug logs in `bluetooth_provider.dart`:
```
[BT] Sent CMD_START_SESSION
[BT] Sent CMD_AUTH with HMAC-SHA256
[BT] Auth successful
[BT] Session started: ...
[BT] CRC FAIL: type=0x20, len=24, bytes=...  (first mismatch only)
[RX] raw len=N: ...  (first 3 BT receive chunks only)
```

### Auth Flow Data Flow (verified working)
```
Flutter connect → ESP32 sends EVT_AUTH_CHALLENGE (0x14)
  → _handleAuthChallenge() → HMAC-SHA256 → _sendPacket(CMD_AUTH)
  → ESP32 sends EVT_AUTH_SUCCESS (0x15) + EVT_SESSION_STARTED (0x10)
  → Flutter: _authState = authenticated, _sessionActive = true
  → DATA_RAW_SAMPLE (0x20) streams @ 100Hz
    → _handleRawSample() → int16→float → sensorDataProvider.updateAllData()
```
