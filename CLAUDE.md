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
│       │   ├── bluetooth_provider.dart  # CRC16 verification (31-byte packets)
│       │   ├── sensor_data_provider.dart # UI state, isolate communication, demo mode
│       │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis
│       │   ├── settings_provider.dart    # + isDemoMode, setDemoMode()
│       │   ├── session_provider.dart
│       │   └── session_logger.dart       # Delegates to DatabaseService (SQLite)
│       ├── screens/
│       │   ├── splash_screen.dart        # STSYS branding, 2s auto-navigate
│       │   ├── connection_screen.dart     # BT scan/connect + Explore App
│       │   ├── main_shell.dart          # 3-tab NavigationBar shell
│       │   ├── tracking_screen.dart     # Mode selection (4 firearm cards)
│       │   ├── tracking_mode_view.dart   # Live graph + mode change dialog
│       │   ├── history_screen.dart      # Session list + clear all + refresh
│       │   ├── settings_screen.dart     # BT scan overlay + settings + target distance slider
│       │   └── session_detail_screen.dart # POST SHOT | ANALYSIS toggle + shot chips
│       └── widgets/
│           ├── muzzle_trace_widget.dart  # MantisX-style live trace
│           ├── shot_analysis_panel.dart  # 3-phase post-shot chart
│           ├── shot_history_list.dart    # Session shot list
│           ├── gyro_realtime_chart.dart  # Real-time gyro chart
│           └── analysis/                 # Offline trajectory replay widgets
│               ├── analysis_tab.dart     # Composite: BarrelTraceCanvas + Scrubber + PhaseSummary + FactorBreakdown
│               ├── trajectory_canvas.dart    # Barrel trace + target overlay + shot markers
│               ├── trajectory_scrubber.dart  # Timeline scrubber + shot chip selector
│               ├── phase_summary_card.dart   # Per-shot 3-phase chart
│               └── factor_breakdown_card.dart # Stability/smoothness/harmonics factor scores
│
├── Firmware_STASYS32/                 # Modular ESP32 firmware (STASYS_FW)
│   └── src/
│       ├── main.cpp                    # Entry, 4 FreeRTOS tasks
│       ├── storage/
│       │   ├── storage.h/cpp           # NVS config/stats/auth
│       │   ├── crc.h/cpp               # CRC16-CCITT
│       │   ├── status_led.h/cpp         # LED patterns
│       │   └── ota.h/cpp               # OTA manager
│       └── sensor/
│           ├── quaternion.h             # Header-only quaternion ops
│           ├── madgwick.h/cpp           # AHRS filter
│           ├── calibration.h/cpp        # IMU calibration + ZUPT
│           └── i2c_bus_recovery.h/cpp   # I2C bus recovery
│
└── Python Code (SSA)/          # OLD — all moved to _python_legacy/ (2026-06-13)
    └── (archived)

### Trajectory Replay Pipeline (2026-06-21) — ✅ Working (2026-07-08)

Offline replay engine converts saved `SessionLog` into visual trajectory.
Critical fix (2026-07-08): `_mergeAccelGyro()` now pairs by **list index** instead of timestamp buckets
(timestamps are epoch ms, not relative → unique buckets → 0 matches).
- `services/trajectory/`: quaternion ops, barrel projection, replay engine
- `widgets/analysis/`: barrel trace canvas, timeline scrubber, phase summary, factor breakdown
- Access: `SessionDetailScreen` → ANALYSIS tab → renders `AnalysisTab` composite widget
- Known: shot detection threshold (4.0 rad/s stability window) may not trigger for slow/dry-fire movements

See `ssa_app/CLAUDE.md` for full details.

