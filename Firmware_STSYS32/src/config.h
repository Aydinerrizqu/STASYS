// ============================================================
// config.h — FirmwareConfig, NVS Storage
// ============================================================
#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>
#include <stdbool.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

// ================= CONFIG STRUCT =================
struct FirmwareConfig {
    uint8_t  sample_rate_hz;     // 50, 100, 200
    uint16_t piezo_threshold;    // ADC threshold (default 800)
    uint16_t accel_threshold;    // Jerk threshold raw LSB (default 300)
    uint16_t debounce_ms;        // Min ms between shots (default 200)
    bool     led_enabled;        // LED feedback
    uint8_t  data_mode;          // 0=both, 1=raw-only, 2=events-only
    uint16_t streaming_rate_hz;  // Raw stream rate
    char     device_name[20];    // BT device name
    bool     adaptive_threshold_enabled;  // Phase 1.3 adaptive threshold
};

// ================= EXTERNALS =================
extern SemaphoreHandle_t configMutex;
extern FirmwareConfig g_config;

// ================= DEFAULTS =================
#define DEFAULT_SAMPLE_RATE       100
#define DEFAULT_PIEZO_THRESHOLD   800
#define DEFAULT_ACCEL_THRESHOLD   300
#define DEFAULT_DEBOUNCE_MS       200
#define DEFAULT_LED_ENABLED      true
#define DEFAULT_DATA_MODE         0
#define DEFAULT_STREAMING_RATE    100
#define DEFAULT_DEVICE_NAME       "STASYS"

// ================= FUNCTIONS =================
void  initConfig();
void  loadConfig(FirmwareConfig* cfg);
bool  saveConfig(const FirmwareConfig* cfg);
void  updateConfig(const FirmwareConfig* newCfg);
void  getConfigCopy(FirmwareConfig* outCfg);

#endif  // CONFIG_H
