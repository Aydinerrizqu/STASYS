# STASYS - Shooter Stability Analysis System

> **Note**: For Flutter app development, see `ssa_app/CLAUDE.md`.
> For firmware development, see `Firmware_STASYS32/CLAUDE.md`.
> That file covers PlatformIO build, module architecture, FreeRTOS tasks, and hardware pinout.

---

## Coding Behavioral Guidelines

These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

---

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: ESP32 + MPU6050 + Piezo sensor, Bluetooth Classic
- **Python Legacy**: `_python_legacy/` - Old Python desktop apps (XOR/30-byte protocol, archived 2026-06-13)
- **Flutter App**: `ssa_app/` - Mobile companion (Android/iOS) — **PRIMARY DEVELOPMENT TARGET**
- **Firmware**: `Firmware_STASYS32/` - Modular PlatformIO ESP32 firmware (STASYS_FW)

**Goal**: Open-source alternative to MantisX for dry/live fire training with shot scoring, muzzle trace visualization, and session analysis.

---

## Architecture

> **Verified 2026-11-22** against the working tree of branch `PreProduction3_Design_Adjust`.
> File paths below are the real ones — earlier revisions of this file listed files
> that have since been deleted (see "Removed Subsystems" at the bottom).

```
d:\Aydiner\Projek Flutter SSA\
├── ssa_app/                         # Flutter mobile app (PRIMARY)
│   └── lib/
│       ├── main.dart                    # App entry, MultiProvider + GoRouter
│       ├── router/app_router.dart       # GoRouter: /connection + ShellRoute (4 tabs)
│       ├── theme/app_theme.dart         # Context-aware palette (StsysTheme.*Of(context))
│       ├── services/
│       │   ├── database_helper.dart    # SQLite singleton, schema v3, migrations
│       │   ├── database_service.dart   # CRUD, chunked BLOB read, binary BLOB encoding
│       │   ├── export_service.dart     # CSV export via Share Sheet (all sessions)
│       │   ├── stasys_protocol.dart    # greeting + 36-byte XOR frame parser (pure Dart)
│       │   ├── firmware_service.dart   # OTA binary loading + chunking + SHA256
│       │   └── profile_service.dart    # Local name-only profiles (SharedPreferences)
│       ├── providers/
│       │   ├── bluetooth_provider.dart  # greeting → streaming, dual-mode parser
│       │   ├── sensor_data_provider.dart # UI state, isolate communication, demo mode
│       │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis
│       │   ├── settings_provider.dart    # + themeMode, isDemoMode, target distance
│       │   ├── session_provider.dart     # Session list management
│       │   ├── session_logger.dart       # Delegates to DatabaseService (SQLite)
│       │   ├── train_session_provider.dart # Train state machine, series lifecycle
│       │   ├── profile_provider.dart     # Local profile CRUD
│       │   └── ota_provider.dart         # OTA state machine
│       ├── models/
│       │   ├── data_models.dart          # DataPoint, SessionLog, ShotResult, enums
│       │   ├── train_preset.dart         # 4 fixed training presets
│       │   └── profile.dart              # Name-only local profile
│       ├── screens/
│       │   ├── connection_screen.dart    # BT scan/connect + calibration/mount flow
│       │   ├── main_shell.dart           # 4-tab NavigationBar shell (Train/History/Tracking/Settings)
│       │   ├── train_screen.dart         # Choices → TRAIN-0 ready → TRAIN-1 active → review
│       │   ├── tracking_screen.dart      # Dot-only live trace preview
│       │   ├── history_screen.dart       # Session list + export + clear all + N-SERIES badge
│       │   ├── settings_screen.dart      # BT scan + theme + mount + target distance
│       │   ├── session_detail_screen.dart # Single-page detail + series chip selector
│       │   ├── ota_update_screen.dart    # Full-screen OTA progress UI
│       │   └── ota_prompt_dialog.dart    # Version compare + Skip/Update
│       └── widgets/
│           ├── muzzle_trace_widget.dart  # MantisX-style live trace
│           ├── shot_trace_geometry.dart  # Shared HOLD→PRESS→RECOIL path (chart + replay)
│           ├── shot_replay_controls.dart # Replay scrubber/play controls
│           ├── shot_replay_panel.dart    # Selected-shot replay panel
│           ├── train_target_widget.dart  # ISSF target, trace, scatter, ring contrast
│           ├── target_replay_view.dart   # Target overlay replay
│           ├── calibration_flow.dart     # Mandatory calibration/mount dialog
│           ├── shot_analysis_panel.dart  # 3-phase post-shot chart
│           ├── shot_history_list.dart    # Session shot list
│           ├── gyro_realtime_chart.dart  # Real-time gyro chart
│           ├── control_panel.dart, status_bar.dart, interactive_chart.dart
│           └── benchmark_analysis_widget*.dart  # Legacy benchmark widgets (dead)
│
├── Firmware_STASYS32/                 # ESP-IDF ESP32 firmware (STASYS_FW)
│   ├── src/main.cpp                  # app_main, 2 FreeRTOS tasks, SPP + streaming
│   ├── src/ota/                      # BT OTA handler (DEAD CODE — not in CMakeLists)
│   ├── components/
│   │   ├── app_protocol/             # 36-byte packet serializer (XOR checksum)
│   │   ├── sensors/                  # sensor_hal: MPU6050 + QMC5883L + HMC5883L + ADC
│   │   └── system_config/            # Pinout + HAL handles
│   ├── partitions_dual_ota.csv
│   └── platformio.ini                # espressif32@6.12.0, framework = espidf
│
├── docs/superpowers/{specs,plans}/   # Design specs + implementation plans (gitignored
│                                     #   — already-tracked files stay tracked)
├── _python_legacy/                   # Old Python desktop apps (archived 2026-06-13)
└── tools/                            # stasys_packet.py firmware-side reference
```

