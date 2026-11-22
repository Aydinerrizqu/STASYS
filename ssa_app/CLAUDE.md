# STASYS Flutter App - Development Guide

> **Note**: This is the Flutter-specific companion to the root `CLAUDE.md`.
> For firmware architecture, communication protocol details, and firmware build
> instructions, see the parent `CLAUDE.md` at the project root.

## Project Purpose

Mobile companion app for the STASYS shooter stability analyzer. Primary platform for live training sessions.

---

## Architecture

> **Verified 2026-11-22** against the working tree of branch `PreProduction3_Design_Adjust`.

```
ssa_app/
├── lib/
│   ├── main.dart                    # App entry, MultiProvider + GoRouter
│   ├── router/app_router.dart       # GoRouter: /connection + ShellRoute (4 tabs)
│   ├── theme/app_theme.dart         # Context-aware palette (StsysTheme.*Of(context))
│   ├── services/
│   │   ├── database_helper.dart     # SQLite singleton, schema v3, migrations
│   │   ├── database_service.dart    # CRUD, chunked BLOB read, binary BLOB encoding
│   │   ├── export_service.dart      # CSV export via Share Sheet
│   │   ├── stasys_protocol.dart     # greeting + 36-byte XOR frame parser (pure Dart)
│   │   ├── firmware_service.dart    # OTA binary loading + chunking + SHA256
│   │   └── profile_service.dart     # Local name-only profile persistence (SharedPreferences)
│   ├── providers/
│   │   ├── bluetooth_provider.dart  # greeting → streaming, dual-mode parser
│   │   │                             # Binary: 0xAA 0xBB + 6 floats + mag + piezo + battery + XOR
│   │   │                             # + OTA command methods: sendOtaStart, sendOtaChunk,
│   │   │                             #   sendOtaFinish, sendRebootCommand, getFirmwareVersion
│   │   ├── sensor_data_provider.dart # UI state, isolate communication, demo mode
│   │   ├── sensor_data_isolate.dart   # Shot detection + 3-phase analysis (hold/press/recoil)
│   │   │                             # + auto-calibration on first 50 samples (gyro zero-offset)
│   │   ├── settings_provider.dart     # Firearm type, training mode, demo mode, target
│   │   │                             #   distance (5–25m), themeMode, autoUpdateFirmware
│   │   ├── session_provider.dart      # Session list management
│   │   ├── session_logger.dart        # Delegates to DatabaseService (SQLite), series metadata
│   │   ├── train_session_provider.dart# Train state machine, series lifecycle, shot tracking
│   │   ├── profile_provider.dart      # Load/create/select/delete name-only profiles
│   │   └── ota_provider.dart          # OTA state machine: idle→loading→sending→verifying→rebooting
│   ├── models/
│   │   ├── data_models.dart          # DataPoint, SessionLog, ShotResult
│   │   │                             # FirearmType, TrainingMode, MountDirection, MountPosition
│   │   ├── train_preset.dart         # 4 fixed training presets (dry/live × weapon × distance)
│   │   └── profile.dart              # Name-only local profile value object
│   ├── screens/
│   │   ├── connection_screen.dart    # BT scan/connect + Explore App + calibration/mount flow
│   │   ├── main_shell.dart           # Bottom 4-tab shell (Train/History/Tracking/Settings)
│   │   ├── train_screen.dart         # Choices → TRAIN-0 (ready) → TRAIN-1 (active) → review
│   │   ├── tracking_screen.dart      # Dot-only live trace preview (diagnostic view)
│   │   ├── history_screen.dart       # Session list + export CSV + clear all + N-SERIES badge
│   │   ├── settings_screen.dart      # BT scan + theme + weapon + mount/direction + distance
│   │   ├── session_detail_screen.dart# Single-page detail + series chip selector + shot chips
│   │   ├── ota_update_screen.dart    # Full-screen OTA progress UI (route /ota-update)
│   │   └── ota_prompt_dialog.dart    # Modal dialog: version compare + Skip/Update
│   ├── screens/tabs/                 # Legacy 4-tab screens — DEAD (unreachable from main.dart)
│   │   ├── graph_tab.dart            # TRACE (muzzle trace) + POST SHOT (3-phase analysis)
│   │   ├── home_tab.dart             # Dashboard (STSYSStyle)
│   │   ├── connection_tab.dart       # Bluetooth device selection
│   │   ├── settings_tab.dart         # Firearm type, training mode
│   │   └── shot_timer_tab.dart       # Shot timer with countdown & splits
│   └── widgets/
│       ├── muzzle_trace_widget.dart  # MantisX-style live trace
│       ├── shot_trace_geometry.dart  # Shared ordered HOLD→PRESS→RECOIL path
│       ├── shot_replay_controls.dart # Replay scrubber/play controls
│       ├── shot_replay_panel.dart    # Selected-shot replay panel (wraps TargetReplayView)
│       ├── train_target_widget.dart  # ISSF target, trace, scatter, ring contrast
│       ├── target_replay_view.dart   # Target overlay replay
│       ├── calibration_flow.dart     # Mandatory 2-phase calibration/mount dialog
│       ├── shot_analysis_panel.dart  # 3-phase post-shot chart with ring overlay
│       ├── shot_history_list.dart    # Session shot list with tappable cards
│       ├── gyro_realtime_chart.dart  # Real-time gyro chart
│       ├── interactive_chart.dart, control_panel.dart, status_bar.dart
│       └── benchmark_analysis_widget*.dart  # Legacy benchmark widgets (dead)
├── tool/
│   ├── live_files.py                 # Dead-code finder: walks imports from lib/main.dart
│   └── inject_large_session.py       # Builds an oversized session row (CursorWindow test)
└── test/unit/
    ├── models/, providers/, services/, screens/, widgets/, utils/
```

