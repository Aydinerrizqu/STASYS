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
│   ├── main.dart                    # App entry, MultiProvider + GoRouter
│   ├── router/app_router.dart       # GoRouter configuration (ShellRoute)
│   ├── theme/app_theme.dart         # Dark STSYS theme (#FFB693 primary, #131313 bg, Manrope/Inter fonts)
│   ├── services/
│   │   ├── database_helper.dart     # SQLite singleton, schema creation, migrations
│   │   ├── database_service.dart    # CRUD operations, binary BLOB encoding
│   │   └── export_service.dart      # CSV export via Share Sheet
│   ├── providers/
│   │   ├── bluetooth_provider.dart  # Text auth (READY→challenge→SHA256 hex) + dual-mode parser
│   │   │                              # Binary: 0xAA 0xBB + 6 floats + piezo + battery + XOR checksum
│   │   │                              # 3-state parser: waitingForReady → waitingForHash → streaming
│   │   ├── sensor_data_provider.dart  # UI state, isolate communication, demo mode
│   │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis (hold/press/recoil)
│   │   │                              # + auto-calibration on first 50 samples (gyro zero-offset)
│   │   ├── settings_provider.dart     # Firearm type, training mode, demo mode, preferences
│   │   ├── session_provider.dart     # Session list management
│   │   └── session_logger.dart       # Delegates to DatabaseService (SQLite)
│   ├── screens/
│   │   ├── splash_screen.dart        # STSYS branding, 2s auto-navigate
│   │   ├── connection_screen.dart     # BT scan/connect + Explore App demo mode
│   │   ├── main_shell.dart           # Bottom 3-tab navigation shell
│   │   ├── tracking_screen.dart      # Mode selection (4 firearm cards)
│   │   ├── tracking_mode_view.dart   # Live graph with mode change dialog
│   │   ├── history_screen.dart       # Session list + export CSV + clear all + refresh
│   │   ├── settings_screen.dart      # BT scan overlay + settings
│   │   └── session_detail_screen.dart # POST SHOT + shot chips
│   ├── screens/tabs/
│   │   ├── graph_tab.dart            # TRACE (muzzle trace) + POST SHOT (3-phase analysis)
│   │   ├── home_tab.dart             # Dashboard (STSYSStyle)
│   │   ├── connection_tab.dart        # Bluetooth device selection
│   │   ├── settings_tab.dart         # Firearm type, training mode
│   │   └── shot_timer_tab.dart       # Shot timer with countdown & splits
│   ├── widgets/
│   │   ├── muzzle_trace_widget.dart  # MantisX-style live trace
│   │   ├── shot_analysis_panel.dart  # 3-phase post-shot chart with ring overlay
│   │   ├── shot_history_list.dart    # Session shot list with tappable cards
│   │   ├── gyro_realtime_chart.dart  # Real-time gyro chart
│   │   ├── interactive_chart.dart
│   │   ├── control_panel.dart
│   │   ├── status_bar.dart
│   │   ├── benchmark_analysis_widget.dart
│   │   └── debug_overlay.dart
│   └── models/
│       └── data_models.dart          # DataPoint, SessionLog, ShotResult, FirearmType, TrainingMode
```

---

## Navigation Flow (GoRouter)

```
App Launch
  └── SplashScreen (STSYS branding, 2s auto-navigate)
        └── ConnectionScreen
              ├── Scan Bluetooth → connect → /tracking
              └── Explore App → demo mode → /tracking

MainShell (3-tab bottom nav):
  ├── /tracking → TrackingScreen
  │     ├── ModeSelectionView (4 firearm cards)
  │     └── TrackingModeView (live graph + mode change dialog)
  ├── /history → HistoryScreen
  │     └── Session list + swipe delete + clear all + refresh
  └── /settings → SettingsScreen
        └── BT scan overlay + firearm type + training mode
