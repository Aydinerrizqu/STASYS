# STASYS - Shooter Stability Analysis System

> **Note**: For Flutter app development, see `ssa_app/CLAUDE.md`.
> For firmware development, see `Firmware_STSYS32/CLAUDE.md`.
> That file covers PlatformIO build, module architecture, remote sync workflow, and hardware pinout.

## Project Overview

STASYS is a DIY shooter training device inspired by MantisX ($99-$249). It consists of:
- **Hardware**: ESP32 + MPU6050 + Piezo sensor, Bluetooth Classic
- **Python App**: `Python Code (SSA)/STASYS.py` - Desktop analysis tool (PyQt5)
- **Flutter App**: `ssa_app/` - Mobile companion (Android/iOS)
- **Firmware**: `Firmware_STSYS32/` - Modular PlatformIO ESP32 firmware

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
│       ├── providers/
│       │   ├── bluetooth_provider.dart  # 8-state packet parser, CRC16-CCITT, HMAC-SHA256 auth
│       │   ├── sensor_data_provider.dart # UI state, isolate communication, demo mode
│       │   ├── sensor_data_isolate.dart  # Shot detection + 3-phase analysis
│       │   ├── settings_provider.dart    # + isDemoMode, setDemoMode()
│       │   ├── session_provider.dart
│       │   └── session_logger.dart
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
├── Firmware_STSYS32/                 # Modular PlatformIO ESP32 firmware
│   └── src/
│       ├── main.cpp           # FreeRTOS tasks
│       ├── protocol.h/cpp     # Packet framing, CRC16-CCITT
│       ├── sensor.h/cpp       # MPU6050 ISR-driven reading
│       ├── bluetooth.h/cpp     # SPP BT, command dispatch
│       ├── shot_detector.h/cpp # Adaptive threshold shot detection
│       ├── security.h/cpp      # Auth stub
│       ├── session.h/cpp       # Session state: IDLE→STREAMING
│       ├── config.h/cpp        # NVS persistent config
│       ├── battery.h/cpp       # Battery monitoring
│       ├── led.h/cpp           # LED feedback
│       ├── storage.h/cpp       # Flash session storage
│       └── ota.h/cpp           # OTA firmware update
│
└── Python Code (SSA)/
    └── STASYS.py               # Desktop app with ProtocolDecoder class
```

---

## Communication Protocol

### Binary Packet Format

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

## Database Schema (shooter_data.db)

### Table: `recordings`
```sql
id INTEGER PRIMARY KEY
timestamp DATETIME
session_id TEXT
stability_score REAL
battery_percentage REAL
elev REAL
wind REAL
cant REAL
firearm_type TEXT  -- Pistol/Rifle/Shotgun/Archery
training_mode TEXT  -- dryFire/liveFire
```

### Table: `shots`
```sql
id INTEGER PRIMARY KEY
timestamp DATETIME
session_id TEXT
score REAL
cant REAL
mode TEXT
firearm_type TEXT
training_mode TEXT
press_score REAL
hold_score REAL
recoil_score REAL
elevation_score REAL
windage_score REAL
```

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
shared_preferences: ^2.2.2
permission_handler: ^12.0.1
path_provider: ^2.1.1
crypto: ^3.0.3  # SHA256 for HMAC auth
intl: ^0.19.0
```

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
- [ ] **Android BT fragmentation** — DATA_RAW_SAMPLE CRC errors ~0.01% (1 in ~9400 packets). Non-critical — sensor data still flows at 99.99% integrity.
- [ ] **Export service** — `export_service.dart` not yet implemented.
- [ ] **Trace window sync with Python** — Flutter 2s window vs Python 0.5s cursor-normalized.

### Migration Status

| Component | Protocol | Status |
|-----------|---------|--------|
| `Firmware_STSYS32/` | New (CRC16-CCITT) | Complete, uploaded to ESP32 |
| `Python Code (SSA)/STASYS.py` | New | ProtocolDecoder class added |
| `ssa_app/` Flutter | New | App shell redesign + GoRouter + demo mode |

### App Shell Redesign (2026-04-09)
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
