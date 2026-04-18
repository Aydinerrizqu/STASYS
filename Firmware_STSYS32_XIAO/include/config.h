#ifndef CONFIG_H
#define CONFIG_H

// =============================================================================
// STSYS32 — Configuration for Seeed XIAO nRF52840 Sense
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// Hardware: Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic + BLE
// =============================================================================

#define FW_VERSION_MAJOR 3
#define FW_VERSION_MINOR 0
#define FW_VERSION_PATCH 0

// =============================================================================
// IMU CONFIGURATION
// =============================================================================
#define IMU_ODR_HZ            100
#define IMU_ACCEL_RANGE_G     16
#define IMU_GYRO_RANGE_DPS    2000
#define IMU_READ_INTERVAL_MS   10   // 1000/100 = 10 ms per sample

// =============================================================================
// PDM MICROPHONE
// =============================================================================
#define PDM_SAMPLE_RATE       16000
#define PDM_CHANNELS          1
#define PDM_BUFFER_SIZE      256

// =============================================================================
// SHOT DETECTION
// =============================================================================
#define SHOT_ACCEL_THRESHOLD_G    2.5f
#define SHOT_ACCEL_PEAK_MIN_G     3.0f   // minimum peak for real shot confirmation
#define SHOT_ACCEL_PEAK_WINDOW_MS 50    // window to find peak after trigger
#define SHOT_AUDIO_THRESHOLD      2000
#define SHOT_WINDOW_MS            15
#define SHOT_DEBOUNCE_MS          500   // prevent double-detection after shot

// =============================================================================
// PRECISION / SCORING
// =============================================================================
#define PISTOL_PRECISION_DEG      0.125f
#define RIFLE_PRECISION_DEG       0.0625f

// =============================================================================
// AIM REFERENCE SETTLING
// =============================================================================
#define AIM_SETTLE_SAMPLES        20    // samples to average for reference (200ms @ 100Hz)
#define AIM_SETTLE_ACCEL_MAX      0.15f  // max accel deviation to consider "settled"
#define AIM_SETTLE_GYRO_MAX       2.0f   // max gyro magnitude to consider "settled"

// =============================================================================
// STABILITY METRICS
// =============================================================================
#define STABILITY_WINDOW_MS       1000
#define STABILITY_SAMPLE_RATE_HZ  100
#define STABILITY_MAX_SAMPLES      100
#define STABILITY_GOOD_DEG         0.3f  // RMS below this = score ~100
#define STABILITY_POOR_DEG         2.0f  // RMS above this = score ~0

// =============================================================================
// PHASE TIMING WINDOWS
// =============================================================================
#define YELLOW_PRE_SHOT_MS        250
#define RED_FOLLOW_THROUGH_MS     500

// =============================================================================
// MOTION / SLEEP
// =============================================================================
#define MOTION_IDLE_TIMEOUT_MS    120000

// =============================================================================
// BATTERY
// =============================================================================
#define BAT_ENABLE_PIN  14
#define BAT_VOLT_PIN    PIN_VBAT
#define LOW_BATTERY_V   3.4f

// =============================================================================
// LED PINS
// =============================================================================
#ifndef LED_RED
  #define LED_RED   11
#endif
#ifndef LED_GREEN
  #define LED_GREEN 13
#endif
#ifndef LED_BLUE
  #define LED_BLUE  12
#endif

// =============================================================================
// BLE
// =============================================================================
#define BLE_MTU               247
#define BLE_CONN_INTERVAL_MIN 24
#define BLE_CONN_INTERVAL_MAX 40
#define GYRO_SCALE            10.0f
#define ACCEL_SCALE           1000.0f

// =============================================================================
// TRACE BUFFER
// =============================================================================
#define TRACE_BUF_SIZE 512

// =============================================================================
// BLE UUIDS
// =============================================================================
#define BLE_SERVICE_UUID    "19B10000-E8F2-537E-4F6C-D104768A1214"
#define BLE_TRACE_CHAR_UUID "19B10001-E8F2-537E-4F6C-D104768A1214"
#define BLE_SCORE_CHAR_UUID "19B10002-E8F2-537E-4F6C-D104768A1214"
#define BLE_DRAW_CHAR_UUID  "19B10003-E8F2-537E-4F6C-D104768A1214"
#define BLE_CMD_CHAR_UUID   "19B10004-E8F2-537E-4F6C-D104768A1214"
#define BLE_AIM_TRACE_CHAR_UUID "19B10005-E8F2-537E-4F6C-D104768A1214"
#define BLE_STABILITY_CHAR_UUID "19B10006-E8F2-537E-4F6C-D104768A1214"

#endif // CONFIG_H
