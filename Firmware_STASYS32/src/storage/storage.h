#ifndef STORAGE_H
#define STORAGE_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define FIRMWARE_VERSION "1.3.0"
#define DEVICE_NAME_MAX_LEN 32
#define VOLTAGE_DIVIDER_RATIO 2.0f
#define DEFAULT_SECRET_KEY "12ebaf10h12fa9123z21sti"

typedef struct {
    char deviceName[DEVICE_NAME_MAX_LEN];
    float accelOffset[3];
    float gyroOffset[3];
    uint16_t sampleRateHz;
    uint8_t btTxPower;
    uint8_t sessionTimeoutMin;
    uint8_t padding[6];
} DeviceConfig;

typedef struct {
    uint32_t totalOperatingSeconds;
    uint32_t deepSleepCount;
    uint32_t resetCount;
    uint32_t lastBatteryPct;
    uint32_t lastResetReason;
} DeviceStats;

bool storageInit(void);
void storageLoadConfig(DeviceConfig* cfg);
bool storageSaveConfig(const DeviceConfig* cfg);
void storageLoadStats(DeviceStats* stats);
bool storageSaveStats(const DeviceStats* stats);
void storageLogReset(uint32_t resetReason);
void storageIncrementDeepSleepCount(void);
void storageAddOperatingTime(uint32_t seconds);
bool storageSaveSecretKey(const char* key);
bool storageLoadSecretKey(char* outKey, size_t maxLen);
bool storageFactoryReset(void);
bool storageLoadLinkKey(uint8_t* outKey, uint8_t* outAddr, size_t* outAddrLen);
bool storageSaveLinkKey(const uint8_t* key, size_t keyLen, const uint8_t* addr, size_t addrLen);
bool storageHasLinkKey(void);
bool storageIsInitialized(void);
bool storageSetInitialized(void);
bool storageGetFirmwareVersion(char* outVersion, size_t maxLen);
bool storageSetFirmwareVersion(const char* version);

#endif  // STORAGE_H