### Removed (2026-11, working tree) — do not look for these

`lib/services/trajectory/` (replay_engine, replay_models, quaternion, projection,
target_geometry), `lib/widgets/analysis/` (analysis_tab, trajectory_canvas,
trajectory_scrubber, phase_summary_card, factor_breakdown_card),
`lib/screens/replay_screen.dart`, `lib/widgets/replay_shot_widget.dart`,
`lib/widgets/replay_trace_painter.dart`.

Replay is now `ShotTraceGeometry` → `TrainTargetWidget` + `ShotReplayControls`.

### Finding dead code

```bash
cd ssa_app && python tool/live_files.py
```
Walks imports from `lib/main.dart` and prints every unreachable `lib/**.dart`.
As of 2026-11-22: **LIVE: 38 / DEAD: 22**. Some "dead" files are still imported by
other dead files, so read the whole list before deleting.

## Navigation Flow (GoRouter)

```
App Launch (initialLocation: '/connection')
  └── ConnectionScreen
        ├── Scan Bluetooth → connect → [firmware check] → calibration/mount flow → /train
        └── Explore App → demo mode → /train (skips calibration)

MainShell (4-tab bottom nav, ShellRoute):
  ├── /train → TrainScreen
  │     ├── Choices view: profile selector + 4 preset cards
  │     ├── TRAIN-0 (readySeries): empty target + START button
  │     ├── TRAIN-1 (activeSeries): target + END SERIES/END SESSION + shot log + replay panel
  │     └── Review (reviewSeries / reviewSession): scatter + shot log + replay + OK
  ├── /history → HistoryScreen
  │     └── Session list + swipe delete + clear all + refresh + N-SERIES badge
  ├── /tracking → TrackingScreen (dot-only diagnostic preview)
  └── /settings → SettingsScreen
        └── BT scan + theme (dark/light) + weapon + mount/direction + target distance
```

There is **no splash screen** in the router any more. `/ota-update` is a
full-screen route outside the ShellRoute.

### Train session state machine

`providers/train_session_provider.dart` →
`TrainSessionState { choices, readySeries, activeSeries, reviewSeries, reviewSession }`.

Android Back is intercepted: `choices` → exit app (confirmation dialog),
`readySeries` → back to choices, `activeSeries` → blocked.

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