```

---

## Demo Mode

Implemented in `sensor_data_provider.dart`:

- `setDemoMode(bool)` — enable/disable demo mode
- `_startDemoTimer()` — Timer.periodic(33ms) generates random gyro/accel data
- `_triggerDemoShot()` — auto-generates shot every 4-8s with score 60-95
- `isDemoMode` getter in `SettingsProvider`

**BT scan in demo mode**: Redirects to `/connection` screen.
**Connect in demo mode**: Auto-disables demo mode, switches to real sensor data.

**Trace data** (2026-04-26): Demo mode integrates gyro → trace coordinates stored in `_demoTracePoints`. Provider assigns `_traceXData`/`_traceYData`/`_liveTraceX`/`_liveTraceY` from these points every tick so the muzzle trace widget renders correctly. Cleared on demo mode stop.

---

## Communication Protocol (STASYS_FW)

> **Updated** (2026-05-05): Flutter app now uses STASYS_FW protocol from `dylemmas/STASYSFW`.
> Source: https://github.com/dylemmas/STASYSFW

### Binary Packet Format (31 bytes)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0xBB` |
| 2 | 4 | ax | float m/s² |
| 6 | 4 | ay | float m/s² |
| 10 | 4 | az | float m/s² |
| 14 | 4 | gx | float rad/s |
| 18 | 4 | gy | float rad/s |
| 22 | 4 | gz | float rad/s |
| 26 | 2 | piezo | uint16 ADC peak |
| 28 | 1 | battery | uint8 % |
| 29 | 2 | crc16 | CRC-16 CCITT over bytes 2-28 |

**Checksum**: CRC-16 CCITT (was XOR in older firmware)
- Initial: `0xFFFF`
- Polynomial: `0x1021`
- Coverage: bytes 2-28 (27 bytes)

### Authentication Protocol (unchanged)

```
Flutter → ESP32: "AUTH_CHALLENGE\n"
ESP32 → Flutter: SHA256("AUTH_CHALLENGE" + SECRET_KEY) hex (64 chars)
Flutter → ESP32: verifies hash
```

**Secret Key**: `12ebaf10h12fa9123z21sti`

### Firmware Features (STASYS_FW)

- **AHRS**: Madgwick filter for orientation
- **ZUPT**: Zero Velocity Update for runtime gyro bias correction
- **Factory Calibration**: 500 samples on first boot, offsets saved to NVS
- **Battery Monitoring**: 100Hz normal, 20Hz low battery, deep sleep at <5%
- **Session Timeout**: 5 minutes inactivity auto-disconnect

---

## Scoring System

> **See parent `CLAUDE.md`: Key Algorithms > MantisX-Style Scoring**

Flutter app uses **MantisX-style soft curve** scoring (sqrt-based penalties).

---

## Shot Detection State Machine

> Flutter implementation: `providers/sensor_data_isolate.dart` → `ShotDetector` class.

### Thresholds
- **Stability Window**: 200ms
- **Gyro Limit**: 4.0 rad/s (ARMING state)
- **Trigger**: Piezo > 100 (dry fire) or jerk > 12.0 (live fire)
- **Cooldown**: 500ms

> Shot detection runs in **Flutter isolate**, NOT in firmware.
> Full 3-phase analysis (hold/press/recoil) is computed in isolate.

---

## Calibration

Located in `providers/sensor_data_isolate.dart`.

**Auto-calibration on startup**: First 50 samples collected while sensor is stationary → compute gyro zero-offset (X/Y/Z). No manual calibration button needed. `_autoCalibrating` flag auto-triggers on first data, sends `calibration_complete` when done.

Legacy manual calibration: `CalibrationManager` class sends `calibration_progress` every 10 samples, `calibration_complete` with offsets when done. Requires `btProvider.isAuthenticated == true` before enabling. Calibration offsets subtracted from raw gyro data in isolate processing.

---

## Live Tracking (MantisX-Style)

### Architecture
- **Isolate** (`sensor_data_isolate.dart`): Gyro integration → quaternion → atan2 projection → trace coordinates
- **Widget** (`muzzle_trace_widget.dart`): 60fps ticker, dot lerp, camera follow, auto-zoom, trace painting

### Quaternion Projection (from stasysz.py)
1. Bias-correct raw gyro (`gx - offsetGx`)
2. Remap MPU6050 axes: `kGyroAxisX=2, kGyroAxisY=1, kGyroAxisZ=0`
3. Integrate quaternion: `_quatIntegrate(q, wx, wy, wz, dt)`
4. Compute relative quaternion: `qRel = normalize(qTare_conj * q)`
5. Project barrel vector `[0,0,1]` through `qRel` → screen coords via `atan2(-v[1], v[2])`, `atan2(v[0], v[2])`

### Auto-Tare (ShotDetector.autoTare)
Triggers when: hardware stationary for ~0.5s (gyro magnitude < 1.0 rad/s) AND trace drift > 0.02 rad (~1.1°)
- Resets `_qTare = _q.copy()` and clears trace buffer
- `stationaryThreshold = 1.0 rad/s`, `driftThreshold = 0.02 rad`, `autoTareInterval = 3.0s`
- **Critical**: `process()` receives **raw** gyro (not pre-corrected) — bias correction happens exactly once inside `process()` to avoid double-subtraction drift bug