### Removed Subsystems (do not look for these)

| Deleted | When | Replacement |
|---------|------|-------------|
| `lib/services/trajectory/` (replay_engine, quaternion, projection, target_geometry, replay_models) | 2026-11 (working tree) | — |
| `lib/widgets/analysis/` (analysis_tab, trajectory_canvas, trajectory_scrubber, phase_summary_card, factor_breakdown_card) | 2026-11 (working tree) | `widgets/train_target_widget.dart` + `widgets/shot_trace_geometry.dart` |
| `lib/screens/replay_screen.dart`, `lib/widgets/replay_shot_widget.dart`, `lib/widgets/replay_trace_painter.dart` | 2026-11 (working tree) | Single-page `session_detail_screen.dart` + `shot_replay_controls.dart` |

> The offline trajectory-replay pipeline documented in earlier revisions of this file
> no longer exists. Shot replay now goes through `ShotTraceGeometry` → `TrainTargetWidget`.

### Unreachable (dead) Flutter files — `ssa_app/tool/live_files.py`

`python tool/live_files.py` (run from `ssa_app/`) walks imports from `lib/main.dart`
and lists every `lib/**.dart` file that is unreachable. As of 2026-11-22 it reports
**LIVE: 38 / DEAD: 22**, including `screens/main_screen.dart`, `screens/splash_screen.dart`,
`screens/tabs/*`, `widgets/control_panel.dart`, `widgets/gyro_realtime_chart.dart`,
`widgets/shot_analysis_panel.dart`, `widgets/shot_history_list.dart`,
`widgets/status_bar.dart`, `utils/*`, `providers/bluetooth_isolate.dart`,
`services/sensor_data_stream.dart`, `widgets/benchmark_analysis_widget*.dart`.
Run it before deleting anything — some "dead" files are still imported by other dead files.

---

## Communication Protocol

> **Updated (2026-10-18)**: Protokol auth-free mengikuti upstream `dylemmas/STASYS_FW` commit `5f955e8`.
> Tidak ada auth/encryption — SPP `ESP_SPP_SEC_NONE`, greeting tunggal, langsung streaming.
> **Keamanan**: siapa pun dalam jarak Bluetooth bisa connect dan membaca stream (keputusan sadar, lihat Progress 2026-10-18).

### Binary Packet Format (36 bytes, XOR checksum)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0xBB` |
| 2 | 4 | ax | float m/s² (little-endian) |
| 6 | 4 | ay | float m/s² |
| 10 | 4 | az | float m/s² |
| 14 | 4 | gx | float rad/s |
| 18 | 4 | gy | float rad/s |
| 22 | 4 | gz | float rad/s |
| 26 | 2 | mag_x | int16 raw magnetometer |
| 28 | 2 | mag_y | int16 raw |
| 30 | 2 | mag_z | int16 raw |
| 32 | 2 | piezo | uint16 ADC peak |
| 34 | 1 | battery | uint8 % |
| 35 | 1 | checksum | XOR over bytes 2..34 |

**Handshake (tanpa auth)**:
```
ESP32 → App: "READY v=2
"   (saat SPP open)
App → ESP32: (tidak perlu mengirim apa pun)
ESP32 → App: streams 36-byte binary packets @ 100Hz
```
Tidak ada key, provisioning, atau PROOF. Lihat `tools/stasys_packet.py` (firma) dan
`ssa_app/lib/services/stasys_protocol.dart` (app) sebagai referensi wire format.

---

## Database Schema (SQLite — stasys_sessions.db)

> **Implemented**: 2026-04-14 — migrated from SharedPreferences (JSON) to SQLite.
> **Schema version 3** (`openDatabase(version: 3)` in `services/database_helper.dart`).
> Storage location: `getDatabasesPath() + '/stasys_sessions.db'` (Android internal storage).
> `onUpgrade` is additive and non-destructive: v1→v2 adds metadata columns,
> v2→v3 creates `session_series` and copies legacy raw BLOBs into series 1.