> **Updated (2026-10-18)**: Auth-free protocol — mengikuti upstream `dylemmas/STASYS_FW` `5f955e8`.
> SPP tanpa pairing/encryption (`ESP_SPP_SEC_NONE`); **siapa pun di jarak Bluetooth bisa membaca stream**.
> Auth v2 (HMAC + device key, 2026-10-04) sudah di-remove dari app (commit `7bbff1c`).

### Binary Packet Format (36 bytes, XOR checksum)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 2 | sync | `0xAA 0xBB` |
| 2 | 24 | ax..gz | 6 × float32 little-endian (accel m/s², gyro rad/s) |
| 26 | 6 | mag_x/y/z | 3 × int16 raw magnetometer (di-decode, belum dipakai UI) |
| 32 | 2 | piezo | uint16 ADC peak |
| 34 | 1 | battery | uint8 % |
| 35 | 1 | checksum | XOR bytes 2..34 |

**Handshake (tanpa auth)**:
```
ESP32 → App: "READY v=2
"     (satu baris, saat SPP open)
App → ESP32: (tidak mengirim apa pun — firmware mengabaikan data masuk)
ESP32 → App: streaming 36-byte frame @ 100Hz
```

### Code Map (v2 auth-free)
- `lib/services/stasys_protocol.dart` — `parseGreeting('READY v=2')`, `parseFrame` (36B XOR),
  `LineBuffer` (split feed), `FrameAssembler` (sync resync, error counter). Pure Dart, no Flutter deps.
- `lib/providers/bluetooth_provider.dart` — phase `waitingForGreeting → streaming` setelah greeting;
  `requestFullSync()`; frame → `updateAllData(...)`; field `isAuthenticated` kini = "streaming aktif".
- Tidak ada key/DEVICE KEY/provisioning lagi (`device_key_store.dart` + UI section dihapus `7bbff1c`).
- Firmware tak menjawab `GET_VERSION` → `connection_screen._checkFirmwareUpdate` null → skip ke kalibrasi (delay ~3s).

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
- Single scrollable page (2026-11 redesign; the old POST SHOT / ANALYSIS tab
  toggle is gone).
- Horizontal shot chips (tap → chart updates), header stats follow the selection.
- **Series chip selector** — one training session can hold several series
  (`session.seriesNumbers`). The chip strip only appears when there is more than
  one; the default selection is the **last** series, and the header shot count
  and average describe the selected series only.

---

## Shot Replay (replaces the deleted trajectory pipeline)

The offline trajectory-replay pipeline (`services/trajectory/`, `widgets/analysis/`)
was removed in 2026-11. Replay now works like this:

| Piece | Role |
|-------|------|
| `widgets/shot_trace_geometry.dart` | `ShotTraceGeometry.fromShot(shot)` → one ordered HOLD → PRESS → RECOIL path with phase boundaries |
| `widgets/train_target_widget.dart` | Paints the ISSF target, the trace, the scatter of all shots, and the impact marker |
| `widgets/shot_replay_controls.dart` | Scrubber + play/pause; drives `replayProgress` (0.0 → 1.0) |
| `widgets/shot_replay_panel.dart` | Bottom panel that wires the controls to the main target |
| `widgets/target_replay_view.dart` | Standalone target-overlay replay of one shot |

**One geometry, two consumers.** The static post-shot chart and the moving
replay draw the *same* path, so the trace and the impact marker always line up.
The impact marker is the trace endpoint — `markerPositions` is shared between the
live drawing and the scatter drawing.

`ShotTracePath.maxDeviation` scales the target to the shot's own deviation
(`maxDeviation * 1.3`, clamped to ≥ 0.01).

### Train target rendering
- ISSF standard target: 10 rings, black bull `r = maxR * 0.4`, dashed crosshair,
  ring numbers 1–10 (outer → inner) drawn with a cached `TextPainter`.
- `maxR = shortestSide * 0.40`.
- Ring strokes are **theme-dependent**: light strokes on the dark shell, dark
  strokes on the light shell. The full-bleed band behind the target follows the
  theme too — a fixed near-white band hid the rings in dark mode.
- Dry vs live training mode paints a different target treatment.

---

## Settings Persistence

