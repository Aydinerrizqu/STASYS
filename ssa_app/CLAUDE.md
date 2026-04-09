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
│   ├── theme/app_theme.dart          # Dark STSYS theme (#FFB693 primary, #131313 bg, Manrope/Inter fonts)
│   ├── providers/
│   │   ├── bluetooth_provider.dart   # 8-state packet parser, CRC16-CCITT, HMAC-SHA256 auth
│   │   │                              # + getConfig(), setDataMode(), CMD_SET_CONFIG, EVT_SENSOR_HEALTH (0x13)
│   │   ├── sensor_data_provider.dart  # UI state, isolate communication
│   │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis (hold/press/recoil)
│   │   ├── settings_provider.dart     # Firearm type, training mode, preferences
│   │   ├── session_provider.dart     # Session list management
│   │   └── session_logger.dart       # Save/load sessions to SharedPreferences
│   ├── screens/
│   │   ├── main_screen.dart          # Bottom nav bar (HOME / LIVE / HISTORY / SETTINGS)
│   │   └── session_detail_screen.dart
│   ├── screens/tabs/
│   │   ├── home_tab.dart             # Dashboard
│   │   ├── graph_tab.dart            # 2 tabs: TRACE (muzzle trace) + POST SHOT (3-phase analysis)
│   │   ├── connection_tab.dart        # Bluetooth device selection
│   │   ├── settings_tab.dart          # Firearm type, training mode
│   │   └── shot_timer_tab.dart        # Shot timer with countdown & splits
│   ├── widgets/
│   │   ├── muzzle_trace_widget.dart   # MantisX-style live trace
│   │   ├── shot_analysis_panel.dart  # 3-phase post-shot chart with ring overlay
│   │   ├── shot_history_list.dart    # Session shot list with tappable cards
│   │   ├── gyro_realtime_chart.dart   # Real-time gyro chart
│   │   ├── interactive_chart.dart
│   │   ├── control_panel.dart
│   │   ├── status_bar.dart
│   │   ├── benchmark_analysis_widget.dart
│   │   └── debug_overlay.dart
│   └── models/
│       └── data_models.dart          # DataPoint, SessionLog, ShotResult, FirearmType, TrainingMode
```

---

## Communication Protocol (Packet-Based)

> **See parent `CLAUDE.md`: Communication Protocol > Binary Packet Format**

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
- `_sendPacket()` — builds outgoing frames (CRC over TYPE+LEN+payload)
- `getConfig()` / `_handleRspConfig()` — fetch firmware config including `data_mode`
- `setDataMode()` — send `CMD_SET_CONFIG` to change data_mode
- `CMD_SET_CONFIG (0x05)` — set firmware config (sample rate, piezo threshold, data mode, etc.)
- `EVT_SENSOR_HEALTH (0x13)` — handled silently (sensor health heartbeat ~10Hz)

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
1. Flutter connects → ESP32 sends `EVT_AUTH_CHALLENGE (0x14)`
2. Flutter: HMAC-SHA256(challenge + session_id) → `CMD_AUTH (0x06)`
3. ESP32: `EVT_AUTH_SUCCESS (0x15)` → Flutter authenticated
4. Flutter calls `startSession()` → `CMD_START_SESSION` → ESP32 sends `EVT_SESSION_STARTED (0x10)`
5. ESP32 streams `DATA_RAW_SAMPLE (0x20)` @ 100Hz

---

## Scoring System

> **See parent `CLAUDE.md`: Key Algorithms > MantisX-Style Scoring**
>
> Flutter app uses **MantisX-style soft curve** scoring (sqrt-based penalties).

---

## Shot Detection State Machine

> Flutter implementation: `providers/sensor_data_isolate.dart` → `ShotDetector` class.

### Thresholds
- **Stability Window**: 200ms
- **Gyro Limit**: 4.0 rad/s (ARMING state)
- **Trigger**: Piezo > 100 (dry fire) or jerk > 12.0 (live fire)
- **Cooldown**: 500ms

> **Note**: Shot detection runs in **Flutter isolate**, NOT in firmware.
> Full 3-phase analysis (hold/press/recoil) is computed in isolate.

---

## Calibration

Located in `providers/sensor_data_isolate.dart` → `_startCalibration()`.

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

### MuzzleTraceWidget
**Committed version** (`HEAD`):
- **Live dot**: ACCELEROMETER (`accelX/Y`) — absolute tilt, NO drift
- **Trace path**: GYRO integration with **2000ms window**, `_maxTracePoints = 200`
- **Phase colors**: Hold=Red, Press=Yellow, Recoil=Cyan (old palette)
- **Scoring rings**: 5 concentric zones (Elite/Expert/Advanced/Intermediate/Beginner)

**Uncommitted enhancement** (current working tree):
- Same accelerometer dot + gyro trace
- **Opacity fade**: oldest = 0.3α, newest = 1.0α (trace segments fade out)
- **Motion blur**: 3 ghost trail dots behind current dot at decreasing opacity
- **Dynamic dot sizing**: 5-8px based on movement velocity
- **Sensitivity increased**: 0.05 → 0.08
- **Dark STSYS colors**: Hold=#FFB693 (orange), Press=#8BCEFF (blue), Recoil=#FFB4AB (coral)
- **Smart `shouldRepaint`**: checks dot position, trace length, phase, liveSpeed
- **`RepaintBoundary`**: isolates painter repaints
- **`Timer`**-based phase transitions (no Future.delayed closures)

### MainScreen
- Bottom Navigation Bar (4 tabs): HOME / LIVE / HISTORY / SETTINGS
- AppBar with STASYS logo + `StatusBadge` (connection status)
- Shot Timer tab removed from navigation

### GraphTab (2 tabs: TRACE + POST SHOT)
- **TRACE tab**: Real-time muzzle trace widget (always streaming)
- **POST SHOT tab**: 3-phase analysis + session history
  - Auto-updates to latest shot when new shot is detected
  - Tap any shot in history list to view that shot's 3-phase chart
  - Shows "NO SHOTS RECORDED" when session has no shots

### ConnectionTab
- Connection status card (connected/disconnected with device info)
- SCAN + PAIRED action buttons with STSYS styling
- Device list with connected indicator

### HomeTab & SettingsTab
- Full dark STSYS theme styling
- Surface containers, Manrope/Inter typography

### ShotHistoryList
- StatefulWidget with cached stats (avg score, shot count)
- Tappable shot cards for 3-phase chart selection

### ShotTimerTab
- Countdown: 3s, 5s, 10s selectable
- Color-coded split performance

### GyroRealtimeChart
- Syncfusion `SfCartesianChart`, 3 lines: X/Y/Z gyro
- Configurable sliding window (3-15 seconds)
- Direct provider references (no extra `List.from()` copies)
- **Data decimation**: isolate sends max 150 points, ~70% data reduction

---

## Dependencies (pubspec.yaml)

```yaml
flutter_bluetooth_serial: ^0.4.0      # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7   # Charts
fl_chart: ^1.0.0                      # Alternative charts
provider: ^6.1.2                      # State management
shared_preferences: ^2.2.2            # Local storage
permission_handler: ^12.0.1           # Android permissions
path_provider: ^2.1.1                  # File paths
crypto: ^3.0.3                        # SHA256 auth
intl: ^0.19.0                         # Formatting
```

---

## Active Branches

| Branch | Status | Description |
|--------|---------|-------------|
| `develop-migrasi-firmware-v3` | **Active** | Current working branch — committed: dark STSYS theme + dark nav, bottom nav redesign, connection_tab, graph_tab, home_tab, settings_tab redesign; uncommitted: muzzle trace enhancement (opacity fade, motion blur, dynamic dot, STSYS colors) |
| `backup-dark-theme-redesign` | Backup | Full backup of all uncommitted changes pushed to remote |
| `develop` | Staged | Dark theme elements pending merge |
| `main` | Base | Initial commit only |

---

## Known Issues / TODOs

### In Progress
- [ ] **Shot history tap reverts to latest** — tapping a shot in history list doesn't persist, reverts to latest shot.
- [ ] **Frame freeze / gralloc4 GPU failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.

### Pending
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
- [ ] **Demo mode not implemented** — testing without hardware not yet built.
- [ ] **Battery monitoring** — battery % received but not displayed consistently.
- [ ] **Export service** — `export_service.dart` not yet implemented.
- [ ] **MantisX feature parity** — drill modes, trend analysis, split time, session notes, etc.

### Performance Optimizations (Phase 1 & 2 — 2026-04-07)
**Goal**: Stable 60fps, production-ready code. All changes compile and APK builds successfully.

#### Phase 1 — 6 fixes
- [x] **`_handleDiffUpdate` O(n) removeWhere** → immutable list assignment. Eliminated O(n) scanning on main thread.
- [x] **Data decimation** — isolate sends max 150 points (was ~500), ~70% data reduction via `_decimate()`.
- [x] **Smart `shouldRepaint`** — `_MuzzleTracePainter` compares dot position, last trace point, phase color.
- [x] **`RepaintBoundary`** — added around `MuzzleTraceWidget` CustomPaint.
- [x] **postFrameCallback consolidation** — `_PostShotTabState` uses single `_scheduleShotUpdate()` with guard flag.
- [x] **UI throttle** — reduced from 50ms (20Hz) to 33ms (~30Hz) for more headroom toward 60fps.

#### Phase 2 — 9 fixes
- [x] **CustomPainter Paint/Color allocations** — All painters pre-allocate Paint/TextPainter as static fields. **~1,100 object allocations/sec eliminated.**
- [x] **`RepaintBoundary` on chart painters** — Added to `_LatestShotPanel` and `ShotAnalysisPanel`.
- [x] **ShotHistoryList cached stats** — Converted to `StatefulWidget`, avg/count computed once.
- [x] **Home tab redundant sort removed** — `SessionProvider.loadSessions()` already sorts.
- [x] **`_handleDiffUpdate` direct cast** — `List<DataPoint>.from()` → direct `as List<DataPoint>` cast. **~180 list allocations/sec eliminated.**
- [x] **`_analyzeShot()` Float64List** — Replaced `List<double>.from()`, `sublist()`, `map().toList()` with `Float64List` typed arrays. **~20 list allocations per shot eliminated.**
- [x] **Recording timer `ValueNotifier`** — `_recordingTimer` updates `recordingDurationNotifier` instead of `notifyListeners()`. No global rebuild every second.
- [x] **Timer replaces Future.delayed** — `_MuzzleTraceWidgetState` uses `Timer` with `_phaseResetTimer` cancellation.

---

## Debug Logging

Bluetooth debug logs in `bluetooth_provider.dart`:
```
[BT] Sent CMD_START_SESSION
[BT] Sent CMD_AUTH with HMAC-SHA256
[BT] Auth successful
[BT] Session started: ...
[CFG] *** data_mode=N ***  (printed on connect)
```

### Auth Flow (verified working)
```
Flutter connect → ESP32 sends EVT_AUTH_CHALLENGE (0x14)
  → _handleAuthChallenge() → HMAC-SHA256 → _sendPacket(CMD_AUTH)
  → ESP32 sends EVT_AUTH_SUCCESS (0x15) + EVT_SESSION_STARTED (0x10)
  → Flutter: _authState = authenticated, _sessionActive = true
  → DATA_RAW_SAMPLE (0x20) streams @ 100Hz
    → _handleRawSample() → int16→float → sensorDataProvider.updateAllData()
```
