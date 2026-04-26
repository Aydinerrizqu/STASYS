# STASYS - Shooter Stability Analysis System

> **Note**: For Flutter app development, see `ssa_app/CLAUDE.md`.
> For firmware development, see `Firmware_STSYS32/CLAUDE.md`.
> That file covers PlatformIO build, module architecture, remote sync workflow, and hardware pinout.

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: ESP32 + MPU6050 + Piezo sensor, Bluetooth Classic
- **Python App**: `Python Code (SSA)/STASYS.py` - Desktop analysis tool (PyQt5)
- **Flutter App**: `ssa_app/` - Mobile companion (Android/iOS)
- **Firmware**: `Firmware_STSYS32/` - Single-file PlatformIO ESP32 firmware (upstream original)

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
│       │   ├── bluetooth_provider.dart  # Text auth (upstream) + dual-mode parser (text auth → binary float 30-byte)
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
│       │   ├── settings_screen.dart     # BT scan overlay + settings
│       │   └── session_detail_screen.dart # POST SHOT 3-phase + shot chips
│       ├── screens/tabs/                # (legacy — used by tracking_mode_view)
│       │   ├── home_tab.dart
│       │   ├── graph_tab.dart            # TRACE (muzzle trace) + POST SHOT (3-phase)
│       │   ├── connection_tab.dart
│       │   ├── settings_tab.dart
│       │   └── shot_timer_tab.dart
│       └── widgets/
│           ├── muzzle_trace_widget.dart  # MantisX-style live trace
│           ├── shot_analysis_panel.dart  # 3-phase post-shot chart
│           ├── shot_history_list.dart    # Session shot list
│           └── gyro_realtime_chart.dart  # Real-time gyro chart
│
├── Firmware_STSYS32/                 # Single-file PlatformIO ESP32 firmware (upstream original)
│   └── src/
│       └── main.cpp           # ~297 lines, polling loop, text-based auth, XOR checksum
│
└── Python Code (SSA)/
    └── STASYS.py               # Desktop app with ProtocolDecoder class