- **SharedPreferences** for app settings only
- **SQLite** for session/shots persistence (stasys_sessions.db)
- **Key strings**: `firearmType`, `trainingMode`, `maxSamples`, `mountDirection`, `mountPosition`, `themeMode`
- **`maxSamples` clamp**: Di-load dengan `.clamp(2, 10)` di `SettingsProvider._loadSettings`. Nilai corrupt (misal 15 dari slider lama) auto-di-fix dan di-overwrite ke SharedPreferences.

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

## Theme — context-aware, cyan + light/dark

`theme/app_theme.dart` exposes `StsysTheme.*Of(context)` accessors that resolve
per brightness. The palette is **not** the old warm-orange dark-only theme.

| Token | Value | Accessor |
|-------|-------|----------|
| primary | `#00E5FF` cyan | `primaryOf(context)` |
| secondary | `#4D7CFE` | `secondaryOf(context)` |
| error | `#FF6B6B` | `errorOf(context)` |
| surface | `#0C0E11` (dark) / near-white (light) | `surfaceContainerLowOf(context)` etc. |
| onSurface | `#F1F5F9` (dark) / `#17202A` (light) | `onSurfaceOf(context)` |

**Rules**
- Never hard-code a colour in a widget — always use the `...Of(context)` accessor.
  Commit `5832434` migrated 16 screens/widgets out of hard-coded `Color(0xFF…)`
  literals; new code must follow the same rule.
- `CustomPainter` has no `BuildContext` — the caller resolves the colour and
  passes it into the painter, which applies it inside `paint()`.
- `onGradientOf(context)` is fixed (`#00252C`): it sits on top of the brand and
  tactical gradients, which do not change with brightness. A white label would
  vanish on the cyan half of the brand gradient.
- Score colours live in `StsysTheme.getScoreColor(score)` — do not re-implement
  the threshold ladder locally (`session_detail_screen.dart` and
  `graph_tab.dart` both delegate to it).
- Dark/light is user-selectable: Settings → Theme, stored in SharedPreferences
  under key `themeMode` (`SettingsProvider.setThemeMode`).
- The OTA screens were hard-wired to the dark palette before `5832434`; they now
  follow the theme too.

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
crypto: ^3.0.3                        # SHA256 auth + OTA checksum
intl: ^0.19.0                         # Formatting
go_router: ^15.1.0                    # Navigation routing
mime: ^2.0.0                          # MIME type for export
```

**Assets:**
```yaml
flutter:
  assets:
    - assets/firmware/stasys_fw.bin  # OTA firmware binary (update on each release)
```

---

## OTA Firmware Update (Bluetooth Classic) — ✅ WORKING (2026-05-23)

### Architecture

```
Flutter App                    ESP32 Firmware
    │                               │
    │ GET_VERSION ──────────────►   │
    │ ◄──────────── VERSION=X.Y.Z   │
    │                               │
    │ Compare: device vs APK        │
    │                               │
    │ OTA_START:size=1728512 ──►   │
    │ ◄──────────── OTA_READY       │
    │                               │
    │ (128-byte chunks × 13473)     │
    │ OTA_DATA:seq=0:base64=... ─► │
    │ ◄──────────── OTA_ACK:seq=0   │
    │ ...repeat...                  │
    │                               │
    │ OTA_FINISH:sha256=... ─────► │
    │ (ESP32 verifies SHA256)       │
    │ ◄──────────── OTA_COMPLETE   │
    │                               │
    │ REBOOT ──────────────────────►│ esp_restart()
    │                               │
    └─ ESP32 boots new firmware ────┘
