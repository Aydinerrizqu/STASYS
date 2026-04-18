# STSYS32 — Shooting Stability Sensor Firmware

Firmware for a MantisX-style shooting stability sensor built on the Seeed XIAO nRF52840 Sense.

> **Android developers:** Think of this like an embedded Android project. You have a hardware device, a build system (PlatformIO instead of Gradle), and unit tests that run without the device. The workflow will feel familiar.

---

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/dylemmas/STASYS_SEEEDXIAO.git
cd STASYS_SEEEDXIAO

# 2. Build firmware (analogous to ./gradlew assembleDebug)
pio run -e xiaoblesense

# 3. Flash to device (analogous to adb install)
pio run -e xiaoblesense -t upload

# 4. Run tests (no hardware needed — like running Android unit tests)
pio test -e native
```

---

## Prerequisites

### Software

| Tool | Why | Install |
|---|---|---|
| **VS Code** | Code editor | [code.visualstudio.com](https://code.visualstudio.com) |
| **PlatformIO IDE** | Build system + flash tool (replaces Gradle for embedded) | VS Code: Extensions → search "PlatformIO" |
| **Git** | Version control | Already installed if you've used Android Studio |

### Hardware

- Seeed XIAO nRF52840 Sense board
- USB-C cable
- (Optional) LiPo battery for untethered use

### Windows: Install USB driver

If flashing fails on Windows, you may need the **SEGGER J-Link / CMSIS-DAP driver**. PlatformIO usually installs it automatically, but if you see a device recognition error:

1. Download drivers from [seeedstudio.com](https://wiki.seeedstudio.com/XIAO-nRF52840-Sense)
2. Or install via PlatformIO: `pio pkg install --platform "nordicnrf52"`

---

## Project Structure

Think of this as an Android app with multiple modules:

```
STASYS_SEEEDXIAO/
├── src/                    # Source code (like src/main/java/)
│   ├── main.cpp            # Entry point — setup() and loop()
│   ├── IMU.cpp             # Accelerometer + gyroscope
│   ├── state.cpp           # State machine (IDLE → AIMING → SHOT → ...)
│   ├── PDM.cpp             # Microphone (audio shot detection)
│   ├── power.cpp           # Battery + deep sleep
│   ├── math.cpp            # Quaternion math + stability scoring
│   └── globals.cpp         # Shared variables
├── include/                # Header files (like src/main/include/)
│   ├── config.h            # Compile-time constants (thresholds, etc.)
│   ├── data.h              # Shared structs (IMU samples, BLE packets)
│   └── globals.h           # Forward declarations
├── test/                   # Unit tests (like src/test/java/)
│   ├── test_all.cpp        # 70 tests covering math, shot detection, FSM
│   └── mocks/              # Mock hardware for testing without device
├── platformio.ini          # Build configuration (like build.gradle)
└── CLAUDE.md               # Detailed architecture docs
```

### The two build environments

| Environment | Purpose | Needs hardware? |
|---|---|---|
| `xiaoblesense` | Build + flash firmware to the device | Yes |
| `native` | Run unit tests on your PC | No |

---

## Development Workflow

### 1. Create a feature branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make changes

Edit source files in `src/` and headers in `include/`.

### 3. Run tests (before committing)

```bash
pio test -e native
```

This runs 70 unit tests covering:
- Quaternion math and stability metrics
- Shot detection (accel spike + audio confirmation)
- State machine transitions (IDLE → AIMING → SHOT → ...)
- FSM edge cases and debounce logic

**All tests must pass before pushing.** No test failures allowed.

### 4. Commit and push

```bash
git add .
git commit -m "Your descriptive commit message"
git push origin feature/your-feature-name
```

### 5. Flash updated firmware

After merging to `main` or when testing a branch:

```bash
# Connect the XIAO board via USB
pio run -e xiaoblesense -t upload
```

---

## Key Concepts (Android → Embedded Mapping)

### State Machine

The device cycles through states: `IDLE → AIMING → TRIGGER → SHOT → RECOIL → AIMING`

Think of this as a `StateFlow` in Kotlin, but running on the device instead of the phone.

### BLE Characteristics

The device streams data over Bluetooth Low Energy. If you're building the companion Android app, these are the characteristics to read:

| Characteristic | UUID | Data |
|---|---|---|
| traceChar | `...1214` | Raw 6-DoF IMU data |
| aimTraceChar | `...1215` | Aim deviation (dPitch, dRoll) @ 20Hz |
| scoreChar | `...1216` | Shot precision score |
| stabilityChar | `...1217` | Post-shot stability metrics |
| cmdChar | `...1219` | Commands from app → device |

See `include/data.h` for the full BLE UUID list and packet formats.

### Thresholds (config.h)

Key detection parameters are in `include/config.h`:

```cpp
SHOT_ACCEL_THRESHOLD_G  = 2.5   // pre-filter trigger
SHOT_ACCEL_PEAK_MIN_G   = 3.0   // peak confirmation
SHOT_DEBOUNCE_MS        = 500   // between shots
AIM_SETTLE_SAMPLES      = 20    // ~200ms to lock aim
STABILITY_GOOD_DEG      = 0.3   // RMS → score 100
STABILITY_POOR_DEG      = 2.0   // RMS → score 0
```

---

## Common Tasks

### Monitor serial output

```bash
pio run -e xiaoblesense -t monitor
```

Analogous to `adb logcat` — watch debug output from the device.

### Clean build

```bash
pio run -e xiaoblesense --target clean
pio run -e xiaoblesense
```

### Run only specific tests

Edit `test/test_all.cpp` and run:

```bash
pio test -e native
```

---

## Troubleshooting

### "No device found" when flashing

1. Check USB cable is data-capable (not charge-only)
2. Double-click the reset button on the XIAO to enter bootloader mode
3. Try a different USB port (USB 2.0 ports sometimes work better)
4. On Windows: install the [XIAO drivers](https://wiki.seeedstudio.com/XIAO-nRF52840-Sense)

### Tests fail on native

If `pio test -e native` fails but you haven't touched test files, check:
1. PlatformIO is up to date: `pio upgrade`
2. Dependencies are resolved: `pio pkg install`

### Build errors

If you see linker errors about `imu` or `madgwick`, that's expected — they're external libraries linked via `build_src_flags` in `platformio.ini`. The build is configured correctly.

---

## Next Steps

- Read `CLAUDE.md` for deep architecture documentation
- Read `include/config.h` to understand the detection thresholds
- Browse `test/test_all.cpp` to see how the tests are structured
- If you're building the companion Android app, start with `include/data.h` for the BLE packet formats