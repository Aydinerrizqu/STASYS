// ============================================================
// config.cpp — FirmwareConfig, NVS Storage
// ============================================================
#include "config.h"
#include <Arduino.h>
#include <Preferences.h>

SemaphoreHandle_t configMutex = NULL;
FirmwareConfig g_config;

static const char* NVS_NAMESPACE = "stsys_cfg";

void initConfig() {
    if (configMutex == NULL) {
        configMutex = xSemaphoreCreateMutex();
    }

    FirmwareConfig defaults;
    memset(&defaults, 0, sizeof(defaults));
    defaults.sample_rate_hz = DEFAULT_SAMPLE_RATE;
    defaults.piezo_threshold = DEFAULT_PIEZO_THRESHOLD;
    defaults.accel_threshold = DEFAULT_ACCEL_THRESHOLD;
    defaults.debounce_ms = DEFAULT_DEBOUNCE_MS;
    defaults.led_enabled = DEFAULT_LED_ENABLED;
    defaults.data_mode = DEFAULT_DATA_MODE;
    defaults.streaming_rate_hz = DEFAULT_STREAMING_RATE;
    strncpy(defaults.device_name, DEFAULT_DEVICE_NAME, sizeof(defaults.device_name) - 1);
    defaults.adaptive_threshold_enabled = false;

    loadConfig(&g_config);

    // If NVS was empty, use defaults
    if (g_config.sample_rate_hz == 0) {
        memcpy(&g_config, &defaults, sizeof(FirmwareConfig));
        saveConfig(&g_config);
        Serial.println("[CONFIG] Using defaults (NVS was empty)");
    }

    Serial.printf("[CONFIG] Loaded: sample_rate=%d, piezo_thresh=%d, accel_thresh=%d\n",
                   g_config.sample_rate_hz, g_config.piezo_threshold, g_config.accel_threshold);
}

void loadConfig(FirmwareConfig* cfg) {
    Preferences prefs;
    if (prefs.begin(NVS_NAMESPACE, true)) {
        cfg->sample_rate_hz = prefs.getUChar("sr", DEFAULT_SAMPLE_RATE);
        cfg->piezo_threshold = prefs.getUShort("pt", DEFAULT_PIEZO_THRESHOLD);
        cfg->accel_threshold = prefs.getUShort("at", DEFAULT_ACCEL_THRESHOLD);
        cfg->debounce_ms = prefs.getUShort("db", DEFAULT_DEBOUNCE_MS);
        cfg->led_enabled = prefs.getBool("led", DEFAULT_LED_ENABLED);
        cfg->data_mode = prefs.getUChar("dm", DEFAULT_DATA_MODE);
        cfg->streaming_rate_hz = prefs.getUShort("str", DEFAULT_STREAMING_RATE);
        cfg->adaptive_threshold_enabled = prefs.getBool("adap", false);
        prefs.getString("name", cfg->device_name, sizeof(cfg->device_name) - 1);
        cfg->device_name[sizeof(cfg->device_name) - 1] = '\0';
        prefs.end();
    } else {
        memset(cfg, 0, sizeof(FirmwareConfig));
    }
}

bool saveConfig(const FirmwareConfig* cfg) {
    Preferences prefs;
    if (!prefs.begin(NVS_NAMESPACE, false)) {
        return false;
    }
    prefs.putUChar("sr", cfg->sample_rate_hz);
    prefs.putUShort("pt", cfg->piezo_threshold);
    prefs.putUShort("at", cfg->accel_threshold);
    prefs.putUShort("db", cfg->debounce_ms);
    prefs.putBool("led", cfg->led_enabled);
    prefs.putUChar("dm", cfg->data_mode);
    prefs.putUShort("str", cfg->streaming_rate_hz);
    prefs.putBool("adap", cfg->adaptive_threshold_enabled);
    prefs.putString("name", cfg->device_name);
    prefs.end();
    Serial.println("[CONFIG] Saved to NVS");
    return true;
}

void updateConfig(const FirmwareConfig* newCfg) {
    if (configMutex != NULL) {
        xSemaphoreTake(configMutex, portMAX_DELAY);
    }
    memcpy(&g_config, newCfg, sizeof(FirmwareConfig));
    if (configMutex != NULL) {
        xSemaphoreGive(configMutex);
    }
    saveConfig(newCfg);
}

void getConfigCopy(FirmwareConfig* outCfg) {
    if (configMutex != NULL) {
        xSemaphoreTake(configMutex, portMAX_DELAY);
    }
    memcpy(outCfg, &g_config, sizeof(FirmwareConfig));
    if (configMutex != NULL) {
        xSemaphoreGive(configMutex);
    }
}