```

### Key Files

| File | Role |
|------|------|
| `services/firmware_service.dart` | Load `.bin` from assets, compute SHA256, chunk into 128-byte pieces |
| `providers/ota_provider.dart` | State machine: idle→loading→sending→verifying→rebooting→completed/failed. 3 retries per chunk, 200ms delay between chunks |
| `providers/bluetooth_provider.dart` | Dedicated `_otaMode` phase, `_otaTextBuffer` (no 2048 trim), `sendOtaStart()`, `sendOtaChunk()`, `sendOtaFinish()`, `getFirmwareVersion()` |
| `screens/ota_update_screen.dart` | Full-screen progress UI (circular %, step indicators) |
| `screens/ota_prompt_dialog.dart` | Modal dialog: version compare + Skip/Update buttons |
| `screens/connection_screen.dart` | After auth, calls `_checkFirmwareUpdate()` → shows dialog or navigates to `/tracking` |
| `router/app_router.dart` | Route `/ota-update` (full-screen, outside ShellRoute) |
| `assets/firmware/stasys_fw.bin` | Bundled firmware binary (updated on each release) |
| `pubspec.yaml` | Declares `assets/firmware/stasys_fw.bin` |

### State Machine (OtaProvider)

```
OtaState.idle → loading → sending → verifying → rebooting → completed
                ↓                    ↓                      ↓
             failed (on error)   failed (OTA_FINISH fail)  failed
