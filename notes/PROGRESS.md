# STASYS Progress Tracker

Track semua fitur dan todo items. Format: `[DONE]` `[IN-PROGRESS]` `[TODO]`

---

## Flutter App (ssa_app)

### Core Features
- [DONE] Binary packet parsing (30 bytes, 100Hz)
- [DONE] MPU6050 sensor data display
- [DONE] Shot detection state machine (IDLE→ARMING→ARMED→POST_GATHER→COOLDOWN)
- [DONE] MantisX-style scoring algorithm
- [DONE] Bluetooth connection (flutter_bluetooth_serial)
- [DONE] SQLite database (recordings + shots tables)
- [DONE] Session recording & playback
- [DONE] Shot chart visualization
- [DONE] Report card view

### UI Screens
- [DONE] Main dashboard
- [DONE] Live monitor screen
- [DONE] Session history screen
- [DONE] Settings screen
- [DONE] Report card screen
- [DONE] Shot timer tab (connected to sensor data provider)
- [DONE] Post-shot analysis tab (3-phase chart + shot history)
- [DONE] CRC protocol fix (firmware scope 2+len → 3+len)
- [DONE] EVT_SENSOR_HEALTH (0x13) handler

### TODO / Enhancement
- [TODO] Export service (export_service.dart - not yet implemented)
- [TODO] Battery monitoring UI (firmware sends it, but not consistently surfaced)
- [TODO] Unify Python/Flutter scoring (currently different algorithms)
- [TODO] README.md for ssa_app
- [TODO] Hardware build guide
- [TODO] Demo mode (testing without hardware)

### Known Issues
- [NOTE] Android BT fragmentation causes ~0.01% CRC error on DATA_RAW (non-critical)

---

## Python App (Python Code (SSA))

### Core Features
- [DONE] Binary packet parsing (30 bytes)
- [DONE] SHA256 authentication with ESP32
- [DONE] SQLite database integration
- [DONE] PyQt5 GUI
- [DONE] Real-time pyqtgraph display
- [DONE] Session report card

### Scoring
- [DONE] Hardcore scoring (Travel=1200, Jerk=5000 penalties)
- [NOTE] Different from Flutter MantisX-style soft curve

### TODO / Enhancement
- [TODO] STASY_V4.py is a duplicate - merge or delete
- [TODO] Unify scoring with Flutter app

### Known Issues
- [BUG] STASY_V4.py duplicate file needs cleanup

---

## Firmware (ESP32)

### Core Features
- [DONE] MPU6050 sensor reading
- [DONE] Piezo shot trigger detection
- [DONE] Bluetooth Classic serial (SPP)
- [DONE] 30-byte binary packet @ 100Hz
- [DONE] SHA256 authentication
- [DONE] Battery monitoring
- [DONE] Oversampling mode (v2.0-OVERSAMPLE)

### TODO / Enhancement
- [TODO] Nothing currently flagged

---

## Documentation

- [DONE] CLAUDE.md (project overview, protocol, algorithms)
- [DONE] This notes folder
- [TODO] README.md for ssa_app
- [TODO] Hardware build guide

---

## Priority Order (What to work on next)

1. Connect shot timer to sensor data provider
2. Implement export service
3. Battery monitoring UI
4. Clean up STASY_V4.py duplicate
5. README.md for ssa_app
