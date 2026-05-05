#include "storage.h"
#include <Preferences.h>
#include <esp_system.h>
#include <string.h>

static Preferences g_prefs;

static const DeviceConfig DEFAULT_CONFIG = {
    "STASYS-ONE",
    {0.0f, 0.0f, 0.0f},
    {0.0f, 0.0f, 0.0f},
    100,
    1,
    5,
    {0},
};

static const DeviceStats DEFAULT_STATS = {
    0, 0, 0, 0, 0,
};

static bool beginNamespace(const char* ns, bool readOnly) {
    if (!g_prefs.begin(ns, readOnly)) {
        Serial.printf("[Storage] Failed to begin namespace '%s'\n", ns);
        return false;
    }
    return true;
}

bool storageInit(void) {
    g_prefs.end();
    if (!g_prefs.begin("stasys", false)) {
        Serial.println("[Storage] FATAL: Cannot open NVS");
        return false;
    }
    Serial.println("[Storage] NVS initialized");
    return true;
}

bool storageIsInitialized(void) {
    if (!beginNamespace("stasys", true)) return false;
    bool result = g_prefs.isKey("init_ok");
    g_prefs.end();
    return result;
}

bool storageSetInitialized(void) {
    if (!beginNamespace("stasys", false)) return false;
    bool ok = g_prefs.putBool("init_ok", true) > 0;
    g_prefs.end();
    return ok;
}

void storageLoadConfig(DeviceConfig* cfg) {
    if (!beginNamespace("config", true)) {
        *cfg = DEFAULT_CONFIG;
        return;
    }

    if (!g_prefs.isKey("name")) {
        g_prefs.end();
        *cfg = DEFAULT_CONFIG;
        return;
    }

    size_t len = g_prefs.getBytesLength("cfg");
    if (len == sizeof(DeviceConfig)) {
        g_prefs.getBytes("cfg", cfg, sizeof(DeviceConfig));
    } else {
        memset(cfg, 0, sizeof(DeviceConfig));
        g_prefs.getString("name", cfg->deviceName, DEVICE_NAME_MAX_LEN);
        cfg->sampleRateHz = g_prefs.getUChar("rate", DEFAULT_CONFIG.sampleRateHz);
        cfg->btTxPower = g_prefs.getUChar("txpwr", DEFAULT_CONFIG.btTxPower);
        cfg->sessionTimeoutMin = g_prefs.getUShort("stmo", DEFAULT_CONFIG.sessionTimeoutMin);

        if (g_prefs.isKey("axoff")) {
            cfg->accelOffset[0] = g_prefs.getFloat("axoff", 0.0f);
            cfg->accelOffset[1] = g_prefs.getFloat("ayoff", 0.0f);
            cfg->accelOffset[2] = g_prefs.getFloat("azoff", 0.0f);
            cfg->gyroOffset[0]  = g_prefs.getFloat("gxoff", 0.0f);
            cfg->gyroOffset[1]  = g_prefs.getFloat("gyoff", 0.0f);
            cfg->gyroOffset[2]  = g_prefs.getFloat("gzoff", 0.0f);
        }
    }

    g_prefs.end();
}

bool storageSaveConfig(const DeviceConfig* cfg) {
    if (!beginNamespace("config", false)) return false;
    bool ok = g_prefs.putBytes("cfg", cfg, sizeof(DeviceConfig)) == sizeof(DeviceConfig);
    if (!ok) {
        Serial.println("[Storage] Failed to save config");
    }
    g_prefs.end();
    return ok;
}

void storageLoadStats(DeviceStats* stats) {
    if (!beginNamespace("stats", true)) {
        *stats = DEFAULT_STATS;
        return;
    }

    stats->totalOperatingSeconds = g_prefs.getUInt("opsec", 0);
    stats->deepSleepCount = g_prefs.getUInt("dscount", 0);
    stats->resetCount = g_prefs.getUInt("rcount", 0);
    stats->lastBatteryPct = g_prefs.getUInt("batpct", 0);
    stats->lastResetReason = g_prefs.getUInt("rstreason", 0);

    g_prefs.end();
}

