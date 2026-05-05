#ifndef OTA_H
#define OTA_H

#include <stdint.h>
#include <stdbool.h>

#define OTA_WIFI_SSID     "STASYS-OTA"
#define OTA_WIFI_PASSWORD "stasys_ota_update"
#define OTA_CHECK_URL     "https://api.stasys.local/firmware/version"
#define OTA_FIRMWARE_URL  "https://api.stasys.local/firmware/stasys_one.bin"
#define OTA_CHECK_INTERVAL_HOURS  24

typedef enum {
    OTA_STATE_IDLE,
    OTA_STATE_CHECKING,
    OTA_STATE_DOWNLOADING,
    OTA_STATE_VERIFYING,
    OTA_STATE_APPLYING,
    OTA_STATE_SUCCESS,
    OTA_STATE_FAILED
} OtaState_t;

typedef struct {
    OtaState_t state;
    uint8_t progressPct;
    char currentVersion[16];
    char latestVersion[16];
    char errorMsg[64];
    uint32_t lastCheckTimestamp;
} OtaStatus_t;

void otaInit(void);
void otaTriggerCheck(void);
void otaGetStatus(OtaStatus_t* outStatus);
bool otaIsUpdating(void);
const char* otaGetCurrentVersion(void);

#endif