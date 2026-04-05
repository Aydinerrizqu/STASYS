// ============================================================
// ota.h — OTA Firmware Update
// ============================================================
#ifndef OTA_H
#define OTA_H

#include <stdint.h>
#include <stdbool.h>
#include <esp_ota_ops.h>

enum class OTAState { IDLE, RECEIVING, VERIFYING, COMPLETE, ERROR };

struct OTAStatus {
    OTAState state;
    uint32_t bytes_received;
    uint32_t total_expected;
};

bool     isOTAInProgress();
const esp_partition_t* otaBegin(uint32_t totalSize);
void     otaWrite(const uint8_t* data, uint32_t len);
bool     otaEnd();
void     otaAbort();
OTAStatus otaGetStatus();

#endif  // OTA_H