bool storageSaveStats(const DeviceStats* stats) {
    if (!beginNamespace("stats", false)) return false;

    g_prefs.putUInt("opsec", stats->totalOperatingSeconds);
    g_prefs.putUInt("dscount", stats->deepSleepCount);
    g_prefs.putUInt("rcount", stats->resetCount);
    g_prefs.putUInt("batpct", stats->lastBatteryPct);
    g_prefs.putUInt("rstreason", stats->lastResetReason);

    g_prefs.end();
    return true;
}

void storageLogReset(uint32_t resetReason) {
    if (!beginNamespace("stats", false)) return;

    uint32_t count = g_prefs.getUInt("rcount", 0) + 1;
    g_prefs.putUInt("rcount", count);
    g_prefs.putUInt("rstreason", resetReason);
    g_prefs.end();
}

void storageIncrementDeepSleepCount(void) {
    if (!beginNamespace("stats", false)) return;
    uint32_t count = g_prefs.getUInt("dscount", 0) + 1;
    g_prefs.putUInt("dscount", count);
    g_prefs.end();
}

void storageAddOperatingTime(uint32_t seconds) {
    if (!beginNamespace("stats", false)) return;
    uint32_t total = g_prefs.getUInt("opsec", 0) + seconds;
    g_prefs.putUInt("opsec", total);
    g_prefs.end();
}

bool storageSaveSecretKey(const char* key) {
    if (!beginNamespace("auth", false)) return false;
    bool ok = g_prefs.putString("seckey", key) > 0;
    g_prefs.end();
    return ok;
}

bool storageLoadSecretKey(char* outKey, size_t maxLen) {
    if (!beginNamespace("auth", true)) return false;
    if (!g_prefs.isKey("seckey")) {
        g_prefs.end();
        return false;
    }
    String key = g_prefs.getString("seckey", "");
    g_prefs.end();

    if (key.length() == 0 || key.length() >= maxLen) return false;
    strncpy(outKey, key.c_str(), maxLen - 1);
    outKey[maxLen - 1] = '\0';
    return true;
}

bool storageFactoryReset(void) {
    g_prefs.end();

    if (!beginNamespace("stasys", false)) return false;
    g_prefs.clear();
    g_prefs.end();

    if (!beginNamespace("config", false)) return false;
    g_prefs.clear();
    g_prefs.end();

    if (!beginNamespace("stats", false)) return false;
    g_prefs.clear();
    g_prefs.end();

    if (!beginNamespace("auth", false)) return false;
    g_prefs.clear();
    g_prefs.end();

    Serial.println("[Storage] Factory reset complete");
    return true;
}

bool storageLoadLinkKey(uint8_t* outKey, uint8_t* outAddr, size_t* outAddrLen) {
    if (!beginNamespace("auth", true)) return false;
    if (!g_prefs.isKey("linkkey")) {
        g_prefs.end();
        return false;
    }

    size_t keyLen = g_prefs.getBytesLength("linkkey");
    if (keyLen < 16) {
        g_prefs.end();
        return false;
    }

    g_prefs.getBytes("linkkey", outKey, keyLen);
    *outAddrLen = 0;
    if (g_prefs.isKey("peeraddr")) {
        *outAddrLen = g_prefs.getBytes("peeraddr", outAddr, 6);
    }

    g_prefs.end();
    return true;
}

bool storageSaveLinkKey(const uint8_t* key, size_t keyLen, const uint8_t* addr, size_t addrLen) {
    if (!beginNamespace("auth", false)) return false;
    bool ok = g_prefs.putBytes("linkkey", key, keyLen) == keyLen;
    if (ok && addrLen > 0) {
        g_prefs.putBytes("peeraddr", addr, addrLen);
    }
    g_prefs.end();
    return ok;
}

bool storageHasLinkKey(void) {
    if (!beginNamespace("auth", true)) return false;
    bool has = g_prefs.isKey("linkkey");
    g_prefs.end();
    return has;
}