### Table: `sessions` (one row per training session)
```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,             -- SESSION_<micros>_<counter>, see below
  date INTEGER NOT NULL,           -- Unix timestamp (ms)
  duration REAL NOT NULL,          -- seconds
  firearm_type TEXT NOT NULL,
  training_mode TEXT NOT NULL,
  profile_name TEXT NOT NULL DEFAULT '',
  training_preset TEXT NOT NULL DEFAULT '',
  series_count INTEGER NOT NULL DEFAULT 0,
  gyro_x BLOB,                     -- legacy raw (kept for pre-v3 sessions)
  gyro_y BLOB, gyro_z BLOB,
  accel_x BLOB, accel_y BLOB, accel_z BLOB
);
CREATE INDEX idx_sessions_date ON sessions(date DESC);
CREATE INDEX idx_sessions_firearm ON sessions(firearm_type);
```

### Table: `session_series` (v3 — raw IMU per series)
```sql
CREATE TABLE session_series (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  series_number INTEGER NOT NULL,
  duration REAL NOT NULL DEFAULT 0,
  gyro_x BLOB, gyro_y BLOB, gyro_z BLOB,
  accel_x BLOB, accel_y BLOB, accel_z BLOB,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  UNIQUE (session_id, series_number)   -- required, else INSERT OR REPLACE never replaces
);
CREATE INDEX idx_session_series ON session_series(session_id, series_number);
```

### Table: `shots`
```sql
CREATE TABLE shots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,       -- FK → sessions.id (ON DELETE CASCADE)
  timestamp INTEGER NOT NULL,     -- Unix timestamp (ms)
  total_score REAL NOT NULL,
  hold_score REAL NOT NULL,
  press_score REAL NOT NULL,
  recoil_score REAL NOT NULL,
  elevation_score REAL NOT NULL,
  windage_score REAL NOT NULL,
  travel_distance REAL NOT NULL,
  peak_jerk REAL NOT NULL,
  firearm_type TEXT NOT NULL,
  training_mode TEXT NOT NULL,
  series_number INTEGER NOT NULL DEFAULT 1,  -- v2: which series the shot belongs to
  hold_x BLOB,                    -- Binary encoded phase traces
  hold_y BLOB,
  press_x BLOB,
  press_y BLOB,
  recoil_x BLOB,
  recoil_y BLOB
);
CREATE INDEX idx_shots_session ON shots(session_id);
CREATE INDEX idx_shots_score ON shots(total_score DESC);
```

### Binary BLOB Encoding

**Time series** (gyro/accel per series): `pointCount(int32)` + `[relTimestamp(float32) + value(float32)] * N`
**Phase traces** (per shot): `count(int32)` + `[value(float64)] * N`

Benefits: ~40% more compact than JSON, 5x faster decode, no JSON parsing overhead.

### Android CursorWindow limit — read BLOBs in chunks

A session row with 60k samples/axis is ~2.8 MB, which exceeds Android's ~2 MB
SQLite CursorWindow and makes `db.query()` throw. Therefore:
- `getSession()` / history queries select **summary columns only** (no IMU BLOBs).
- Raw data is read per series via `getSeriesRaw(sessionId)` → `_readSeriesBlobColumn()`
  → `SELECT substr(col, ?, ?)` in **256 KB chunks** (`_blobChunkBytes`).
- `ssa_app/tool/inject_large_session.py` builds a deliberately oversized row to
  regression-test this (`test/unit/services/database_row_size_test.dart`).

### Session ID uniqueness

`train_session_provider.dart` builds `SESSION_<microsSinceEpoch>_<counter>` with a
monotonic `_sessionCounter`. Two sessions started in the same clock tick would
otherwise share an id and overwrite each other.

---

## Development Workflow

### Building & Uploading Firmware (PlatformIO + ESP-IDF)
```bash
# Find ESP32 COM port first
powershell -Command "[System.IO.Ports.SerialPort]::GetPortNames()"

# Build (framework = espidf, espressif32@6.12.0)
cd Firmware_STASYS32
python -m platformio run -e esp32dev

# Upload (COM3 detected 2026-05-23)
python -m platformio run -e esp32dev --target upload --upload-port COM3

# Monitor serial
python -m platformio device monitor --port COM3 --baud 115200
```

