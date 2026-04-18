# STASYS — Shooting Stability Sensor

Firmware for a MantisX-style shooting stability sensor on the Seeed XIAO nRF52840 Sense.

> **Status (2026-04-18):** Firmware compiles and uploads via DFU, but LED does not light up after upload. Debugging in progress.

## Hardware

- **Board**: Adafruit Feather nRF52840 Sense (nordicnrf52 platform)
- **IMU**: LSM6DS3 (104Hz, ±16g accel, ±2000 dps gyro)
- **Microphone**: PDM mono @ 16kHz
- **BLE**: Adafruit Bluefruit (Nordic SoftDevice)
- **Power**: LiPo battery with voltage monitoring

## Build & Run

```bash
pio run -e xiaoblesense       # build firmware
pio run -e xiaoblesense -t upload  # flash to device
pio test -e native            # run unit tests (70 tests, no hardware needed)
pio run -e xiaoblesense -t monitor  # serial monitor
```

## Project Structure

```
src/
  main.cpp       — setup(), loop() entry point
  IMU.cpp        — IMU config, Madgwick filter, BLE streaming
  state.cpp      — FSM, shot detection, recoil analysis
  PDM.cpp        — microphone, audio shot detection
  power.cpp      — battery, deep sleep, LEDs
  math.cpp       — quaternions, stability metrics
  globals.cpp     — global variables

include/
  config.h       — all compile-time constants
  data.h         — shared structs (ImuSample, BLE packets, etc.)
  globals.h      — forward declarations, external globals

test/
  test_all.cpp   — 70 unit tests for math, shot detection, FSM, stability
```

## Features

### Live Aim Trace
- When the shooter settles into AIMING state, a reference quaternion is established by averaging 20 calm samples (200ms).
- Each subsequent sample's pitch/roll is expressed as delta from this reference.
- Streamed over BLE characteristic `BLE_AIM_TRACE_CHAR_UUID` at 20Hz.

### Shot Detection
- Combines accel spike (>2.5G pre-filter) + peak confirmation (>3.0G within 50ms) + audio spike confirmation.
- 500ms debounce between shots prevents double-detection.
- Live fire (IMU + audio) vs dry fire (IMU only) detected.

### Stability Score
- During AIMING state, pitch/roll deviation from reference is accumulated into 100-sample buffers.
- At shot finalization, computes: RMS deviation, max deviation, std-dev per axis.
- Mapped to 0-100 score (0.3° RMS = 100, 2.0° RMS = 0).
- Sent via `BLE_STABILITY_CHAR_UUID`.

### State Machine
`IDLE → AIMING → TRIGGER → SHOT → RECOIL → AIMING`

### BLE Characteristics

| Characteristic | UUID | Direction | Purpose |
|---|---|---|---|
| traceChar | `...1214` | Device→App | Raw 6-DoF streaming |
| aimTraceChar | `...1215` | Device→App | Aim deviation (dPitch, dRoll) @ 20Hz |
| scoreChar | `...1216` | Device→App | Shot score (precision deviation) |
| stabilityChar | `...1217` | Device→App | Stability metrics after shot |
| drawChar | `...1218` | Device→App | Draw stroke metrics |
| cmdChar | `...1219` | App→Device | Commands (mode switch, reset, sleep) |

## Configuration

Key thresholds are in `include/config.h`:

```cpp
SHOT_ACCEL_THRESHOLD_G    = 2.5   // pre-filter trigger
SHOT_ACCEL_PEAK_MIN_G    = 3.0   // peak confirmation
SHOT_DEBOUNCE_MS         = 500   // between shots
AIM_SETTLE_SAMPLES       = 20    // ~200ms @ 100Hz
AIM_SETTLE_ACCEL_MAX     = 0.15  // G tolerance
AIM_SETTLE_GYRO_MAX      = 2.0   // dps tolerance
STABILITY_GOOD_DEG        = 0.3   // RMS → score 100
STABILITY_POOR_DEG        = 2.0   // RMS → score 0
```

## Testing

Tests use **Unity** framework and run natively (no hardware). The test suite mirrors the firmware's core logic:

```bash
pio test -e native    # 70 tests
```

New tests should be added in `test/test_all.cpp`. The test file has local implementations of `fsmStep` and `detectShot` for isolation.

## Future Work

- **ML shot detection**: Collect IMU logs from real sessions → train Edge Impulse classifier → replace threshold-based detection (v2)
- **Session history on-device**: Store shots in flash/NVS between sessions
- **BLE firmware update**: OTA DFU over BLE

---

## Known Issues

### LED tidak menyala setelah upload (2026-04-18)
**Symptom:** Firmware berhasil ter-upload via DFU, tapi LED RGB tidak menyala setelah device restart.

**Kemungkinan penyebab:**
1. LED pin conflict - `LED_RED/BLUE/GREEN` di-redefine di `config.h` padahal sudah ada di variant.h
2. IMU initialization failure causing hang/crash
3. Hardware issue

**Steps debugging:**
1. Double-tap RESET → masuk DFU mode
2. Upload firmware dengan `pio run -e xiaoblesense -t upload --upload-port COM14`
3. Double-tap RESET lagi, langsung buka serial monitor:
   ```bash
   pio device monitor -p COM14 -b 115200
   ```
4. Check output - harusnya ada:
   - `[STSYS32] Booting v3.0.0...`
   - `[STSYS32-IMU] Configured: 104Hz...`
   - `[STSYS32-IMU-RAW] #1 ax=... ay=... az=...` (first 10 samples)
   - `[STSYS32-BLE] Advertising. GATT service live.`
5. Jika IMU values ~0.00 → IMU initialization gagal
6. Jika serial output kosong → firmware crash saat boot

**Fix LED pin conflict (pending):**
```cpp
// config.h - hapus duplicate definitions karena sudah ada di variant.h feather_nrf52840_sense
#ifndef LED_RED
  #define LED_RED   PIN_LED1  // atau 11
#endif
#ifndef LED_GREEN
  #define LED_GREEN 13
#endif
#ifndef LED_BLUE
  #define LED_BLUE  PIN_LED2  // atau 12
#endif
```
