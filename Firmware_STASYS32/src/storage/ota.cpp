#include "ota.h"
#include "storage.h"
#ifndef UNIT_TEST
#include <WiFi.h>
#include <esp_https_ota.h>
#include <esp_ota_ops.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <string.h>

#define OTA_TASK_STACK 16384

static TaskHandle_t g_otaTaskHandle = NULL;
static volatile OtaStatus_t g_status = {
    OTA_STATE_IDLE,
    0,
    FIRMWARE_VERSION,
    "",
    "",
    0,
};
static SemaphoreHandle_t g_statusMutex = NULL;
static bool g_updatePending = false;

static esp_err_t validateOtaImage(const esp_partition_t* partition) {
    (void)partition;
    return ESP_OK;
}

static void otaTask(void* parameter) {
    (void)parameter;

    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        {
            if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
            g_status.state = OTA_STATE_CHECKING;
            if (g_statusMutex) xSemaphoreGive(g_statusMutex);
        }

        Serial.println("[OTA] Checking for updates...");

        WiFi.mode(WIFI_STA);
        WiFi.begin(OTA_WIFI_SSID, OTA_WIFI_PASSWORD);

        int attempts = 0;
        while (WiFi.status() != WL_CONNECTED && attempts < 20) {
            vTaskDelay(pdMS_TO_TICKS(500));
            attempts++;
        }

        if (WiFi.status() != WL_CONNECTED) {
            Serial.println("[OTA] WiFi connection failed");
            WiFi.disconnect(true);
            if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
            g_status.state = OTA_STATE_IDLE;
            strncpy((char*)g_status.errorMsg, "WiFi connection failed", sizeof(g_status.errorMsg) - 1);
            if (g_statusMutex) xSemaphoreGive(g_statusMutex);
            vTaskDelay(pdMS_TO_TICKS(60000));
            continue;
        }

        Serial.printf("[OTA] Connected, IP: %s\n", WiFi.localIP().toString().c_str());

        esp_http_client_config_t httpConfig = { };
        httpConfig.url = OTA_FIRMWARE_URL;
        httpConfig.timeout_ms = 30000;
        httpConfig.use_global_ca_store = true;

        esp_https_ota_config_t otaConfig = { };
        otaConfig.http_config = &httpConfig;

        esp_https_ota_handle_t otaHandle = NULL;
        esp_err_t err = esp_https_ota_begin(&otaConfig, &otaHandle);

        if (err != ESP_OK) {
            Serial.printf("[OTA] esp_https_ota_begin failed: %d\n", err);
            WiFi.disconnect(true);
            if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
            g_status.state = OTA_STATE_FAILED;
            snprintf((char*)g_status.errorMsg, sizeof(g_status.errorMsg), "OTA begin failed: 0x%x", err);
            if (g_statusMutex) xSemaphoreGive(g_statusMutex);
            vTaskDelay(pdMS_TO_TICKS(60000));
            continue;
        }

        if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
        g_status.state = OTA_STATE_DOWNLOADING;
        if (g_statusMutex) xSemaphoreGive(g_statusMutex);

        bool downloadComplete = false;
        while (!downloadComplete) {
            err = esp_https_ota_perform(otaHandle);
            if (err == ESP_ERR_HTTPS_OTA_IN_PROGRESS) {
                size_t bytesRead = esp_https_ota_get_image_len_read(otaHandle);
                uint8_t pct = (bytesRead * 100) / (1024 * 1024);
                if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
                g_status.progressPct = pct > 99 ? 99 : pct;
                if (g_statusMutex) xSemaphoreGive(g_statusMutex);
                vTaskDelay(pdMS_TO_TICKS(10));
            } else {
                downloadComplete = true;
            }
        }

        if (esp_https_ota_is_complete_data_received(otaHandle)) {
            if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
            g_status.state = OTA_STATE_VERIFYING;
            if (g_statusMutex) xSemaphoreGive(g_statusMutex);

            const esp_partition_t* running = esp_ota_get_running_partition();
            const esp_partition_t* next = esp_ota_get_next_update_partition(running);
            err = esp_ota_set_boot_partition(next);
            if (err == ESP_OK) {
                if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
                g_status.state = OTA_STATE_APPLYING;
                g_status.progressPct = 100;
                if (g_statusMutex) xSemaphoreGive(g_statusMutex);

                Serial.println("[OTA] Update complete. Rebooting...");
                esp_https_ota_finish(otaHandle);
                WiFi.disconnect(true);
                vTaskDelay(pdMS_TO_TICKS(500));
                esp_restart();
            } else {
                if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
                g_status.state = OTA_STATE_FAILED;
                snprintf((char*)g_status.errorMsg, sizeof(g_status.errorMsg), "Boot partition error: 0x%x", err);
                if (g_statusMutex) xSemaphoreGive(g_statusMutex);
            }
        } else {
            Serial.println("[OTA] Incomplete data received");
            esp_https_ota_abort(otaHandle);
            if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
            g_status.state = OTA_STATE_FAILED;
            strncpy((char*)g_status.errorMsg, "Incomplete data received", sizeof(g_status.errorMsg) - 1);
            if (g_statusMutex) xSemaphoreGive(g_statusMutex);
        }

        WiFi.disconnect(true);
        vTaskDelay(pdMS_TO_TICKS(60000));
    }
}

void otaInit(void) {
    g_statusMutex = xSemaphoreCreateMutex();
    if (g_statusMutex == NULL) {
        Serial.println("[OTA] FATAL: Failed to create mutex");
        return;
    }

    const esp_partition_t* running = esp_ota_get_running_partition();
    const esp_partition_t* boot = esp_ota_get_boot_partition();
    if (running && boot) {
        Serial.printf("[OTA] Running partition: %s at 0x%08X\n",
            running->label, running->address);
    }

    xTaskCreatePinnedToCore(otaTask, "OtaTask", OTA_TASK_STACK, NULL, 1, &g_otaTaskHandle, 0);
    Serial.println("[OTA] Manager initialized");
}

void otaTriggerCheck(void) {
    if (g_otaTaskHandle) {
        xTaskNotifyGive(g_otaTaskHandle);
    }
}

void otaGetStatus(OtaStatus_t* outStatus) {
    if (g_statusMutex) xSemaphoreTake(g_statusMutex, portMAX_DELAY);
    memcpy(outStatus, (const void*)&g_status, sizeof(OtaStatus_t));
    if (g_statusMutex) xSemaphoreGive(g_statusMutex);
}

bool otaIsUpdating(void) {
    OtaStatus_t s;
    otaGetStatus(&s);
    return s.state == OTA_STATE_DOWNLOADING || s.state == OTA_STATE_VERIFYING || s.state == OTA_STATE_APPLYING;
}

const char* otaGetCurrentVersion(void) {
    return FIRMWARE_VERSION;
}

#endif  // UNIT_TEST