> ⚠️ **ESP-IDF rejects build paths containing spaces.** The repo lives in
> `d:\Aydiner\Projek Flutter SSA\` — build from a copy in a space-free path.
> `IDF_PATH` is normally unset in the shell; PlatformIO supplies its own
> `framework-espidf` package, but the IDF CMake tools still need a space-free cwd.

### Firmware tests (Python — no pytest installed)
```bash
cd Firmware_STASYS32
python test/test_protocol_contract.py   # 5 tests
python test/test_sens_log.py            # 13 tests
python test/test_stasys_packet.py       # 8 tests
python test/test_validate_partitions.py # 13 tests
```
`pytest` is **not** installed on this machine — run each file directly (each is a
`unittest` module with a `__main__` block).

### Testing Flutter App
```bash
cd ssa_app
flutter test                     # 209 tests (2026-11-22, all pass)
flutter analyze --no-fatal-infos # "No issues found!" (2026-11-22)
flutter build apk --debug
# Install APK from build/app/outputs/flutter-apk/app-debug.apk
```

> **Toolchain**: Flutter 3.35.1 stable · Dart SDK `^3.9.0` · `flutter_lints: ^6.0.0`.
> **Test gotchas**: `flutter test` runs files in parallel and two files opening the
> same SQLite file lock each other out — `DatabaseHelper.setDatabaseFileNameForTesting()`
> points each test at a unique file name. In Git Bash, `tail` on the compact reporter
> output is unreliable (CR rendering); check the exit code instead.

---

## Dependencies

### Flutter
```
flutter_bluetooth_serial: ^0.4.0  # Bluetooth Classic
syncfusion_flutter_charts: ^30.2.7
fl_chart: ^1.0.0
provider: ^6.1.2
shared_preferences: ^2.2.2        # App settings only
sqflite: ^2.3.2                   # Session/shots persistence (SQLite)
path: ^1.9.0                      # Path utilities for DB
share_plus: ^10.0.0               # CSV export via Share Sheet
permission_handler: ^12.0.1
path_provider: ^2.1.1
crypto: ^3.0.3                    # SHA256 (OTA checksum)
intl: ^0.19.0
go_router: ^15.1.0
mime: ^2.0.0
```
Dev: `mocktail ^1.0.3`, `coverage ^1.7.2`, `sqflite_common_ffi ^2.3.4+4`,
`firebase_crashlytics ^4.0.0`, `firebase_core ^3.0.0` (setup pending).

### ESP32 / PlatformIO
```
platform = espressif32@6.12.0
framework = espidf                     # NOT arduino — see Firmware_STASYS32/CLAUDE.md
board_build.partitions = partitions_dual_ota.csv
components: bt, nvs_flash, driver, esp_adc, esp_http_client
```

### Release Build Note (2026-04-26)
`flutter_bluetooth_serial ^0.4.0` has a dependency on `androidx.appcompat:appcompat:1.3.0` which uses `android:attr/lStar` (Android 12+ API). This causes AAPT error on release builds with AGP 8.9+.

**Fix**: Patch the pub cache copy before building:
```
# flutter_bluetooth_serial-0.4.0/android/build.gradle:
compileSdkVersion 30  → 34
buildToolsVersion '30.0.3'  → '34.0.0'
implementation 'androidx.appcompat:appcompat:1.3.0'  → 1.7.0
```
Path: `C:/Users/<USER>/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_bluetooth_serial-0.4.0/android/build.gradle`
⚠️ `flutter pub cache repair` will revert this — re-patch after repair.

---

## Theme & Navigation (2026-11)

### Theme — context-aware, cyan + light/dark

The palette is **no longer** the warm-orange dark-only theme. `theme/app_theme.dart`
now exposes `StsysTheme.*Of(context)` accessors that resolve per brightness.

| Token | Dark | Light |
|-------|------|-------|
| `primary` | `#00E5FF` (cyan) | same accent family |
| `secondary` | `#4D7CFE` | — |
| `error` | `#FF6B6B` | — |
| `surface` | `#0C0E11` | near-white shell |
| `onSurface` | `#F1F5F9` | `#17202A` |

- **Never hard-code a colour in a widget.** Use `StsysTheme.primaryOf(context)`,
  `surfaceContainerLowOf(context)`, `onGradientOf(context)`, etc. Hard-coded
  `Color(0xFF…)` literals were migrated out in commit `5832434`; new code must
  follow the same rule.
- `CustomPainter` has no `BuildContext` — the caller passes the colour in and
  the painter applies it inside `paint()`.
- `onGradientOf(context)` is fixed (`#00252C`) because it sits on top of the
  fixed brand/tactical gradients, which do not change with brightness.
- Dark/light is user-selectable in Settings (`themeMode` in SharedPreferences,
  `SettingsProvider.setThemeMode`).
- Score colours live in `StsysTheme.getScoreColor(score)` — do not re-implement
  the threshold ladder locally.

### Navigation — 4 tabs, no splash

```
App Launch → /connection (ConnectionScreen)
              ├── Scan BT → connect → firmware check → calibration/mount flow → /train
              └── Explore App → demo mode → /train

MainShell (ShellRoute, 4 tabs): /train, /history, /tracking, /settings
```
There is **no splash screen** in the router any more (`initialLocation: '/connection'`).

---

## Progress 2026-11-01 → 2026-11-22 — Session Grouping, Detail Redesign, Theme Migration ✅

Branch `PreProduction3_Design_Adjust` (ahead of `main` = `61799f9` by 6 commits).
Verified 2026-11-22: **Flutter 209/209 tests pass · `flutter analyze` clean ·
firmware 39/39 Python tests pass.**

- [x] **`97820ae`** — design spec: Supabase cloud sync + developer panel.
  Offline-first (local SQLite stays source of truth, sync is additive),
  optional Google/Email login, per-session upload, offline queue via a
  `sync_status` column, developer panel = Supabase Studio + three SQL views.
  **Spec only — no implementation yet.**
- [x] **`4ff4ec0`** — design spec: session-series grouping (one History card per
  training session, series chips in detail, `shots.series_number` populated).
