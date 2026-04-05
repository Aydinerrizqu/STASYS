// ============================================================
// ota.cpp — OTA Firmware Update
// ============================================================
#include "ota.h"
#include <Arduino.h>
#include <esp_ota_ops.h>

static const esp_partition_t* s_otaPartition = NULL;
static esp_ota_handle_t s_otaHandle = 0;
static uint32_t s_bytesReceived = 0;
static uint32_t s_totalExpected = 0;
static OTAState s_state = OTAState::IDLE;

bool isOTAInProgress() {
    return s_state == OTAState::RECEIVING || s_state == OTAState::VERIFYING;
}

const esp_partition_t* otaBegin(uint32_t totalSize) {
    const esp_partition_t* update_partition = esp_ota_get_next_update_partition(NULL);
    if (update_partition == NULL) {
        Serial.println("[OTA] No OTA partition found");
        return NULL;
    }

    esp_err_t err = esp_ota_begin(update_partition, totalSize, &s_otaHandle);
    if (err != ESP_OK) {
        Serial.printf("[OTA] esp_ota_begin failed: %d\n", err);
        s_state = OTAState::ERROR;
        return NULL;
    }

    s_otaPartition = update_partition;
    s_bytesReceived = 0;
    s_totalExpected = totalSize;
    s_state = OTAState::RECEIVING;

    Serial.printf("[OTA] Begin: partition=%s size=%lu\n",
                  update_partition->label, (unsigned long)totalSize);
    return update_partition;
}

void otaWrite(const uint8_t* data, uint32_t len) {
    if (s_state != OTAState::RECEIVING) return;
    esp_err_t err = esp_ota_write(s_otaHandle, data, len);
    if (err == ESP_OK) {
        s_bytesReceived += len;
    } else {
        Serial.printf("[OTA] write error: %d\n", err);
    }
}

bool otaEnd() {
    if (s_state != OTAState::RECEIVING) return false;

    s_state = OTAState::VERIFYING;
    esp_err_t err = esp_ota_end(s_otaHandle);
    if (err != ESP_OK) {
        Serial.printf("[OTA] verification failed: %d\n", err);
        s_state = OTAState::ERROR;
        return false;
    }

    err = esp_ota_set_boot_partition(s_otaPartition);
    if (err != ESP_OK) {
        Serial.printf("[OTA] set boot partition failed: %d\n", err);
        s_state = OTAState::ERROR;
        return false;
    }

    s_state = OTAState::COMPLETE;
    Serial.println("[OTA] Update verified and scheduled for boot");
    return true;
}

void otaAbort() {
    if (s_otaHandle != 0) {
        esp_ota_abort(s_otaHandle);
        s_otaHandle = 0;
    }
    s_state = OTAState::IDLE;
    s_bytesReceived = 0;
    Serial.println("[OTA] Aborted");
}

OTAStatus otaGetStatus() {
    OTAStatus st;
    st.state = s_state;
    st.bytes_received = s_bytesReceived;
    st.total_expected = s_totalExpected;
    return st;
}