```

---

## Communication Protocol

> **Updated (2026-05-05)**: Firmware STASYS_FW menggunakan CRC16-CCITT (31 bytes), bukan XOR (30 bytes).

### Binary Packet Format (STASYS_FW — 31 bytes)

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
| 29 | 2 | crc16 | CRC16-CCITT over bytes 2..28 |

**CRC16-CCITT**: Initial `0xFFFF`, polynomial `0x1021`.
Test vector: `'123456789'` → `0x29B1`

**Authentication** (text-based):
```
ESP32 → App: "READY\n"
App → ESP32: "AUTH_CHALLENGE\n"
ESP32 → App: SHA256(challenge + SECRET_KEY) hex\n
ESP32 → App: streams 31-byte binary packets @ 100Hz
```
**Secret Key**: `12ebaf10h12fa9123z21sti`

---

## Database Schema (SQLite — stasys_sessions.db)

> **Implemented**: 2026-04-14 — migrated from SharedPreferences (JSON) to SQLite for production scalability.
> Storage location: `getDatabasesPath() + '/stasys_sessions.db'` (Android internal storage).

### Table: `sessions`
```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  date INTEGER NOT NULL,          -- Unix timestamp (ms)
  duration REAL NOT NULL,          -- seconds
  firearm_type TEXT NOT NULL,
  training_mode TEXT NOT NULL,
  gyro_x BLOB,                    -- Binary encoded time series
  gyro_y BLOB,
  gyro_z BLOB,
  accel_x BLOB,
  accel_y BLOB,
  accel_z BLOB
);
CREATE INDEX idx_sessions_date ON sessions(date DESC);
CREATE INDEX idx_sessions_firearm ON sessions(firearm_type);
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

Time series and phase traces are stored as binary BLOB (not JSON) for compactness and speed:

**Time series** (gyro/accel per session): `pointCount(int32)` + `[relTimestamp(float32) + value(float32)] * N`
**Phase traces** (per shot): `count(int32)` + `[value(float64)] * N`

Benefits: ~40% more compact than JSON, 5x faster decode, no JSON parsing overhead.

---

## Development Workflow

### Building & Uploading Firmware (PlatformIO)
```bash
# Find ESP32 COM port first
powershell -Command "[System.IO.Ports.SerialPort]::GetPortNames()"

# Build
cd Firmware_STASYS32
python -m platformio run -e esp32dev

# Upload (COM12 detected 2026-05-05)
python -m platformio run -e esp32dev --target upload --upload-port COM12

# Monitor serial
python -m platformio device monitor --port COM12 --baud 115200
```

### Testing Flutter App
```bash
cd ssa_app
flutter build apk --debug
# Install APK from build/app/outputs/flutter-apk/app-debug.apk
```

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
crypto: ^3.0.3  # SHA256 for HMAC auth
intl: ^0.19.0
go_router: ^15.1.0
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

### Arduino / ESP32 (PlatformIO)
```
framework: arduino (ESP32 arduino core 3.20017)
BluetoothSerial (built-in ESP32)
Wire (built-in)
WiFi (built-in)
Preferences (built-in)
esp_https_ota (built-in)
```

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

### Migration Status (2026-05-09)

| Component | Protocol | Status |
|-----------|---------|--------|
| `Firmware_STASYS32/` | STASYS_FW (CRC16, 31-byte, FreeRTOS) | ✅ Updated — from `dylemmas/STASYSFW` |
| `Flutter bluetooth_provider.dart` | CRC16 verification | ✅ Updated |
| `Flutter settings_tab.dart` | Mount Direction/Position + RESET AXIS | ✅ Implemented (2026-05-09) |
| `Python desktop apps` | XOR (30-byte) | 📁 Archived to `_python_legacy/` (2026-06-13). Update deferred. |

> **Firmware Uploaded**: 2026-06-13 via COM3 (latest, v1.4.0 with CRC16 scope fix). Chip ESP32-D0WD-V3, MAC 78:1c:3c:f5:16:18.
> **Live Tracking Status**: ✅ WORKING (verified 2026-06-13). Bluetooth auth + CRC16 verification + streaming data + muzzle trace rendering semua berfungsi.