- [x] **`80fd819`** — single-page session detail + safe loading of large rows.
  History queries omit the IMU BLOBs; raw data is read per series in 256 KB
  chunks to stay under Android's ~2 MB CursorWindow limit.
  Adds `database_row_size_test.dart` + `tool/inject_large_session.py`.
- [x] **`fb759a2`** — session-series grouping implemented. New `session_series`
  table (schema v2→v3, non-destructive migration copies legacy raw into series 1).
  `UPDATE`-then-`INSERT` instead of `INSERT OR REPLACE` (REPLACE would cascade-delete
  the session's own shots); `UNIQUE(session_id, series_number)` is required for
  `INSERT OR REPLACE` to replace. Session ids carry a monotonic counter so two
  sessions in the same clock tick don't overwrite each other.
- [x] **`5832434`** — theme migration: 16 screens/widgets moved to the
  context-aware `StsysTheme.*Of(context)` accessors; the two OTA screens were
  hard-wired to the dark palette and now follow the theme. CustomPainter colours
  are passed in by the caller. Also fixes a 4.5 px overflow of the "N SERIES"
  badge in History (wrapped in a `FittedBox`).

### Working-tree changes (2026-11, not yet committed)

Removes the offline trajectory-replay pipeline and consolidates the UI:
`lib/services/trajectory/*`, `lib/widgets/analysis/*`, `lib/widgets/analysis_tab.dart`,
`lib/screens/replay_screen.dart`, `lib/widgets/replay_shot_widget.dart`,
`lib/widgets/replay_trace_painter.dart` are deleted (−4026 lines net).
Replay now runs through `ShotTraceGeometry` → `TrainTargetWidget` +
`ShotReplayControls`. Also: `print` → `debugPrint`, `withOpacity` → `withValues`,
and removal of unused fields/params.

**Not yet committed — do not lose these.** Verify with
`git status --short` before committing anything else.

### Known follow-ups (non-blocking)

- `firmware_service.expectedVersion = '1.4.0'` vs firmware `FIRMWARE_VERSION "2.0.0"`
  (`Firmware_STASYS32/src/main.cpp:22`) — inert while the firmware does not answer
  `GET_VERSION`.
- ~3 s connect delay while the app waits for that unanswered `GET_VERSION`.
- `isAuthenticated` in `bluetooth_provider.dart` now means "streaming active" (old name).
- `Firmware_STASYS32/src/ota/*` is dead code (not in `src/CMakeLists.txt` SRCS);
  its `extern isAuthenticated` guard is stale — replace with
  `g_state != BT_OTA_IDLE` before reviving OTA.
- Greeting chunk that also carries the first frame loses ~1 frame (FrameAssembler resync).
- **Hardware acceptance still outstanding**: flash firmware → reboot → connect to
  `STASYS-XXXX` → immediate stream, no key/provisioning/PROOF.

---

## Known Issues / TODOs

### Completed (2026-06-13)
- [x] **CRC16 Scope Mismatch in `computeCRC16()` — CRITICAL FIX (Live Tracking Now Working!)**
  - **Symptom**: Bluetooth auth berhasil, ESP32 mulai streaming, tapi Flutter reject SEMUA packet dengan `[BT] CRC16 fail`. Muzzle trace kosong.
  - **Root cause**: `computeCRC16()` di `Firmware_STASYS32/src/main.cpp:199-201` pakai `sizeof(DataPacket) - 2` = 29 bytes. Itu termasuk 2 byte CRC field itu sendiri (yang masih 0x0000 saat compute). Flutter hitung CRC dari 27 bytes (bytes 2-28, exclude CRC) → mismatch permanent.
  - **Fix**: Ubah ke `crc16_ccitt((const uint8_t*)pkt + 2, 27)` — hanya 27 bytes payload (6 floats + piezo + battery), exclude sync header DAN crc16 field.
  - **Verification**: Upload firmware via COM3. Build sukses (RAM 22.1%, Flash 97.3%). Test di HP: live tracking muncul, trace path dan dot bergerak real-time mengikuti gerakan ESP32.
  - **Files**: `Firmware_STASYS32/src/main.cpp`

- [x] **Firmware Version Sync ke 1.4.0 (2026-06-13)**
  - **Firmware**: `storage.h:8` ubah `#define FIRMWARE_VERSION "1.3.0"` → `"1.4.0"`
  - **Flutter**: `firmware_service.dart:20` `expectedVersion = '1.4.0'` (sebelumnya sudah 1.4.0)
  - **Result**: Dialog OTA tidak muncul lagi saat connect — versi cocok antara ESP32 dan Flutter.
  - **Upload method**: USB/COM3 langsung (10-15 detik) bukan OTA Bluetooth (~45 menit). User pilih jalur cepat.

### Completed (2026-06-13)
- [x] **OTA Drain Loop Steals Sensor Packets — CRITICAL FIX**
  - **Symptom**: Live tracking UI kosong setelah fitur OTA Bluetooth ditambahkan. Tidak ada gambar = data sensor tidak sampai ke Flutter.
  - **Root cause**: `btOtaTask` di `Firmware_STASYS32/src/ota/bt_ota.cpp:198-237` membaca SerialBT **terus-menerus sejak auth sukses**, tidak peduli OTA aktif atau tidak. Byte dari `SerialBT.write()` (sensor packets 31-byte) di-read → masuk `g_lineBuf` (max 255) → overflow → discarded.
  - **Fix**: Tambah guard `if (g_state == BT_OTA_IDLE) { taskYIELD(); continue; }` di line 207-213. Drain loop **hanya** aktif saat OTA berjalan (`g_state != BT_OTA_IDLE`).
  - **Verification**: Build sukses (RAM 22.1%, Flash 97.3% — sama dengan sebelumnya). Perlu test upload + live tracking.
  - **Files**: `Firmware_STASYS32/src/ota/bt_ota.cpp`

- [x] **Cancel OTA via BT disconnect — Safety Analysis (2026-06-13)**
  - **Firmware**: AMAN. Saat `SerialBT.connected()` return false → `isAuthenticated = false` → `btOtaReset()` trigger → `esp_ota_abort()` cleanup → ESP32 boot dari partisi lama (tidak ada brick risk).
  - **Flutter**: AMAN secara safety. `OtaProvider._state` tidak ter-reset ke idle otomatis saat disconnect (hanya saat app restart), tapi tidak ada crash/leak.
  - **Decision**: User akan re-do OTA dari awal (~45 menit) saat reconnect — tidak implement resume untuk simplicity. Progress OTA tidak resume, tapi firmware selalu boot dari partisi valid.

- [x] **Python Desktop App — Archived (2026-06-13)**
  - 16 file Python (XOR/30-byte protocol) dipindahkan ke `_python_legacy/`. Folder ditambah ke `.gitignore`. Folder kosong `Python/` dan `ssa_app/Simulasi Python/` dihapus.
  - Fokus sekarang hanya Flutter + Firmware. Update Python ke CRC16/31-byte deferred.

### Completed (2026-05-23)
- [x] **OTA Bluetooth Firmware Update** — ✅ WORKING! Full E2E implementation complete.
  - **Architecture**: Dual-task FreeRTOS (drain loop + write task), semaphore signaling, queue-based async write
  - **Protocol**: Text commands (GET_VERSION, OTA_START, OTA_DATA, OTA_FINISH, REBOOT), base64 encoding, SHA256 verification
  - **Chunk size**: 128 bytes (raw) → ~172 bytes (base64) → ~200 bytes (BT transfer) — fits ESP32 BT RX buffer
  - **Speed**: ~13,500 chunks @ 200ms delay = ~45 minutes for 1.7MB firmware
  - **Key fixes**:
    - Flutter `_otaTextBuffer` cleared BEFORE switching to `otaMode` (prevents RangeError)
    - ESP32 drain loop: `taskYIELD()` after EVERY byte processed (prevents BT buffer overflow)
    - ESP32 drain loop: 5ms delay between iterations (fast enough to prevent overflow)
    - Semaphore-based ACK signaling (non-blocking, responsive)
  - **Files**: `bt_ota.cpp`, `bt_ota.h`, `bt_ota_commands.h`, `bluetooth_provider.dart`, `ota_provider.dart`, `firmware_service.dart`, `ota_update_screen.dart`, `ota_prompt_dialog.dart`
  - **Status**: Production-ready, tested E2E, firmware uploaded via COM3
  - ⚠️ **NOTE 2026-06-13**: Drain loop originally ran 24/7 from auth — fixed to only run during active OTA (see OTA Drain Loop Steals Sensor Packets above).

### Pending
- [ ] **OTA Speed Optimization** — Current: 45 min for 1.7MB. Target: 10-15 min. Approaches: larger chunks (256 bytes), burst mode (batched ACKs), reduced delay. Needs incremental testing.
- [ ] **Firebase Crashlytics** — dependency added (2026-05-05), setup pending (needs Firebase account + google-services.json)
- [ ] **Frame freeze / gralloc4 GPU buffer failure** — GPU/driver incompatibility with Impeller. **Not app code issue**. Test on different device.
- [ ] **MantisX feature parity** — drill modes, trend analysis, split time, session notes, etc.
- [ ] **Supabase cloud sync** — spec only (`97820ae`). Not implemented.
- [ ] **Dead-code cleanup** — 22 unreachable Flutter files listed by `ssa_app/tool/live_files.py`.
- [ ] **Hardware acceptance for the auth-free protocol** — flash → reboot → connect → immediate stream, no key.

### Live Tracking Requirements (2026-04-24)
User requirements for MantisX-style live tracking:
1. **60fps smooth** — no stutter
2. **Dot follows hardware 1:1** — up=up, right=right, no inversion
3. **Camera follows dot** — view/dot stays centered, background moves (camera movement style)
4. **Calibration = zero drift** — dot stays centered when hardware is still (auto-cal on first 50 samples)
5. **Trace line visible** — trail shows movement history continuously
6. **Auto-tare** — silent re-centering when drift detected while stationary
7. **Auto-zoom** — zoom adjusts dynamically to keep movement visible on canvas

**Implementation (2026-04-26)**:
- `sensor_data_isolate.dart`: auto-calibrate first 50 samples → compute gyro zero-offset
- `sensor_data_isolate.dart` ShotDetector: auto-tare (stationaryThreshold=1.0 rad/s, driftThreshold=0.02 rad, interval=3s) — triggers when hardware is still for ~0.5s AND trace has drifted >1.1°
- `muzzle_trace_widget.dart`: camera lerp 0.03 (~500ms delay), auto-zoom (minZoom=0.015, maxZoom=0.12), smooth shot reset, trace rebuild from isolate snapshot
- Gyro-only for tracking (integrate → quaternion → atan2 projection). Accel only for init orientation + shot detection.
- **Bug fixed (2026-04-26)**: `_shotDetector.process()` was receiving **bias-corrected** gyro from isolate, then bias-correcting AGAIN internally → double subtraction caused accumulated drift. Fixed by passing **raw** gyro to `process()` — bias correction now happens exactly once inside `process()`.

### Progress 2026-10-18 — Auth-Free Protocol Adoption + Train Redesign ✅

**Keputusan (2026-10-18)**: ikuti upstream `dylemmas/STASYS_FW` `5f955e8` yang menghapus seluruh autentikasi.
Menggantikan implementasi auth v2 (HMAC + device key) dari 2026-10-04/06 — commit-nya tetap di history.

- [x] **Firmware `96bb3b4`**: hapus auth state machine, provisioning, enrollment window;
  `ESP_SPP_SEC_NONE`; greeting statis `READY v=2
`; send gate koneksi saja.
  39/39 test Python; pio build OK (RAM 15.3%, Flash 49.3%). Diagnostik ADC/piezo dipertahankan.
- [x] **Flutter `7bbff1c`**: phase → greeting→streaming langsung (`requestFullSync()` tanpa PROOF);
  hapus key store, DEVICE KEY UI, `flutter_secure_storage`, `allowBackup=false`.
  190/190 test; APK debug build OK. Greeting parser hanya menerima `READY v=2`.
- [x] **Redesign UI `a906431`** (kerjaan user): train screen redesign (shot replay controls,
  target replay view, train target widget), theme context-aware `StsysTheme.*Of(context)` di semua
  screen, widget tests baru (shot_replay_controls, train_target_widget, train_screen, settings_provider).
- [x] **`.gitignore` `60b25d1`**: izinkan `Firmware_STASYS32/test/**/*.py`.
- Review: tiap task dua tahap (spesifikasi + kualitas) + review final cross-boundary pairing → READY.

**Uji hardware (belum dilakukan)**: flash firmware → reboot → connect ke STASYS-XXXX →
stream langsung jalan. **Tanpa key/provisioning/PROOF.**

**Known follow-ups (non-blocking)**:
- `Firmware_STASYS32/src/ota/*` adalah dead code (tidak di CMakeLists SRCS);
  guard `extern isAuthenticated`-nya sudah usang — ganti dengan `g_state != BT_OTA_IDLE` sebelum OTA dihidupkan lagi.
- `firmware_service.expectedVersion '1.4.0'` vs firmware `2.0.0` — inert selama GET_VERSION tidak diimplementasi.
- Delay ~3 detik saat connect (menunggu GET_VERSION timeout yang memang tak dijawab firmware v2).
- `isAuthenticated` di provider kini berarti "streaming aktif" (nama lama, rename opsional).
- Greeting chunk yang menyertakan frame pertama: ~1 frame hilang (FrameAssembler resync; sudah dicatat).

### Migration Status (2026-05-09, updated 2026-11-22)

| Component | Protocol | Status |
|-----------|---------|--------|
| `Firmware_STASYS32/` | STASYS_FW v2 (36-byte XOR, ESP-IDF) | ✅ Updated — auth-free, upstream `5f955e8` |
| `Flutter bluetooth_provider.dart` | 36-byte XOR frame parser | ✅ Updated |
| `Flutter settings_screen.dart` | Mount Direction/Position + RESET AXIS | ✅ Implemented (2026-05-09) |
| `Python desktop apps` | XOR (30-byte) | 📁 Archived to `_python_legacy/` (2026-06-13). Update deferred. |

> **Firmware**: ESP32-D0WD-V3, MAC 78:1c:3c:f5:16:18, `FIRMWARE_VERSION "2.0.0"`
> (`src/main.cpp:22`). Last uploaded 2026-06-13 via COM3 — that build predates the
> ESP-IDF port, so **the current firmware has never been flashed to hardware**.
> **Live Tracking Status**: last verified 2026-06-13 on the CRC16-era build; the
> current 36-byte/XOR protocol is verified by contract tests only.

### Quick Wins (2026-05-09) ✅
- [x] Fix duplicate `@override` in `sensor_data_provider.dart:512`
- [x] Mount Direction FW/BW toggle (enum `MountDirection` + SettingsProvider + isolate + UI binding)
- [x] Mount Mode selector TOP/BOT/LEFT/RIGHT (enum `MountPosition` + 4-button grid with active state)
- [x] RESET AXIS button (clears gyro offsets, re-runs 50-sample auto-calibration via isolate)

### App Shell Redesign (2026-04-09) + SQLite Migration (2026-04-14)
- [x] GoRouter with ShellRoute (3-tab bottom nav: Tracking/History/Settings — since grown to 4 tabs: Train/History/Tracking/Settings)
- [x] SplashScreen (STSYS branding, 2s auto-navigate)
- [x] ConnectionScreen (BT scan/connect + Explore App demo mode)
- [x] TrackingScreen (mode selection 4 firearm cards + live graph)
- [x] TrackingModeView (live TRACE + POST SHOT tabs + mode change dialog)
- [x] HistoryScreen (session list + swipe delete + clear all + refresh button)
- [x] SettingsScreen (BT scan overlay + firearm type + training mode)
- [x] SessionDetailScreen (POST SHOT 3-phase + horizontal shot chips)
- [x] Demo mode (random gyro/accel + auto shot 4-8s + score 65-95)
- [x] Shot selection persistence (hasUserSelected flag)
- [x] Battery indicator in all headers
- [x] Demo mode: BT scan redirects to connection, connect auto-disables demo
- [x] **SQLite persistence** (2026-04-14): Migrated from SharedPreferences (JSON) → SQLite with binary BLOB encoding. `services/database_helper.dart` (singleton, schema, indexes) + `services/database_service.dart` (CRUD, encode/decode). `session_logger.dart` delegates to `DatabaseService` — backward compatible API.
- [x] **Export Service** (2026-04-14): CSV export via Share Sheet. `services/export_service.dart` exports all sessions (session summary + shot details). Button added to HistoryScreen header. Uses `share_plus` package.
- [x] **Live trace drift fix** (2026-04-26): Double bias correction bug — isolate pre-subtracted gyro offset before passing to `process()`, which then subtracted again internally, causing `gx - 2*offset` integration error → accumulated drift. Fixed by passing raw gyro to `process()`. Auto-tare (stationary + drift threshold), auto-zoom, camera follow all working.

### Historical / Fixed
- [x] esp_bt_gap.h not found in PlatformIO — GAP callback removed
- [x] Preferences::getString() wrong args — fixed in config.cpp
- [x] sensor.cpp goto crosses initialization — declarations moved to top
- [x] mbedtls/hmac.h not found — security.cpp stubbed
- [x] RecoveryTask watchdog timeout — added `esp_task_wdt_reset()` in loop
- [x] CMD_START_SESSION guard blocking Flutter auth — removed `_isAuthenticated` check
- [x] Firmware not sending EVT_AUTH_CHALLENGE — added to dispatchCommand
- [x] PktRawSample sizeof mismatch — changed to 24 bytes
- [x] ESP32 TX serial debug flooding — limited to first 3 packets
- [x] **CRC scope mismatch** — Fixed firmware `encodePacket()` to use `3+len`.
- [x] **EVT_SENSOR_HEALTH (0x13)** — Added handler in Flutter `_handlePacket()`.
- [x] Dark STSYS theme applied — `app_theme.dart` with STSYS palette, Manrope/Inter fonts
- [x] Muzzle trace enhancement — opacity fade, motion blur, dynamic dot sizing

### Flutter Performance (Phase 1 & 2 — 2026-04-07)
- Eliminated ~1,100 Paint/Color/TextPainter allocations/sec
- Eliminated ~180 list allocations/sec
- Eliminated ~20 list allocations/shot
- Data decimation: ~500 → 150 points per UI update (~70% reduction)
- UI throttle: 50ms → 33ms (~30Hz)
- Smart `shouldRepaint` + `RepaintBoundary` on all CustomPainters
- Recording timer: global `notifyListeners()` → `ValueNotifier<Duration>`

---

## UI/UX Design References

> ⚠️ The `UI UX Design/` folder **no longer exists on disk** (removed during the
> 2026-10 repo cleanup, `6c527a3`). The HTML mockups it held are gone. The live
> design source of truth is now the Figma file used for the train-flow redesign
> (see `docs/superpowers/specs/2026-09-13-figma-train-flow-redesign-design.md`).

The two historical directions, for reference only:

### DESIGN 1 — Evolutionary Redesign (2026-04-10, superseded)
Polish from the Tactical Precision design system: glassmorphism cards, Manrope +
Inter, pulse/gradient animations, tiered score rings. The warm-orange accent
(`#FFB693`) it used is **no longer** the app's primary (see Theme above).

### DESIGN 2 — Night Ops HUD (2026-04-10, superseded)
Military HUD aesthetic: near-black-blue surfaces, Orbitron display type, cyan
`#00D4FF` secondary, frosted-glass cards, radar/status indicators. The cyan half
of this direction survived into the current palette; the orange did not.

---

## Contact / Support

This is a DIY project. ESP32 + MPU6050 + Piezo hardware required for full functionality.