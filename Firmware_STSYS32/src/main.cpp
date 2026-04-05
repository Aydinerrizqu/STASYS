// ============================================================
// main.cpp — FreeRTOS Tasks + Command Dispatch
// ============================================================
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_task_wdt.h>
#include <esp_timer.h>
#include <nvs_flash.h>
#include <esp_system.h>
#include <esp_efuse.h>

// Core headers
#include "protocol.h"
#include "sensor.h"
extern uint8_t s_consecutiveErrors;
#include "config.h"
#include "session.h"
#include "shot_detector.h"
#include "security.h"
#include "bluetooth.h"
#include "battery.h"
#include "led.h"

// ================= TASK STACK SIZES =================
#define SENSOR_TASK_STACK    4096
#define DETECTOR_TASK_STACK 4096
#define STREAM_TASK_STACK   2048
#define BATTERY_TASK_STACK  1024
#define RECOVERY_TASK_STACK 2048

#define BATTERY_INTERVAL_MS 30000UL

// ================= QUEUES =================
QueueHandle_t sampleQueue    = NULL;
QueueHandle_t shotEventQueue = NULL;
QueueHandle_t streamQueue    = NULL;

// ================= STATS =================
static uint32_t s_sampleCounter = 0;
static uint32_t s_droppedSamples = 0;
static uint32_t s_shotsDetected = 0;
static uint32_t s_lastBatteryUpdate = 0;
static uint32_t s_lastActivityTime = 0;
static bool s_sleepScheduled = false;
static uint32_t s_lastHeartbeat_ms = 0;
static const uint32_t HEARTBEAT_INTERVAL_MS = 5000;

#define IDLE_TIMEOUT_MS (5UL * 60 * 1000)

// ================= POWER MANAGEMENT =================
static void recordActivity() {
    s_lastActivityTime = millis();
    s_sleepScheduled = false;
}

static void checkIdleSleep() {
    uint32_t now = millis();
    if (g_btConnected) return;
    if (getSessionState() == SessionState::STREAMING) return;

    if (!s_sleepScheduled) {
        if (now - s_lastActivityTime > IDLE_TIMEOUT_MS) {
            Serial.println("[PWR] Idle timeout reached, entering light sleep...");
            s_sleepScheduled = true;
            esp_sleep_enable_timer_wakeup(10 * 1000000ULL);
            esp_light_sleep_start();
            s_sleepScheduled = false;
            recordActivity();
            Serial.println("[PWR] Woke from light sleep");
        }
    }
}

// ================= FIRMWARE VERSION =================
#define BUILD_VERSION_MAJOR 3
#define BUILD_VERSION_MINOR 1
#define BUILD_VERSION_PATCH 0
#define BUILD_VERSION ((BUILD_VERSION_MAJOR << 16) | (BUILD_VERSION_MINOR << 8) | BUILD_VERSION_PATCH)
#define BUILD_TIMESTAMP 0