```

---

## Communication Protocol

> **Dual-protocol support** (2026-04-22): Flutter app now handles upstream firmware (text auth + XOR + 30-byte float packets) in parallel with the modular firmware protocol via dual-mode parser.

### Upstream Original (Firmware_STSYS32 — Active)

**Binary Packet Format** (30 bytes):

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
| 29 | 1 | checksum | XOR of bytes 2..28 |

**Authentication** (text-based):
```
ESP32 → App: "READY\n"
App → ESP32: "AUTH_CHALLENGE\n"
ESP32 → App: SHA256(challenge + SECRET_KEY) hex\n
ESP32 → App: streams 30-byte binary packets @ 100Hz
```
**Secret Key**: `12ebaf10h12fa9123z21sti`
**Parser**: `_ConnectionPhase` state machine (waitingForReady → waitingForHash → streaming)

### Modular Firmware (Legacy — documented below)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Sync0 | `0xAA` |
| 1 | 1 | Sync1 | `0x55` |
| 2 | 1 | Type | Packet type (see table below) |
| 3 | 1 | LenLo | Payload length (LSB) |
| 4 | 1 | LenHi | Payload length (MSB) |
| 5..N | N | Payload | Packet-type-specific data |
| N+1 | 1 | CrcLo | CRC16-CCITT over TYPE(1)+LEN_LO(1)+LEN_HI(1)+payload(N) |
| N+2 | 1 | CrcHi | Total scope = 3+N bytes, not 2+N |

**CRC16-CCITT**: Initial `0xFFFF`, polynomial `0x1021`, no reflection, no final XOR.
Verified with test vector `'123456789'` → `0x29B1`.

### Packet Types

| Type | Name | Direction | Description |
|------|------|-----------|-------------|
| 0x01 | `CMD_START_SESSION` | App→Firmware | Start sensor streaming + trigger auth |
| 0x02 | `CMD_STOP_SESSION` | App→Firmware | Stop sensor streaming |
| 0x03 | `CMD_GET_INFO` | App→Firmware | Request device info |
| 0x04 | `CMD_GET_CONFIG` | App→Firmware | Request current config |
| 0x05 | `CMD_SET_CONFIG` | App→Firmware | Set config values |
| 0x06 | `CMD_AUTH` | App→Firmware | HMAC-SHA256 auth response |
| 0x10 | `EVT_SESSION_STARTED` | Firmware→App | Session started, session_id included |
| 0x11 | `EVT_SESSION_STOPPED` | Firmware→App | Session summary |
| 0x12 | `EVT_SHOT_DETECTED` | Firmware→App | Shot detected with peaks (info only) |
| 0x13 | `EVT_SENSOR_HEALTH` | Firmware→App | Sensor health heartbeat @ ~10Hz (8 bytes) |
| 0x14 | `EVT_AUTH_CHALLENGE` | Firmware→App | 16-byte challenge + session_id |
| 0x15 | `EVT_AUTH_SUCCESS` | Firmware→App | Auth successful |
| 0x1F | `EVT_ERROR` | Firmware→App | Error with code + message |
| 0x20 | `DATA_RAW_SAMPLE` | Firmware→App | Sensor data @ 100Hz (24 bytes) |
| 0x81 | `RSP_INFO` | Firmware→App | Device info response |
| 0x82 | `RSP_CONFIG` | Firmware→App | Config response |
| 0x83 | `RSP_ACK` | Firmware→App | Command acknowledgment |
| 0x85 | `RSP_SHOT_STATS` | Firmware→App | Shot statistics response |

### DATA_RAW_SAMPLE Payload (24 bytes — compiler-aligned)

| Offset | Size | Field | Type | Conversion |
|--------|------|-------|------|-----------|
| 0 | 4 | counter | uint32 | — |
| 1 | 4 | timestamp_us | uint32 | — |
| 2 | 2 | ax | int16 | raw / 8192.0 * 9.81 → m/s² |
| 3 | 2 | ay | int16 | raw / 8192.0 * 9.81 → m/s² |
| 4 | 2 | az | int16 | raw / 8192.0 * 9.81 → m/s² |
| 5 | 2 | gx | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 6 | 2 | gy | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 7 | 2 | gz | int16 | raw / 65.5 * 0.0174533 → rad/s |
| 8 | 2 | piezo | uint16 | ADC peak value |
| 9 | 2 | reserved | uint16 | was: temperature (unused) |

> ⚠️ **Struct alignment**: `sizeof(PktRawSample) = 24 bytes` (compiler packs). ESP32 is little-endian.

### Authentication Protocol

```
Flutter → ESP32: CMD_START_SESSION (0x01)
ESP32 → Flutter: EVT_AUTH_CHALLENGE (0x14) [session_id(4) + challenge(16) = 20 bytes]
Flutter → ESP32: CMD_AUTH (0x06) [session_id(4) + HMAC-SHA256(32) = 36 bytes]
ESP32 → Flutter: EVT_AUTH_SUCCESS (0x15) [session_id(4) = 4 bytes]
ESP32 → Flutter: EVT_SESSION_STARTED (0x10) [17 bytes]
ESP32 → Flutter: DATA_RAW_SAMPLE (0x20) @ 100Hz [24 bytes + 2 CRC = 31 bytes total frame]
```

**Secret Key**: `12ebaf10h12fa9123z21sti`
**HMAC Input**: challenge(16 bytes) + session_id(4 bytes LE)
**HMAC Output**: 32-byte digest, sent as-is (not hex-encoded)

---

## Database Schema (SQLite — stsys_sessions.db)

> **Implemented**: 2026-04-14 — migrated from SharedPreferences (JSON) to SQLite for production scalability.
> Storage location: `getDatabasesPath() + '/stsys_sessions.db'` (Android internal storage).

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

### Settings Persistence
App settings (firearm type, training mode, demo mode, max samples) remain in **SharedPreferences** — small, rarely accessed, no query needed.

---

## Key Algorithms

### Shot Detection State Machine (Firmware + Flutter Isolate)
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

**Difficulty Multipliers**: Pistol: 1.0, Rifle: 0.7, Archery: 1.3, Shotgun: 0.9
**Training Mode**: Live Fire gets 0.8x multiplier (more forgiving)

---

## Development Workflow

### Building & Uploading Firmware (PlatformIO)
```bash
# Find ESP32 COM port first
python -c "import serial.tools.list_ports; [print(p.device) for p in serial.tools.list_ports.comports()]"

# Upload to ESP32
cd Firmware_STSYS32
pio run --target upload --upload-port COM8
pio device monitor --port COM8 --baud 115200
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
Preferences (built-in)
```

---

## Known Issues / TODOs

### Pending
- [ ] **Frame freeze / gralloc4 GPU buffer failure** — GPU/driver incompatibility with Impeller rendering engine. **Not app code issue**. Test on different device.
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.
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

### Migration Status

| Component | Protocol | Status |
|-----------|---------|--------|
| `Firmware_STSYS32/` | Upstream original (text auth, XOR, float 30-byte) | ✅ Complete — reset to `dylemmas/STASYSESP32` single-file |
| `Python Code (SSA)/STASYS.py` | Upstream original | ✅ Compatible via ProtocolDecoder class |
| `ssa_app/` Flutter | Upstream original protocol | ✅ **Synced** — dual-mode parser handles text auth → binary streaming |

> ⚠️ **Flutter app NOT compatible with upstream firmware** — different protocol. Demo mode is primary way to use the app without ESP32 hardware.

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
    │   ├── splash-screen.html
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