### Camera Follow + Auto-Zoom
- Camera lerp: `_cameraLerp = 0.03` (~500ms delay)
- Auto-zoom: tracks max trace extent relative to camera center, zooms between `_minZoom=0.015` and `_maxZoom=0.12` with lerp `_autoZoomLerp=0.02`
- Dot lerp: `t = deltaMs/16.0` toward target position (smooth 60fps movement)

### Bug Fixed (2026-04-26)
Isolate was calling `fixedGx = gx - _offsetGyroX` then passing `fixedGx` to `process()`. Inside `process()`, it would `gxBc = gx - offsetGx` (where `offsetGx == _offsetGyroX`) → effectively `gx - 2*offsetGx`. This systematic double subtraction caused trace drift. Fixed by passing raw `gx/gy/gz` to `process()`.

---

## Session & Shot Data

### SessionLog (session_logger.dart → DatabaseService/SQLite)
Per-session data stored in SQLite with binary BLOB encoding.
`session_provider.dart` manages session list with `loadSessions()`, `deleteSession()`.

### ShotResult (data_models.dart)
Per-shot scoring:
- `totalScore`, `holdScore`, `pressScore`, `recoilScore`
- `elevationScore`, `windageScore`
- `travelDistance`, `peakJerk`
- `firearmType`, `trainingMode`, `timestamp`
- `holdX/Y`, `pressX/Y`, `recoilX/Y` trace lists for 3-phase analysis plotting

### Session Detail Screen
- POST SHOT 3-phase chart (H/P/R + ELEV/WIND)
- Horizontal shot chips (tap → chart updates)
- Delete session with confirmation

---

## Settings Persistence

- **SharedPreferences** for app settings only
- **SQLite** for session/shots persistence (stsys_sessions.db)
- **Key strings**: `firearmType`, `trainingMode`, `maxSamples`

---

## Export Service

`services/export_service.dart` exports all sessions to CSV via Share Sheet.

**CSV Format**:
```csv
# SESSIONS
session_date,firearm_type,training_mode,duration_sec,avg_score,best_score,worst_score,shot_count

# SHOTS
session_date,firearm_type,training_mode,shot_timestamp,total_score,hold_score,press_score,recoil_score,elevation_score,windage_score,travel_distance,peak_jerk
```

Export button in HistoryScreen header (visible when sessions exist).

---

## Dependencies (pubspec.yaml)

```yaml
flutter_bluetooth_serial: ^0.4.0      # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7   # Charts
fl_chart: ^1.0.0                      # Alternative charts
provider: ^6.1.2                      # State management
shared_preferences: ^2.2.2            # App settings only
sqflite: ^2.3.2                       # Session/shots persistence (SQLite)
path: ^1.9.0                          # Path utilities for DB
share_plus: ^10.0.0                  # CSV export via Share Sheet
permission_handler: ^12.0.1           # Android permissions
path_provider: ^2.1.1                  # File paths
crypto: ^3.0.3                        # SHA256 auth
intl: ^0.19.0                         # Formatting
go_router: ^15.1.0                    # Navigation routing
```

---

## Active Branches

| Branch | Status | Description |
|--------|---------|-------------|
| `PreProduction_0` | **Active** | TDD + STASYS_FW: CRC-16 checksum, 31-byte packets, memory leaks fixed, unit tests (27 passing), lifecycle-aware ticker |
| `migrasi_firmware_awal_v1` | Backup | Previous version with XOR checksum (30-byte packets) |
| `migrasi_firmware_awal` | Backup | Snapshot of earlier version |
| `backup-dark-theme-redesign` | Backup | Full backup of all uncommitted changes pushed to remote |
| `develop` | Staged | Dark theme elements pending merge |
| `main` | Base | Initial commit only |

---

## Known Issues / TODOs

### Pending
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
- [ ] **MantisX feature parity** — drill modes, trend analysis, split time, session notes, etc.
- [ ] **Frame freeze / gralloc4 GPU failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.

### Settings (Pending Implementation)
- [ ] Mount mode selector — `onTap` stub in settings_tab.dart
- [ ] Direction FW/BW toggle — `onChanged` empty in settings_tab.dart
- [ ] RESET AXIS button — `onTap` no-op in settings_tab.dart

---