```

### Version Logic

- ESP32 firmware version: compile-time `FIRMWARE_VERSION` macro — now in
  `Firmware_STASYS32/src/main.cpp:22` (`"2.0.0"`), **not** `storage.h` any more.
- APK assets version: `firmware_service.dart` → `expectedVersion = '1.4.0'` (update on release).
- Dialog appears when `currentFw != newFw.version`.

> ⚠️ **The auth-free v2 firmware does not answer `GET_VERSION`.**
> `connection_screen._checkFirmwareUpdate` therefore gets `null` and skips the
> dialog — but only after waiting out the ~3 s timeout. The version mismatch
> (`1.4.0` vs `2.0.0`) is inert until `GET_VERSION` is reimplemented on the
> firmware side.

### OTA state on the firmware side (2026-11)

`Firmware_STASYS32/src/ota/*` is **dead code** — it is not listed in
`src/CMakeLists.txt` SRCS, so it is never compiled. Its `extern isAuthenticated`
guard is stale (that symbol no longer exists) and would fail to link if it were
re-enabled. Replace the guard with `g_state != BT_OTA_IDLE` before reviving OTA.

### Implementation Details (2026-05-23)

**Flutter side**:
- `_connectionPhase = _ConnectionPhase.otaMode` — dedicated OTA parsing, no binary collision
- `_otaTextBuffer = ''` cleared BEFORE switching phase (prevents RangeError)
- `_waitForOtaResponse()` uses `_otaTextBuffer` in OTA mode (unlimited, no 2048 trim)
- 200ms delay between chunks (prevents ESP32 BT RX buffer overflow)
- 3 retries per chunk, 5000ms timeout per response

**ESP32 side**:
- Dual-task FreeRTOS: drain task (priority 2, Core 0) + write task (priority 1, Core 0)
- Drain task: reads SerialBT, parses text commands, sends ACKs. `taskYIELD()` after every byte prevents buffer overflow.
- Write task: receives chunks from queue, calls `esp_ota_write()` (~500ms blocking), updates SHA256
- Binary semaphore: write task signals drain task when chunk is done
- Queue size: 4 entries (128 bytes each = 512 bytes total)
- `btOtaReset()` called on disconnect, auth fail, or OTA_ABORT

**Speed**: ~13,500 chunks @ 200ms delay + esp_ota_write ~500ms per chunk = ~45 minutes for 1.7MB. See pending optimization below.

### Auto-Update Toggle

`settings_screen.dart` has switch for "Auto-update firmware" → stored in SharedPreferences as `autoUpdateFirmware` (bool, default false).

### Build Process for Release

1. Update `Firmware_STASYS32/src/main.cpp` → `#define FIRMWARE_VERSION "X.Y.Z"` (line 22)
2. Build firmware: `cd Firmware_STASYS32 && python -m platformio run -e esp32dev`
3. Copy binary: `cp .pio/build/esp32dev/firmware.bin ../ssa_app/assets/firmware/stasys_fw.bin`
4. Update `firmware_service.dart` → `expectedVersion = 'X.Y.Z'`
5. Build APK: `cd ssa_app && flutter build apk --debug`

---

## Active Branches

| Branch | Status | Description |
|--------|---------|-------------|
| `PreProduction3_Design_Adjust` | **Active** | 6 commits ahead of `main` (`5832434`): session-series grouping, single-page session detail, chunked BLOB reads, context-aware theme migration. Working tree has the trajectory-pipeline removal (uncommitted). |
| `PreProduction3` | Staged | STASYS_FW + live tracking, pre-series-grouping session model |
| `feature/figma-train-redesign` | Merged into `main` | Figma train-flow redesign worktree |
| `migrasi_firmware_awal_v1` | Backup | Previous version with XOR checksum (30-byte packets) |
| `migrasi_firmware_awal` | Backup | Snapshot of earlier version |
| `backup-dark-theme-redesign` | Backup | Full backup of all uncommitted changes pushed to remote |
| `develop` | Staged | Dark theme elements pending merge |
| `main` | Base | `61799f9` — auth-free protocol adoption + CLAUDE.md update |

`main` is also checked out in the worktree `.worktrees/figma-train-redesign`.

---

## Known Issues / TODOs

### Pending
- [ ] **OTA Speed Optimization** — Current: 45 min for 1.7MB. Target: 10-15 min. Approaches: larger chunks (256 bytes), burst mode (batched ACKs), reduced delay. Needs incremental testing (test each chunk size change).
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
- [ ] **MantisX feature parity** — drill modes, trend analysis, split time, session notes, etc.
- [ ] **Frame freeze / gralloc4 GPU failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.
- [ ] **Supabase cloud sync** — design spec only (`docs/superpowers/specs/2026-11-01-supabase-cloud-sync-design.md`). Not implemented.
- [ ] **Dead-code cleanup** — 22 unreachable Flutter files, listed by `python tool/live_files.py`.
- [ ] **Hardware acceptance of the auth-free protocol** — flash firmware → reboot → connect → immediate stream, no key. The current 36-byte/XOR firmware has never been flashed to hardware.

### Completed (2026-08-23) ✅
- [x] **Post-shot/replay trace synchronization** — `ShotTraceGeometry` provides one ordered HOLD → PRESS → RECOIL path, shared by the static `_ThreePhasePainter` and `ReplayShotWidget` playback. Playback draws the same colored segments progressively under the moving dot. Added geometry and Session Detail layout regression tests. Commit: `d303935`.

### Completed (2026-06-21) — superseded 2026-11
- [x] **Trajectory Refactor Phase 1: Module Extraction** — `quaternion.dart`, `barrel_projection.dart`. **Deleted 2026-11.**
- [x] **Trajectory Refactor Phase 2: Replay Engine** — `replay_engine.dart`: offline `SessionLog` → `ReplayTrace`. **Deleted 2026-11.**
- [x] **Trajectory Refactor Phase 3: AnalysisTab** — POST SHOT / ANALYSIS toggle. **Deleted 2026-11.**
- [x] **Target Distance Settings** — `targetDistanceM` (5–25m, default 10m) in `SettingsProvider` + slider in `settings_screen.dart` under "TARGET DISTANCE" section. Still current.

### Completed (2026-05-23) ✅
- [x] **OTA Bluetooth Firmware Update** — ✅ WORKING! Full E2E implementation complete. See detailed implementation above. Tested E2E with 1.7MB firmware, ~45 min transfer time.

### Settings (Implemented 2026-05-09)
- [x] Mount position selector (TOP/BOT/LEFT/RIGHT) — `settings_tab.dart`, persisted via SharedPreferences
- [x] Mount direction FW/BW toggle — `_MiniToggle` bound to `SettingsProvider`, passed to isolate via `update_settings`
- [x] RESET AXIS button — triggers `SensorDataProvider.resetAxis()` → isolate `reset_axis` message → clears offsets, re-runs 50-sample auto-calibration

### Dead Code (Pending Cleanup)

Regenerate the list with `python tool/live_files.py` (from `ssa_app/`) rather than
trusting this snapshot — it was taken 2026-11-22 and reports **LIVE: 38 / DEAD: 22**:
- `services/sensor_data_stream.dart` — fully commented out, unused
- `providers/bluetooth_isolate.dart` — old 28-byte protocol implementation
- `screens/main_screen.dart` — old 4-tab navigation (replaced by `main_shell.dart`)
- `screens/splash_screen.dart` — splash removed from the router
- `screens/tabs/*` — graph, home, connection, settings, shot_timer
- `screens/tracking_mode_view.dart`
- `widgets/control_panel.dart`, `widgets/gyro_realtime_chart.dart`,
  `widgets/shot_analysis_panel.dart`, `widgets/shot_history_list.dart`,
  `widgets/status_bar.dart`, `widgets/interactive_chart.dart`
- `widgets/benchmark_analysis_widget*.dart` — 3 versions of the benchmark widget
- `utils/data_processor.dart`, `utils/debug_helper.dart`, `utils/debug_overlay.dart`

> Some of these are still imported by other dead files, so the reachability graph
> has to be read as a whole before deleting anything.

---

## Progress 2026-11-01 → 2026-11-22 — Session Grouping, Detail Redesign, Theme Migration ✅

Branch `PreProduction3_Design_Adjust`, 6 commits ahead of `main`.
Verified 2026-11-22: **Flutter 209/209 tests pass · `flutter analyze --no-fatal-infos`
clean · firmware 39/39 Python tests pass.**

- [x] **`97820ae`** — design spec: Supabase cloud sync + developer panel.
  Offline-first (local SQLite stays the source of truth, sync is additive),
  optional Google/Email login, per-session upload, offline queue via a
  `sync_status` column, developer panel = Supabase Studio + three SQL views.
- [x] **`4ff4ec0`** — design spec: session-series grouping.
- [x] **`80fd819`** — single-page session detail + safe loading of large session rows.
  History queries omit the IMU BLOBs; raw data is read per series in 256 KB
  chunks to stay under Android's ~2 MB CursorWindow limit.
  Adds `database_row_size_test.dart` and `tool/inject_large_session.py`.
- [x] **`fb759a2`** — session-series grouping implemented (schema v2 → v3).
  New `session_series` table; `shots.series_number` now holds the real series
  number, so one training session stays one card in History. History cards show
  an "N SERIES" badge; the default series is the last one; the session detail
  and replay get a series chip selector whose stats follow the selection.
  The raw buffer is cleared when a new series starts, so a finished series'
  raw data cannot leak into the next one. Session ids carry a monotonic counter
  so two sessions started in the same clock tick cannot overwrite each other.
- [x] **`5832434`** — theme migration (see the Theme section above).

### Working-tree changes (uncommitted as of 2026-11-22)

Removes the trajectory-replay pipeline and consolidates the UI:
`lib/services/trajectory/*`, `lib/widgets/analysis/*`, `lib/widgets/analysis_tab.dart`,
`lib/screens/replay_screen.dart`, `lib/widgets/replay_shot_widget.dart`,
`lib/widgets/replay_trace_painter.dart` — **−4026 lines net**.
Also: `print` → `debugPrint`, `withOpacity` → `withValues(alpha:)`,
unused fields/parameters removed, `_StasysHeader` simplified (the shell now
renders its own header).

**These changes are not committed — check `git status --short` before committing
anything else so they are not lost.**

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
[BT] Connected to <device name>
[BT] Greeting received: READY v=2
[BT] Streaming started
```
The auth log lines (`CMD_AUTH`, `Auth successful`, `CMD_START_SESSION`) were
removed with the auth-free protocol — see Progress 2026-10-18.
Use `debugPrint`, not `print` (the working tree migrated the OTA and BT logs).

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

### Quick Wins (2026-05-09) ✅
- [x] Fix duplicate `@override` in `sensor_data_provider.dart:512`
- [x] Implement Mount Direction FW/BW toggle (enum + SettingsProvider + isolate + UI)
- [x] Implement RESET AXIS button (SensorDataProvider → isolate → clear offsets + re-cal)
- [x] Implement Mount Mode selector (4-position grid with active state)
- [x] Fix maxSamples slider range di settings_tab.dart (min: 3→2, max: 15→10, divisions: 4→8)
- [x] Fix slider labels di settings_tab.dart ('3s'→'2s', '15s'→'10s')
- [x] Tambah clamp di SettingsProvider._loadSettings untuk auto-fix corrupt values (15→10)

#### Firebase Crashlytics Setup (Pending)
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
