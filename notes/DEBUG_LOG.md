# STASYS Debug Log

Bug, error, dan solusi yang pernah dihadapi. Semua error baru harus dicatat di sini.

---

## [Tanggal] - 30-Byte Protocol Mismatch

**Error/Problem:**
Flutter `bluetooth_provider.dart` parsed 28 bytes while firmware sent 30 bytes. Caused data corruption - gyro values were garbage, battery/checksum misaligned.

**Root Cause:**
Firmware uses `uint16` for piezo ADC (2 bytes), but Flutter code used `uint8` (1 byte). This shifted all subsequent byte offsets.

**Solution:**
- Changed packetSize from 28 to 30
- Changed piezo field from `uint8` to `uint16` in format string `'<ffffffHB'`
- Byte offsets now: battery at 28, checksum at 29
- Max gyro validation set to 10.0 rad/s (firmware uses 500dps = ~8.73 rad/s range)

**Files Involved:**
- `ssa_app/lib/providers/bluetooth_provider.dart`
- `STASYS_Firmware_Oversampling.ino`

**Status:** RESOLVED

---

## [Tanggal] - Shot Timer Not Connected

**Error/Problem:**
Shot timer tab (`shot_timer_tab.dart`) has `_onShotDetected` callback that is never triggered. Sensor data provider doesn't fire the shot event to the timer.

**Root Cause:**
The shot detection logic exists in the sensor data isolate, but the connection to the UI-level shot timer widget was never implemented.

**Solution:**
- Need to wire up shot_detected message from isolate to the timer UI
- The provider listens for `'shot_detected'` message type but timer tab isn't connected

**Files Involved:**
- `ssa_app/lib/widgets/shot_timer_tab.dart`
- `ssa_app/lib/providers/sensor_data_provider.dart`
- `ssa_app/lib/isolates/sensor_data_isolate.dart`

**Status:** OPEN - needs implementation

---

## [Tanggal] - Scoring Algorithm Divergence

**Error/Problem:**
Python app uses "Hardcore" scoring (Travel=1200, Jerk=5000 penalties) while Flutter uses MantisX-style soft curve (sqrt-based penalties). Same database, different scores.

**Root Cause:**
Different scoring algorithms were implemented independently in each platform.

**Solution:**
- No immediate fix needed - both are valid scoring methods
- Consider unifying to one algorithm in future

**Files Involved:**
- `Python Code (SSA)/STASYS.py`
- `ssa_app/lib/models/shot.dart`

**Status:** KNOWN - design decision, not a bug

---

## [Tanggal] - STASY_V4.py Duplicate

**Error/Problem:**
`STASY_V4.py` is a near-duplicate of `STASYS.py` with different defaults (COM4, PIEZO 400/2500). Creates confusion about which is canonical.

**Root Cause:**
Fork was created for different hardware config but not merged back.

**Solution:**
- Decide: merge differences into STASYS.py with configurable defaults, or delete STASY_V4.py

**Files Involved:**
- `Python Code (SSA)/STASY_V4.py`

**Status:** OPEN - needs decision

---

## [2026-04-05] - CRC Scope Mismatch (DATA_RAW_SAMPLE)

**Error/Problem:**
DATA_RAW_SAMPLE (0x20) packets failed CRC verification. AUTH packets (0x14, 0x15, 0x10) passed.

**Root Cause:**
Firmware `encodePacket()` in `protocol.cpp` computed CRC over `TYPE(1)+LEN_LO(1)+payload` = `2+len` bytes.
Flutter parser computed CRC over `TYPE(1)+LEN_LO(1)+LEN_HI(1)+payload` = `3+len` bytes.
The LEN field is 2 bytes (LE), but firmware only included the low byte.

**Solution:**
`protocol.cpp` line 67: changed `crc16_ccitt(&outBuffer[2], 2 + len)` → `crc16_ccitt(&outBuffer[2], 3 + len)`
Also added `EVT_SENSOR_HEALTH (0x13)` handler in Flutter (spammed "Unknown packet type").

**Files Involved:**
- `Firmware_STSYS32/src/protocol.cpp` (encodePacket CRC scope)
- `ssa_app/lib/providers/bluetooth_provider.dart` (added 0x13 handler)

**Status:** RESOLVED

---

## [Tanggal] - Battery Monitoring Not Surfaced

**Error/Problem:**
Firmware sends battery percentage in byte 28 of each packet, but Flutter UI doesn't consistently display or track battery level.

**Root Cause:**
Battery field is parsed but not used in any UI widget or notification.

**Solution:**
- Add battery level indicator to status bar / connection screen
- Add low battery warning

**Files Involved:**
- `ssa_app/lib/providers/bluetooth_provider.dart` (parses battery)
- `ssa_app/lib/screens/` (UI files need battery widget)

**Status:** OPEN - enhancement needed

---

## Template (copy-paste untuk bug baru)

```
## [Tanggal] - [Short Bug Title]

**Error/Problem:**
> Deskripsi error

**Root Cause:**
> Kenapa terjadi

**Solution:**
> Cara fix-nya

**Files Involved:**
- `path/to/file.dart`
- `path/to/file.ino`

**Status:** [OPEN / RESOLVED / IN-PROGRESS]

---
```
