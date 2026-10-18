# STASYS Firmware Hardware / Schematic Guide

This guide documents the hardware connections implied by the active ESP32 firmware. It is a firmware-derived reference, **not a complete or verified electrical schematic**. Confirm module pin labels, supply requirements, analog front-end components, and battery-divider values against the actual hardware before powering or fabricating a board.

## Controller

- **Target:** ESP32 Classic, PlatformIO `esp32dev` / ESP32 Dev Module.
- Firmware GPIO numbers below refer to the ESP32 module pins, not a particular DevKit header position. DevKit header layouts vary; use the board's pinout to map GPIO numbers to header labels.
- GPIO35 and GPIO39 are input-only on the classic ESP32 and are used as ADC inputs here.

## Pin and signal assignments

| Function | ESP32 GPIO | ESP32 ADC channel | Connects to | Firmware details |
|---|---:|---|---|---|
| I²C SDA | GPIO21 | — | MPU and magnetometer SDA | I²C controller 0, configured for 400 kHz. |
| I²C SCL | GPIO22 | — | MPU and magnetometer SCL | I²C controller 0, configured for 400 kHz. |
| Battery voltage sense | GPIO39 | ADC1 channel 3 | Battery divider output | 12-bit ADC, 11 dB attenuation; firmware applies a divider ratio of 2.0. |
| Piezo analog input | GPIO35 | ADC1 channel 7 | Piezo signal-conditioning output | 12-bit ADC, 11 dB attenuation. |
| Ground | GND | — | ESP32, sensors, analog front-end, and battery-divider ground | Common ground is required for the analog and I²C signals. |
| Sensor supply | Not specified | — | MPU and magnetometer modules | The firmware does not identify module supply voltage or regulator. Verify the module specifications and ESP32 logic-level compatibility. |

The ADC channel-to-GPIO mapping is for the ESP32 target configured by this project. The firmware initializes ADC1 and enables both channels with the same attenuation and bit width.

## I²C devices

Wire the I²C devices in parallel to GPIO21 (SDA), GPIO22 (SCL), and a compatible common ground. The firmware scans the bus at startup and uses these addresses:

| Device | 7-bit I²C address | Firmware behavior |
|---|---:|---|
| MPU motion sensor | `0x68` | Required at startup; firmware reads its WHO_AM_I register and expects `0x68`. |
| QMC5883P-compatible magnetometer | `0x2C` | Preferred magnetometer. Firmware checks chip ID `0x80` at register `0x00` and configures normal measurement mode. |
| HMC5883L magnetometer | `0x1E` | Compatibility fallback. Used only if the QMC device is not available and the expected `H43` identity is read. |

The known GY-273 module in this project is labeled **HMC5883L** but was verified to contain a QMC5883P-compatible sensor at `0x2C`. Do not infer the chip from the breakout-board label alone. The firmware can probe both magnetometer addresses; normally only the installed compatible device responds.

### I²C electrical notes

- SDA and SCL need pull-ups to a voltage safe for ESP32 GPIOs. The firmware enables the ESP-IDF I²C driver's internal pull-ups, but these may not be sufficient for a reliable physical bus; check the breakout boards and add suitable external pull-ups if needed.
- Ensure there are no conflicting pull-ups to 5 V. ESP32 GPIOs are not 5 V tolerant.
- Keep the bus wiring short and connect sensor grounds to ESP32 ground.
- The code specifies 400 kHz operation; reduce the bus speed if the actual wiring or modules are unreliable.

## Analog inputs

### Battery voltage sense — GPIO39 / ADC1_CH3

The firmware expects a battery measurement spanning approximately **3.0–4.2 V** after converting the ADC reading back through a configured divider ratio of **2.0**. This implies a nominal 2:1 voltage divider: the ADC input sees about half the battery voltage (up to about 2.1 V at 4.2 V battery voltage).

```text
Battery + ── R_TOP ──┬── GPIO39 (ADC1_CH3)
                     ├── optional ADC filter capacitor to GND
                     R_BOTTOM
                     │
Battery − ───────────┴── ESP32 GND
```

- `R_TOP` and `R_BOTTOM` values are **not specified by the firmware**. Choose them for the required divider ratio, ADC source impedance, power consumption, and settling time; verify ADC accuracy with the assembled hardware.
- Keep the maximum possible ADC-pin voltage within the ESP32's electrical limits, including battery charging voltage and transients. Do not connect a Li-ion cell directly to GPIO39.
- The firmware's battery percentage mapping clamps to 0% at or below 3.0 V and 100% at or above 4.2 V. The divider ratio constant is in `components/system_config.h`.

### Piezo input — GPIO35 / ADC1_CH7

The firmware samples the analog signal on GPIO35 but does **not** define the piezo sensor, bias network, amplifier, protection, or filter. A piezo element can generate voltage spikes; do not connect an unconditioned piezo element directly to the ESP32 ADC. Design and verify an analog front end that limits the input to the ADC-safe range and provides any required bias, clamping, and filtering.

## Basic wiring checklist

1. Map the GPIO numbers to the correct header pins for the exact ESP32 DevKit revision.
2. Connect GPIO21/GPIO22 to SDA/SCL on the MPU and the installed magnetometer; use compatible pull-ups and logic levels.
3. Connect GPIO39 to the battery-divider midpoint, with battery negative and ESP32 GND common.
4. Connect the piezo front-end output to GPIO35; ensure the front end protects the ADC from both polarities and excessive voltage.
5. Verify module supply and pin order from each module's documentation before connecting power.
6. On startup, use the serial log's I²C scan and magnetometer probe messages to confirm the expected devices respond.

## Source of truth and maintenance

Assignments are defined in `components/system_config.h` (also mirrored at `components/system_config/system_config.h`) and ADC channels / configuration are set in `components/sensors/sensor_hal.cpp`. Keep this guide synchronized if those assignments change. Firmware values describe software expectations; they do not validate the physical circuit or replace component datasheets.