## Performance Optimizations (Phase 1 & 2 — 2026-04-07)
**Goal**: Stable 60fps, production-ready code. All changes compile and APK builds successfully.

### Phase 1 — 6 fixes
- [x] **`_handleDiffUpdate` O(n) removeWhere** → immutable list assignment. Eliminated O(n) scanning on main thread.
- [x] **Data decimation** — isolate sends max 150 points (was ~500), ~70% data reduction via `_decimate()`.
- [x] **Smart `shouldRepaint`** — `_MuzzleTracePainter` compares dot position, last trace point, phase color.
- [x] **`RepaintBoundary`** — added around `MuzzleTraceWidget` CustomPaint.
- [x] **postFrameCallback consolidation** — `_PostShotTabState` uses single `_scheduleShotUpdate()` with guard flag.
- [x] **UI throttle** — reduced from 50ms (20Hz) to 33ms (~30Hz) for more headroom toward 60fps.

### Phase 2 — 9 fixes
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

---

## TDD Implementation & Production Readiness (2026-05-05)

### Completed Changes

#### Phase 1: Test Infrastructure ✅
- Added `mocktail: ^1.0.3` — library-based mocking (no code generation)
- Added `coverage: ^1.7.2` — coverage reporting
- Added `firebase_crashlytics: ^4.0.0` + `firebase_core: ^3.0.0` — crash reporting (pending setup)
- Created test directory structure:
  ```
  test/
  ├── unit/
  │   ├── models/data_models_test.dart
  │   └── utils/ring_buffer_test.dart
  ```

#### Phase 2: Critical Bug Fixes ✅
**Memory leak fixes:**
- `providers/sensor_data_provider.dart` — Fixed `dispose()`:
  - Added `_mainReceivePort?.close()` + null assignment
  - Added `_dataIsolate?.kill()` + null assignment
  - Added `_recordingTimer?.cancel()` + null assignment
  - Added `super.dispose()` call

- `providers/bluetooth_provider.dart` — Fixed `dispose()`:
  - Added `_dataSubscription = null` after cancel
  - Added `_connection = null` after dispose
  - Added `super.dispose()` call

**Error handling:**
- `providers/session_logger.dart` — Added try-catch to `saveSession()`:
  - Logs session ID on success
  - Logs error with stack trace on failure
  - Re-throws exception for caller handling

#### Phase 3: Unit Tests ✅
**27 tests passing:**
- `test/unit/models/data_models_test.dart` (16 tests):
  - FirearmType.fromString, displayName
  - TrainingMode.fromString, displayName
  - DataPoint creation, toMap, fromMap
  - ShotResult creation, serialization, deserialization
  - Null phase traces handling
  - Missing enum fallback handling

- `test/unit/utils/ring_buffer_test.dart` (11 tests):
  - Capacity, add, toList
  - Overflow behavior
  - Clear and resize operations
  - Edge cases (zero, negative resize)

#### Phase 4: Production Hardening ✅
**Battery efficiency:**
- `widgets/muzzle_trace_widget.dart` — Added `WidgetsBindingObserver`:
  - 60fps ticker stops when app backgrounded (AppLifecycleState.paused/inactive/hidden)
  - Ticker resumes when app foregrounded (AppLifecycleState.resumed)
  - Prevents battery drain while app not visible

### Pending Changes (TODO)

#### Firebase Crashlytics Setup
- [ ] Create Firebase project in Firebase Console
- [ ] Download `google-services.json` to `ssa_app/android/app/`
- [ ] Add Firebase plugins to `android/app/build.gradle`:
  ```groovy
  plugins {
    id 'com.google.gms.google-services'
  }
  ```
- [ ] Initialize Crashlytics in `main.dart`:
  ```dart
  await Firebase.initializeApp();
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterError(details);
    FlutterError.presentError(details);
  };
  ```

#### Additional Test Coverage
- [ ] Service tests: `database_service_test.dart`, `export_service_test.dart`
- [ ] Provider tests: `settings_provider_test.dart`, `session_provider_test.dart`
- [ ] Widget tests: `shot_history_list_test.dart`, `shot_analysis_panel_test.dart`

#### Production Enhancements
- [ ] Offline session queue — queue failed saves for retry when connectivity restored
- [ ] ErrorWidget fallback — global error boundary for widget tree crashes
- [ ] Global exception handler in `main.dart` — catch and report unhandled exceptions

### Test Execution
```bash
flutter test                    # Run all tests
flutter test --coverage         # Run with coverage report
flutter analyze --no-fatal-infos # Check for warnings/errors
```