### Quick Wins (2026-05-09) ✅
- [x] Fix duplicate `@override` in `sensor_data_provider.dart:512`
- [x] Mount Direction FW/BW toggle (enum `MountDirection` + SettingsProvider + isolate + UI binding)
- [x] Mount Mode selector TOP/BOT/LEFT/RIGHT (enum `MountPosition` + 4-button grid with active state)
- [x] RESET AXIS button (clears gyro offsets, re-runs 50-sample auto-calibration via isolate)

### App Shell Redesign (2026-04-09) + SQLite Migration (2026-04-14)
- [x] GoRouter with ShellRoute (3-tab bottom nav: Tracking/History/Settings)
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

## UI/UX Design Mockups (NOT YET IMPLEMENTED)

HTML mockups exist for visual reference. Both designs are **not yet implemented** in Flutter code.

```
d:\Aydiner\Projek Flutter SSA\
└── UI UX Design\
    ├── Currently_used\                  # Exact replica of current Flutter UI
    │   ├── index.html
    │   ���── splash-screen.html
    │   ├── connection-screen.html
    │   ├── tracking-mode-selection.html
    │   ├── tracking-live.html
    │   ├── history-screen.html
    │   ├── settings-screen.html
    │   └── session-detail.html
    └── DESIGN\
        ├── DESIGN 1 (Redesign Tampilan - 2026-04-10)\
        │   ├── index.html
        │   ├── splash-screen.html
        │   ├── connection-screen.html
        │   ├── tracking-mode-selection.html
        │   ├── tracking-live.html
        │   ├── history-screen.html
        │   ├── settings-screen.html
        │   └── session-detail.html
        └── DESIGN 2 (Night Ops HUD - 2026-04-10)\
            ├── index.html
            ├── splash-screen.html
            ├── connection-screen.html
            ├── tracking-mode-selection.html
            ├── tracking-live.html
            ├── history-screen.html
            ├── settings-screen.html
            └── session-detail.html
```

**Preview**: Open any `.html` file in Chrome/Edge/Firefox. Uses Google Fonts + Phosphor Icons CDN — no build needed.

---

### DESIGN 1 — Evolutionary Redesign

**Approach**: Polish and refine from existing Tactical Precision design system.

| Element | Change from current |
|---------|-------------------|
| Base bg | `#0D0D0D` (deeper dark) |
| Primary accent | `#FFB693` (warm orange) |
| Typography | Manrope + Inter, larger display, tighter body |
| Cards | Glassmorphism with backdrop blur, rounded corners (12-16px) |
| Animations | Pulse dots, fade transitions, gradient shimmer on buttons |
| Score display | Ring/badge with tier colors (Elite/Expert/Advanced/etc.) |
| Empty states | Illustrated with clear CTAs |

**Preview**: `UI UX Design/DESIGN/DESIGN 1 (Redesign Tampilan - 2026-04-10)/index.html`

---

### DESIGN 2 — Night Ops HUD (2026-04-10)

**Approach**: Military/tactical HUD aesthetic with advanced data visualization.

| Element | Change |
|---------|--------|
| Base bg | `#080C10` (near-black blue) |
| Surface | `#0D1520` (dark navy) |
| Primary accent | `#FF6B3D` (tactical orange-red) |
| Secondary | `#00D4FF` (cyan HUD) |
| Typography | **Orbitron** (HUD/tech display) + Inter (body) |
| Icons | Phosphor Icons (duotone) |
| Cards | Frosted glass with corner bracket decorations + cyan glow |
| Score display | HUD ring with animated fill + glow pulse |
| Charts | Animated SVG scan line sweeping, glow layers |
| Animations | Radar sweep, scan effects, staggered reveals |
| Status indicators | Animated radar pulse, signal bars |

**Preview**: `UI UX Design/DESIGN/DESIGN 2 (Night Ops HUD - 2026-04-10)/index.html`

---

## Contact / Support

This is a DIY project. ESP32 + MPU6050 + Piezo hardware required for full functionality.