// ================= RECOVERY TASK (Core 1) =================
void recoveryTask(void* param) {
    (void)param;
    Serial.println("[RECOVERY] Task started");
    esp_task_wdt_add(NULL);

    for (;;) {
        esp_task_wdt_reset();
        if (recoveryQueue != NULL) {
            bool signal;
            if (xQueueReceive(recoveryQueue, &signal, pdMS_TO_TICKS(1000)) == pdTRUE) {
                Serial.println("[RECOVERY] I2C error detected, attempting recovery...");
                recoverI2CBus();
                s_consecutiveErrors = 0;
            }
        } else {
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
    }
}

// ================= SENSOR TASK (Core 1, High Priority) =================
#define OVERSAMPLE_LOOPS 10  // 1kHz reads → 100Hz output
void sensorTask(void* param) {
    (void)param;
    Serial.println("[SENSOR] Task started");
    esp_task_wdt_add(NULL);

    SensorSample sample;

    for (;;) {
        if (dataReadySem != NULL && xSemaphoreTake(dataReadySem, pdMS_TO_TICKS(5)) == pdTRUE) {
            if (readSensorBurst(&sample)) {
                if (sampleQueue != NULL) {
                    if (xQueueSendToBack(sampleQueue, &sample, 0) != pdTRUE) {
                        s_droppedSamples++;
                    }
                }
                if (streamQueue != NULL) {
                    xQueueSendToBack(streamQueue, &sample, 0);
                }
                s_sampleCounter++;
            }
        } else {
            // Polling fallback
            if (readSensorBurst(&sample)) {
                if (sampleQueue != NULL) xQueueSendToBack(sampleQueue, &sample, 0);
                if (streamQueue != NULL) xQueueSendToBack(streamQueue, &sample, 0);
                s_sampleCounter++;
            }
        }
        esp_task_wdt_reset();
    }
}

// ================= SHOT DETECTOR TASK (Core 1) =================
void shotDetectorTask(void* param) {
    (void)param;
    Serial.println("[DETECTOR] Task started");
    esp_task_wdt_add(NULL);

    SensorSample sample;
    ShotEvent event;
    DetectorConfig cfg;
    uint32_t configRefreshCounter = 0;

    // Init detector with config
    FirmwareConfig fwCfg;
    getConfigCopy(&fwCfg);
    cfg.piezo_threshold = fwCfg.piezo_threshold;
    cfg.accel_threshold = fwCfg.accel_threshold;
    cfg.debounce_ms = fwCfg.debounce_ms;
    cfg.adaptive_threshold_enabled = fwCfg.adaptive_threshold_enabled;
    updateShotDetectorConfig(&cfg);

    for (;;) {
        if (sampleQueue != NULL && xQueueReceive(sampleQueue, &sample, pdMS_TO_TICKS(10)) == pdTRUE) {
            // Periodically refresh config
            if (++configRefreshCounter >= 100) {
                getConfigCopy(&fwCfg);
                cfg.piezo_threshold = fwCfg.piezo_threshold;
                cfg.accel_threshold = fwCfg.accel_threshold;
                cfg.debounce_ms = fwCfg.debounce_ms;
                cfg.adaptive_threshold_enabled = fwCfg.adaptive_threshold_enabled;
                updateShotDetectorConfig(&cfg);
                configRefreshCounter = 0;
            }

            // Only process if session is active
            if (getSessionState() == SessionState::STREAMING) {
                uint32_t sessionId = g_lastSession.session_id;
                bool shotDetected = processSample(&sample, &event, sessionId);
                if (shotDetected) {
                    s_shotsDetected++;
                    addShotToSession(&event);

                    // Send shot event packet
                    uint8_t buf[MAX_PACKET_SIZE];
                    uint16_t len = encodePacket(PKT_TYPE_EVT_SHOT_DETECTED, &event, sizeof(event), buf);
                    if (txQueue != NULL) {
                        TXItem item;
                        memcpy(item.data, buf, len);
                        item.length = len;
                        xQueueSend(txQueue, &item, 0);
                    }

                    // LED + haptic feedback
                    triggerShotFeedback();

                    if (shotEventQueue != NULL) {
                        xQueueSendToBack(shotEventQueue, &event, 0);
                    }
                }
            }
        }
        vTaskDelay(pdMS_TO_TICKS(1));
        esp_task_wdt_reset();
    }
}

// ================= STREAM TASK (Core 0) — sends raw samples at configured rate =================
void streamTask(void* param) {
    (void)param;
    Serial.println("[STREAM] Task started");
    esp_task_wdt_add(NULL);

    SensorSample sample;
    SensorSample lastSample;
    FirmwareConfig cfg;
    uint32_t lastStreamTime_us = 0;
    uint32_t streamInterval_us = 10000;  // 100Hz default
    uint32_t configRefreshCounter = 0;

    getConfigCopy(&cfg);
    streamInterval_us = 1000000 / cfg.streaming_rate_hz;

    for (;;) {
        uint32_t now = esp_timer_get_time();

        // Refresh config periodically
        if (++configRefreshCounter >= 500) {
            getConfigCopy(&cfg);
            streamInterval_us = 1000000 / cfg.streaming_rate_hz;
            configRefreshCounter = 0;
        }

        // Check data mode
        if (cfg.data_mode == 2) {
            // Events-only: drain stream queue
            if (streamQueue != NULL) {
                while (xQueueReceive(streamQueue, &sample, 0) == pdTRUE) {}
            }
            // Debug: only print occasionally to avoid flooding
            static uint32_t s_lastMode2Print = 0;
            if (now - s_lastMode2Print > 5000000) {
                Serial.printf("[STREAM] data_mode=2 (events-only), dropping samples\n");
                s_lastMode2Print = now;
            }
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (getSessionState() == SessionState::STREAMING) {
            if (now - lastStreamTime_us >= streamInterval_us) {
                lastStreamTime_us = now;

                // Drain queue, keep only latest sample
                bool gotSample = false;
                if (streamQueue != NULL) {
                    while (xQueueReceive(streamQueue, &sample, 0) == pdTRUE) {
                        lastSample = sample;
                        gotSample = true;
                    }
                }

                if (gotSample) {
                    // Build PktRawSample (26 bytes)
                    PktRawSample pkt;
                    pkt.sample_counter = s_sampleCounter;
                    pkt.timestamp_us = lastSample.timestamp_us;
                    pkt.accel_x = lastSample.accel_x;
                    pkt.accel_y = lastSample.accel_y;
                    pkt.accel_z = lastSample.accel_z;
                    pkt.gyro_x = lastSample.gyro_x;
                    pkt.gyro_y = lastSample.gyro_y;
                    pkt.gyro_z = lastSample.gyro_z;
                    pkt.piezo = lastSample.piezo;
                    pkt.reserved = lastSample.temperature;

                    uint8_t buf[MAX_PACKET_SIZE];
                    uint16_t len = encodePacket(PKT_TYPE_DATA_RAW_SAMPLE, &pkt, sizeof(pkt), buf);

                    if (txQueue != NULL) {
                        TXItem item;
                        memcpy(item.data, buf, len);
                        item.length = len;
                        xQueueSend(txQueue, &item, 0);
                    }
                }
            }
        } else {
            // Not streaming: drain queue to prevent buildup
            if (streamQueue != NULL) {
                while (xQueueReceive(streamQueue, &sample, 0) == pdTRUE) {}
            }
        }

        vTaskDelay(pdMS_TO_TICKS(1));
        esp_task_wdt_reset();
    }
}

// ================= BATTERY TASK (Core 0) =================
void batteryMonitorTask(void* param) {
    (void)param;
    Serial.println("[BATTERY] Task started");
    esp_task_wdt_add(NULL);

    int lastReportedVal = -1;

    for (;;) {
        updateBattery();
        uint8_t currentVal = getBatteryPercent();
        recordActivity();

        if (lastReportedVal < 0 || abs((int)currentVal - (int)lastReportedVal) >= 2) {
            lastReportedVal = currentVal;
        }

        // Low battery warning
        BatteryStatus st = readBattery();
        if (st.isLow && !st.isCharging) {
            setLEDMode(LEDMode::LOW_BATTERY);
        }

        // Periodic health report
        if (s_sampleCounter > 0 && (s_sampleCounter % 10000 == 0)) {
            Serial.printf("[STATS] samples=%lu dropped=%lu shots=%lu batt=%d%%\n",
                         s_sampleCounter, s_droppedSamples, s_shotsDetected, currentVal);
        }

        vTaskDelay(pdMS_TO_TICKS(BATTERY_INTERVAL_MS / portTICK_PERIOD_MS));
        esp_task_wdt_reset();
    }
}

// ================= BLUETOOTH TASK (Core 0) =================
void bluetoothTask(void* param) {
    (void)param;
    Serial.println("[BT] Task started");
    esp_task_wdt_add(NULL);

    DecodedPacket cmd;

    for (;;) {
        // Check connection state
        bool connected = SerialBT.connected();
        if (connected != g_btConnected) {
            g_btConnected = connected;
            if (connected) {
                Serial.println("[BT] Connected");
                setLEDMode(LEDMode::CONNECTED);
                s_rxLen = 0;

                // Auto-stop session on disconnect
                if (getSessionState() == SessionState::STREAMING) {
                    stopSession();
                    PktSessionStopped pkt;
                    pkt.session_id = g_lastSession.session_id;
                    pkt.duration_ms = g_lastSession.duration_ms;
                    pkt.shot_count = g_lastSession.shot_count;
                    pkt.battery_end = getBatteryPercent();
                    pkt.sensor_health = 0;
                    uint8_t buf[MAX_PACKET_SIZE];
                    uint16_t len = encodePacket(PKT_TYPE_EVT_SESSION_STOPPED, &pkt, sizeof(pkt), buf);
                    if (txQueue != NULL) {
                        TXItem item; memcpy(item.data, buf, len); item.length = len;
                        xQueueSend(txQueue, &item, 0);
                    }
                }
            } else {
                Serial.println("[BT] Disconnected");
                esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE);
                setLEDMode(LEDMode::IDLE);
                s_rxLen = 0;
                s_lastHeartbeat_ms = 0;
            }
        }

        // Heartbeat during active sessions
        if (g_btConnected && getSessionState() == SessionState::STREAMING) {
            uint32_t now = millis();
            if (now - s_lastHeartbeat_ms >= HEARTBEAT_INTERVAL_MS) {
                s_lastHeartbeat_ms = now;
                sendSensorHealthPacket();
                Serial.println("[BT] Heartbeat sent");
            }
        }

        // Read incoming BT data
        int available = SerialBT.available();
        if (available > 0) {
            int toRead = min(available, (int)(sizeof(s_rxBuffer) - s_rxLen));
            if (toRead == 0) {
                s_rxOverflowCount++;
                Serial.printf("[BT] RX overflow #%lu\n", s_rxOverflowCount);
                vTaskDelay(pdMS_TO_TICKS(5));
                continue;
            }
            int bytesRead = SerialBT.readBytes(s_rxBuffer + s_rxLen, toRead);
            if (bytesRead > 0) {
                s_rxLen += bytesRead;

                // Parse through buffer
                uint16_t consumed = 0;
                for (uint16_t i = 0; i < s_rxLen; ) {
                    bool found = false;
                    uint16_t best = 0;

                    for (uint16_t j = 0; j < s_rxLen - i; j++) {
                        if (decodeByte(s_rxBuffer[i + j], &cmd)) {
                            found = true;
                            best = i + j + 1;
                            dispatchCommand(&cmd);
                            break;
                        }
                    }

                    if (found) {
                        consumed = best;
                        memmove(s_rxBuffer, s_rxBuffer + consumed, s_rxLen - consumed);
                        s_rxLen -= consumed;
                        consumed = 0;
                        break;
                    } else {
                        bool foundSync = false;
                        for (uint16_t j = 1; j < s_rxLen - i; j++) {
                            if (s_rxBuffer[i + j] == PKT_SYNC0) {
                                memmove(s_rxBuffer, s_rxBuffer + i + j, s_rxLen - i - j);
                                s_rxLen -= (i + j);
                                foundSync = true;
                                break;
                            }
                        }
                        if (!foundSync) {
                            s_rxLen = 0;
                        }
                        break;
                    }
                }
            }
        }

        // Send outgoing TX queue packets
        TXItem txItem;
        static uint32_t s_debugPktCount = 0;
        while (xQueueReceive(txQueue, &txItem, 0) == pdTRUE) {
            // Debug: print first 3 packets only
            if (s_debugPktCount < 3) {
                Serial.printf("[TX] #%lu len=%u: ", (unsigned long)s_debugPktCount, (unsigned)txItem.length);
                for (uint16_t i = 0; i < txItem.length; i++) {
                    Serial.printf("%02X ", (unsigned)txItem.data[i]);
                }
                Serial.println();
                s_debugPktCount++;
            }
            SerialBT.write(txItem.data, txItem.length);
        }

        vTaskDelay(pdMS_TO_TICKS(1));
        esp_task_wdt_reset();
    }
}

// ================= COMMAND DISPATCH =================
static void sendSessionStartedPacket() {
    PktSessionStarted pkt;
    pkt.session_id = g_lastSession.session_id;
    pkt.timestamp_us = g_lastSession.start_time_us;
    pkt.battery_percent = g_lastSession.battery_start;
    pkt.sensor_health = 0;
    pkt.free_heap = esp_get_free_heap_size();

    uint8_t buf[MAX_PACKET_SIZE];
    uint16_t len = encodePacket(PKT_TYPE_EVT_SESSION_STARTED, &pkt, sizeof(pkt), buf);
    if (txQueue != NULL) {
        TXItem item; memcpy(item.data, buf, len); item.length = len;
        xQueueSend(txQueue, &item, 0);
    }
}

static void sendSessionStoppedPacket() {
    PktSessionStopped pkt;
    pkt.session_id = g_lastSession.session_id;
    pkt.duration_ms = g_lastSession.duration_ms;
    pkt.shot_count = g_lastSession.shot_count;
    pkt.battery_end = getBatteryPercent();
    pkt.sensor_health = 0;

    uint8_t buf[MAX_PACKET_SIZE];
    uint16_t len = encodePacket(PKT_TYPE_EVT_SESSION_STOPPED, &pkt, sizeof(pkt), buf);
    if (txQueue != NULL) {
        TXItem item; memcpy(item.data, buf, len); item.length = len;
        xQueueSend(txQueue, &item, 0);
    }
}

static void sendInfoPacket() {
    SensorHealth health;
    checkSensorHealth(&health);

    PktInfo info;
    info.firmware_version = BUILD_VERSION;
    info.hardware_rev = 1;
    info.build_timestamp = 0;
    info.supported_features = FEATURE_OTA_SUPPORTED | FEATURE_STORAGE_SUPPORTED |
                              FEATURE_ENCRYPTED | FEATURE_AUTH_REQUIRED |
                              FEATURE_PWM_LED | FEATURE_HAPTIC_PWM |
                              FEATURE_COREDUMP;
    info.mpu_whoami = health.mpu_whoami;
    info.reserved[0] = 0;
    info.reserved[1] = 0;

    sendPacket(PKT_TYPE_RSP_INFO, &info, sizeof(info));
}

static void sendConfigPacket() {
    FirmwareConfig cfg;
    getConfigCopy(&cfg);

    uint8_t pkt[50];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = cfg.sample_rate_hz;
    pkt[1] = cfg.piezo_threshold & 0xFF;
    pkt[2] = (cfg.piezo_threshold >> 8) & 0xFF;
    pkt[3] = cfg.accel_threshold & 0xFF;
    pkt[4] = (cfg.accel_threshold >> 8) & 0xFF;
    pkt[5] = cfg.debounce_ms & 0xFF;
    pkt[6] = (cfg.debounce_ms >> 8) & 0xFF;
    pkt[7] = cfg.led_enabled ? 1 : 0;
    pkt[8] = cfg.data_mode;
    pkt[9] = cfg.streaming_rate_hz & 0xFF;
    pkt[10] = (cfg.streaming_rate_hz >> 8) & 0xFF;
    strncpy((char*)&pkt[11], cfg.device_name, 19);

    sendPacket(PKT_TYPE_RSP_CONFIG, pkt, sizeof(pkt));
}

void dispatchCommand(const DecodedPacket* cmd) {
    recordActivity();

    switch (cmd->type) {
        case PKT_TYPE_CMD_AUTH: {
            if (cmd->payload_len >= sizeof(PktAuth)) {
                const PktAuth* auth = (const PktAuth*)cmd->payload;
                if (verifyAuthToken(auth->token, auth->session_id)) {
                    updateBattery();
                    uint8_t batt = getBatteryPercent();

                    // Send EVT_AUTH_SUCCESS (0x15)
                    PktAuthSuccess authSucc;
                    authSucc.session_id = auth->session_id;
                    uint8_t buf[MAX_PACKET_SIZE];
                    uint16_t len = encodePacket(PKT_TYPE_EVT_AUTH_SUCCESS, &authSucc, sizeof(authSucc), buf);
                    if (txQueue != NULL) {
                        TXItem item; memcpy(item.data, buf, len); item.length = len;
                        xQueueSend(txQueue, &item, 0);
                    }
                    Serial.printf("[BT] AUTH OK for session %lu\n", (unsigned long)auth->session_id);

                    // Auto-start session after successful auth
                    SessionState state = startSession(auth->session_id, batt);
                    if (state == SessionState::STREAMING) {
                        sendSessionStartedPacket();
                        Serial.printf("[BT] Session %lu started (streaming)\n", (unsigned long)auth->session_id);
                        setLEDMode(LEDMode::STREAMING);
                    }
                } else {
                    sendError(0x05, "Auth failed");
                }
            }
            break;
        }

        case PKT_TYPE_CMD_START_SESSION: {
            // Send AUTH_CHALLENGE. Session starts AFTER CMD_AUTH is received.
            uint32_t sessionId = (uint32_t)(esp_timer_get_time() & 0x7FFFFFFF);

            uint8_t challenge[16];
            generateChallenge(challenge);

            PktAuthChallenge authChal;
            authChal.session_id = sessionId;
            memcpy(authChal.challenge, challenge, 16);
            uint8_t buf[MAX_PACKET_SIZE];
            uint16_t len = encodePacket(PKT_TYPE_EVT_AUTH_CHALLENGE, &authChal, sizeof(authChal), buf);
            if (txQueue != NULL) {
                TXItem item; memcpy(item.data, buf, len); item.length = len;
                xQueueSend(txQueue, &item, 0);
            }
            Serial.printf("[BT] Sent AUTH_CHALLENGE for session %u (waiting for CMD_AUTH)\n", sessionId);
            // NOTE: Session is started when CMD_AUTH is received (see CMD_AUTH handler above)
            (void)sessionId;  // suppress unused warning
            break;
        }

        case PKT_TYPE_CMD_STOP_SESSION: {
            uint16_t lastShotCount = g_lastSession.shot_count;
            SessionState state = stopSession();
            if (state == SessionState::IDLE) {
                setLEDMode(LEDMode::CONNECTED);
                sendSessionStoppedPacket();
                sendAck(PKT_TYPE_CMD_STOP_SESSION, 0);

                // Suggest thresholds
                if (lastShotCount > 0 && g_detectState.shot_peak_count > 0) {
                    uint32_t sum = 0;
                    for (uint8_t i = 0; i < g_detectState.shot_peak_count; i++) {
                        sum += g_detectState.shot_peaks[i];
                    }
                    float mean = (float)sum / g_detectState.shot_peak_count;
                    uint32_t sumSq = 0;
                    for (uint8_t i = 0; i < g_detectState.shot_peak_count; i++) {
                        int32_t d = (int32_t)g_detectState.shot_peaks[i] - (int32_t)(mean + 0.5f);
                        sumSq += (uint32_t)(d * d);
                    }
                    float variance = (float)sumSq / g_detectState.shot_peak_count;
                    float stddev = sqrtf(variance);
                    uint16_t suggested = (uint16_t)(mean - 0.5f * stddev);
                    if (suggested < 100) suggested = 100;
                    Serial.printf("[DETECTOR] Suggest: piezo_threshold=%u (mean=%.0f, stddev=%.1f)\n",
                                 suggested, mean, stddev);
                }
            } else {
                sendError(0x03, "No active session");
            }
            break;
        }

        case PKT_TYPE_CMD_GET_INFO:
            sendInfoPacket();
            break;

        case PKT_TYPE_CMD_GET_CONFIG:
            sendConfigPacket();
            break;

        case PKT_TYPE_CMD_SET_CONFIG:
            if (cmd->payload_len >= 11) {
                FirmwareConfig newCfg;
                memset(&newCfg, 0, sizeof(newCfg));
                newCfg.sample_rate_hz = cmd->payload[0];
                newCfg.piezo_threshold = cmd->payload[1] | ((uint16_t)cmd->payload[2] << 8);
                newCfg.accel_threshold = cmd->payload[3] | ((uint16_t)cmd->payload[4] << 8);
                newCfg.debounce_ms = cmd->payload[5] | ((uint16_t)cmd->payload[6] << 8);
                newCfg.led_enabled = cmd->payload[7] != 0;
                newCfg.data_mode = cmd->payload[8];
                newCfg.streaming_rate_hz = cmd->payload[9] | ((uint16_t)cmd->payload[10] << 8);
                strncpy(newCfg.device_name, (char*)&cmd->payload[11], sizeof(newCfg.device_name) - 1);
                updateConfig(&newCfg);
                sendConfigPacket();
                sendAck(PKT_TYPE_CMD_SET_CONFIG, 0);
            }
            break;

        case PKT_TYPE_CMD_CALIBRATE_START:
            sendAck(PKT_TYPE_CMD_CALIBRATE_START, 0);
            Serial.println("[BT] Starting user calibration...");
            runUserCalibration();
            break;

        case PKT_TYPE_CMD_GET_SHOT_STATS: {
            FirmwareConfig cfg;
            getConfigCopy(&cfg);
            PktShotStats stats;
            stats.shot_count = g_detectState.shot_peak_count;
            stats.adaptive_enabled = cfg.adaptive_threshold_enabled ? 1 : 0;
            if (g_detectState.shot_peak_count >= 2) {
                uint32_t sum = 0;
                for (uint8_t i = 0; i < g_detectState.shot_peak_count; i++) {
                    sum += g_detectState.shot_peaks[i];
                }
                float mean = (float)sum / g_detectState.shot_peak_count;
                uint32_t sumSq = 0;
                for (uint8_t i = 0; i < g_detectState.shot_peak_count; i++) {
                    int32_t d = (int32_t)g_detectState.shot_peaks[i] - (int32_t)(mean + 0.5f);
                    sumSq += (uint32_t)(d * d);
                }
                float variance = (float)sumSq / g_detectState.shot_peak_count;
                stats.mean_peak = (uint16_t)(mean + 0.5f);
                stats.stddev_peak = (uint16_t)(sqrtf(variance) + 0.5f);
            } else {
                stats.mean_peak = 0;
                stats.stddev_peak = 0;
            }
            stats.adaptive_threshold = g_detectState.adaptive_threshold;
            sendPacket(PKT_TYPE_RSP_SHOT_STATS, &stats, sizeof(stats));
            break;
        }

        default:
            Serial.printf("[BT] Unknown command: 0x%02X\n", cmd->type);
            sendError(0xFF, "Unknown command");
            break;
    }
}

// ================= NVS INIT =================
static void initNVS() {
    esp_err_t nvs_err = nvs_flash_init();
    if (nvs_err == ESP_ERR_NVS_NO_FREE_PAGES ||
        nvs_err == ESP_ERR_INVALID_STATE) {
        nvs_flash_erase();
        nvs_err = nvs_flash_init();
    }
    if (nvs_err == ESP_OK) {
        Serial.println("[MAIN] NVS: initialized");
    } else {
        Serial.printf("[MAIN] NVS: init failed (%d)\n", nvs_err);
    }
}

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.printf("\n\n=== STASYS ESP32 v%d.%d.%d ===\n",
                 BUILD_VERSION_MAJOR, BUILD_VERSION_MINOR, BUILD_VERSION_PATCH);
    Serial.println("[MAIN] Initializing...");

    initNVS();
    initConfig();

    // Create semaphore
    if (dataReadySem == NULL) {
        dataReadySem = xSemaphoreCreateBinary();
    }

    // Scan I2C
    scanI2CBus();

    // Init sensor
    bool sensorOk = initMPU6050();
    if (!sensorOk) {
        Serial.println("[MAIN] WARNING: MPU6050 not detected — running in degraded mode");
    }

    // Calibration
    CalibrationData cal;
    loadCalibrationData(&cal);
    if (!cal.is_calibrated && !cal.factory_calibrated) {
        Serial.println("[MAIN] No calibration data — running factory calibration...");
        runFactoryCalibration();
    }

    // Battery + LED
    initBattery();
    initLED();
    Serial.printf("[MAIN] Battery: %d%%\n", getBatteryPercent());

    // Bluetooth
    FirmwareConfig cfg;
    getConfigCopy(&cfg);

    uint64_t chipid = ESP.getEfuseMac();
    char deviceName[30];
    sprintf(deviceName, "STASYS-V2-%04X", (uint16_t)(chipid >> 32));
    initBluetooth(deviceName);

    // Create queues
    sampleQueue = xQueueCreate(64, sizeof(SensorSample));
    shotEventQueue = xQueueCreate(32, sizeof(ShotEvent));
    streamQueue = xQueueCreate(64, sizeof(SensorSample));

    // Init shot detector
    initShotDetector();

    // Watchdog
    esp_task_wdt_init(60, true);

    // Create tasks
    BaseType_t res;
    res = xTaskCreatePinnedToCore(recoveryTask, "RecoveryTask", RECOVERY_TASK_STACK, NULL, 2, NULL, 1);
    Serial.printf("[MAIN] RecoveryTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(sensorTask, "SensorTask", SENSOR_TASK_STACK, NULL, 3, NULL, 1);
    Serial.printf("[MAIN] SensorTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(shotDetectorTask, "ShotDetector", DETECTOR_TASK_STACK, NULL, 2, NULL, 1);
    Serial.printf("[MAIN] ShotDetectorTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(streamTask, "StreamTask", STREAM_TASK_STACK, NULL, 1, NULL, 0);
    Serial.printf("[MAIN] StreamTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(batteryMonitorTask, "BatteryMonitor", BATTERY_TASK_STACK, NULL, 1, NULL, 0);
    Serial.printf("[MAIN] BatteryMonitorTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(bluetoothTask, "BluetoothTask", 4096, NULL, 2, NULL, 0);
    Serial.printf("[MAIN] BluetoothTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    res = xTaskCreatePinnedToCore(ledTask, "LEDTask", 2048, NULL, 1, NULL, 0);
    Serial.printf("[MAIN] LEDTask: %s\n", (res == pdPASS) ? "OK" : "FAIL");

    Serial.println("[MAIN] Setup complete — ready for connections");
    Serial.printf("[MAIN] Heap free: %lu bytes\n", esp_get_free_heap_size());
    Serial.printf("[PROTO] sizeof(PktRawSample)=%u (expected 24)\n", (unsigned)sizeof(PktRawSample));

    // CRC test: verify CRC16-CCITT with known test vector
    const uint8_t test_data[] = {0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39}; // "123456789"
    uint16_t test_crc = crc16_ccitt(test_data, sizeof(test_data));
    Serial.printf("[CRC] Test '123456789' = %04X (expected 29B1)\n", (unsigned)test_crc);

    // DATA_RAW_SAMPLE CRC test
    PktRawSample testPkt;
    memset(&testPkt, 0, sizeof(testPkt));
    testPkt.sample_counter = 0x12345678;
    testPkt.timestamp_us = 0x00000001;
    testPkt.accel_x = 0x0001;
    uint8_t testBuf[64];
    uint16_t testLen = encodePacket(0x20, &testPkt, sizeof(testPkt), testBuf);
    Serial.printf("[CRC] DATA_RAW frame len=%u: ", (unsigned)testLen);
    for (uint16_t i = 0; i < testLen; i++) Serial.printf("%02X ", (unsigned)testBuf[i]);
    Serial.println();
}

void loop() {
    checkIdleSleep();
    vTaskDelay(pdMS_TO_TICKS(1000));
}
