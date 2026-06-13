#include "bt_ota.h"
#include "storage/storage.h"
#include "storage/status_led.h"
#include <Arduino.h>
#include <BluetoothSerial.h>
#ifndef UNIT_TEST
#include <esp_ota_ops.h>
#include <esp_err.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include <mbedtls/sha256.h>
#include <string.h>

extern BluetoothSerial SerialBT;
extern volatile bool isAuthenticated;

#define BT_OTA_TASK_STACK  30720
#define BT_OTA_WRITE_STACK  8192
#define BT_OTA_TIMEOUT_MS   60000
#define BT_OTA_LINE_MAX     256

// Static state
static TaskHandle_t     g_btOtaTaskHandle = NULL;
static TaskHandle_t     g_btOtaWriteTaskHandle = NULL;
static volatile BtOtaState_t g_state = BT_OTA_IDLE;
static esp_ota_handle_t g_otaHandle = 0;
static volatile uint32_t g_totalReceived = 0;
static volatile uint32_t g_expectedSize  = 0;
static volatile uint32_t g_lastActivityMs = 0;
static char              g_lineBuf[BT_OTA_LINE_MAX];
static size_t            g_linePos = 0;

// SHA256 context for on-the-fly hashing of received firmware
static mbedtls_sha256_context g_shaCtx;
static bool g_shaActive = false;

// Pause sensor task during OTA to prevent BT buffer overflow
static volatile bool g_otaActive = false;

// FreeRTOS queue for async write — decouples esp_ota_write from drain loop
static QueueHandle_t g_writeQueue = NULL;

static SemaphoreHandle_t g_writeDoneSem = NULL;

// Write queue entry
typedef struct {
    uint8_t data[OTA_CHUNK_SIZE];
    size_t  dataLen;
    uint32_t seq;
} OtaWriteEntry_t;

// Pending ACK state — write task signals when done, drain task sends ACK
static volatile uint32_t g_writeSeq = 0;
static volatile bool  g_writeSuccess = false;

// ================================================================
// Minimal base64 decoder — no external library required
// ================================================================
static int base64DecodeChunk(const char* in, size_t inLen, uint8_t* out, size_t* outLen) {
    static const int8_t decodeTable[256] = {
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63,
        52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1,
        -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
        15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1,
        -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    };

    size_t outIdx = 0;
    int i = 0;
    uint32_t buf = 0;
    int bits = 0;

    while (i < (int)inLen) {
        char c = in[i++];
        if (c == '=') break;
        int8_t val = decodeTable[(uint8_t)c];
        if (val < 0) continue;

        buf = (buf << 6) | (uint8_t)val;
        bits += 6;

        if (bits >= 8) {
            bits -= 8;
            out[outIdx++] = (uint8_t)(buf >> bits);
            buf &= ((1 << bits) - 1);
        }
    }

    *outLen = outIdx;
    return 0;
}

// ================================================================
// Parse integer from tail of a "key=NNN" substring
// ================================================================
static bool parseUint32(const char* str, const char* key, uint32_t* out) {
    const char* p = strstr(str, key);
    if (!p) return false;
    p = strchr(p, '=');
    if (!p) return false;
    *out = strtoul(p + 1, NULL, 10);
    return true;
}

// ================================================================
// Abort OTA in progress — reset all state
// ================================================================
static void abortOta(const char* reason) {
    if (g_state == BT_OTA_RECEIVING || g_state == BT_OTA_WRITING || g_state == BT_OTA_VERIFYING) {
        if (g_otaHandle != 0) {
            esp_ota_abort(g_otaHandle);
            g_otaHandle = 0;
        }
    }
    if (g_shaActive) {
        mbedtls_sha256_free(&g_shaCtx);
        g_shaActive = false;
    }
    g_state = BT_OTA_IDLE;
    g_totalReceived = 0;
    g_expectedSize  = 0;
    g_linePos = 0;
    g_otaActive = false;
    ledSetPattern(LED_IDLE);
    Serial.printf("[BT-OTA] Aborted: %s\n", reason);
}

// ================================================================
// Dedicated task: handles esp_ota_write off the drain loop's critical path
// Receives decoded chunks from queue, writes to flash, signals ACK ready
// ================================================================
static void btOtaWriteTask(void* parameter) {
    (void)parameter;
    Serial.println("[BT-OTA-Write] Task started");

    OtaWriteEntry_t entry;
    for (;;) {
        if (xQueueReceive(g_writeQueue, &entry, portMAX_DELAY) == pdTRUE) {
            Serial.printf("[BT-OTA-Write] Queue received seq=%u, len=%u\n", entry.seq, entry.dataLen);
            if (g_state != BT_OTA_RECEIVING && g_state != BT_OTA_WRITING) {
                Serial.printf("[BT-OTA-Write] Wrong state=%d, skipping seq=%u\n", g_state, entry.seq);
                continue;
            }

            // Write to OTA partition (this blocks ~500ms but drain loop keeps running)
            esp_err_t err = esp_ota_write(g_otaHandle, entry.data, entry.dataLen);

            // Update SHA256
            if (g_shaActive && err == ESP_OK) {
                mbedtls_sha256_update(&g_shaCtx, entry.data, entry.dataLen);
            }

            // Signal result back to drain loop
            g_writeSeq = entry.seq;
            g_writeSuccess = (err == ESP_OK);
            g_totalReceived += entry.dataLen;

            if (g_writeDoneSem != NULL) {
                BaseType_t xHigherPriorityTaskWoken = pdFALSE;
                xSemaphoreGiveFromISR(g_writeDoneSem, &xHigherPriorityTaskWoken);
                if (xHigherPriorityTaskWoken == pdTRUE) {
                    portYIELD_FROM_ISR();
                }
            }

            Serial.printf("[BT-OTA-Write] esp_ota_write result seq=%u: err=0x%x\n", entry.seq, err);
            if (err != ESP_OK) {
                Serial.printf("[BT-OTA-Write] esp_ota_write failed seq=%u: 0x%x\n", entry.seq, err);
            }
        }
    }
}

// ================================================================
// Drain task: parse text, send ACKs, manage buffer overflow prevention
// This runs continuously WITHOUT blocking on esp_ota_write
// ================================================================
void btOtaTask(void* parameter) {
    (void)parameter;
    g_linePos = 0;
    memset(g_lineBuf, 0, sizeof(g_lineBuf));

    Serial.println("[BT-OTA] Task started");

    for (;;) {
        if (!isAuthenticated) {
            if (g_state != BT_OTA_IDLE) {
                btOtaReset();
            }
            delay(50);
            continue;
        }

        // CRITICAL FIX: Only drain SerialBT during an active OTA transfer.
        // Without this guard, the drain loop runs 24/7 from auth success
        // and consumes every byte the sensor task writes via SerialBT.write().
        // 31-byte binary packets are non-printable, get pushed into g_lineBuf
        // (max 255), and silently discarded on overflow — so the Flutter app
        // never receives a single sensor packet while OTA is idle.
        // g_state == BT_OTA_IDLE == no OTA in progress == sensor packets own the stream.
        if (g_state == BT_OTA_IDLE) {
            // Idle: still feed the watchdog and yield so lower-priority tasks run.
            taskYIELD();
            continue;
        }

        // Drain ALL available bytes — no artificial delay in inner loop
        // taskYIELD inside inner loop gives write task CPU time without
        // sacrificing drain responsiveness. This prevents BT RX buffer overflow.
        while (SerialBT.available() > 0) {
            g_lastActivityMs = millis();
            int c = SerialBT.read();
            if (c < 0) break;

            if (c == '\n' || c == '\r') {
                if (g_linePos > 0) {
                    g_lineBuf[g_linePos] = '\0';
                    btOtaHandleTextCommand(g_lineBuf);
                    g_linePos = 0;
                    memset(g_lineBuf, 0, sizeof(g_lineBuf));
                }
            } else {
                if (g_linePos < BT_OTA_LINE_MAX - 1) {
                    g_lineBuf[g_linePos++] = (char)c;
                } else {
                    // Line buffer overflow — reset and skip
                    g_linePos = 0;
                    memset(g_lineBuf, 0, sizeof(g_lineBuf));
                }
            }

            // CRITICAL: yield after EVERY byte processed.
            // This allows esp_ota_write (~500ms) to progress in write task
            // without blocking BT RX buffer drainage. Without this, the inner
            // loop spins 100% consuming all CPU, preventing write task from
            // running → queue fills up → overflow.
            taskYIELD();
        }

        // Check if write task completed a chunk — send ACK immediately
        if (g_writeDoneSem != NULL && xSemaphoreTake(g_writeDoneSem, 0) == pdTRUE) {
            Serial.printf("[BT-OTA] Write complete! seq=%u, success=%d\n", g_writeSeq, g_writeSuccess);
            if (g_writeSuccess) {
                g_state = BT_OTA_WRITING;
                SerialBT.printf("OTA_ACK:seq=%u\n", g_writeSeq);
                Serial.printf("[BT-OTA] Chunk %u written (%u/%u bytes)\n",
                    g_writeSeq, g_totalReceived, g_expectedSize);
            } else {
                SerialBT.printf("OTA_NAK:seq=%u:write_error\n", g_writeSeq);
                abortOta("write_failed");
            }
        }

        // Timeout check (every iteration, not every 10ms)
        if (g_state == BT_OTA_RECEIVING || g_state == BT_OTA_WRITING) {
            uint32_t elapsed = millis() - g_lastActivityMs;
            if (elapsed > BT_OTA_TIMEOUT_MS) {
                Serial.printf("[BT-OTA] Timeout after %ums\n", elapsed);
                abortOta("timeout");
                SerialBT.println("OTA_TIMEOUT");
            }
        }

        // Small delay between draining and re-checking.
        // This prevents 100% CPU while waiting for data.
        // 5ms is short enough to keep BT RX buffer from overflowing
        // (ESP32 BT RX buffer holds ~200 bytes; at 115200 baud that's ~17ms)
        vTaskDelay(pdMS_TO_TICKS(5));

        // Debug: log drain loop activity every 5 seconds
        static uint32_t lastDrainDebug = 0;
        if (millis() - lastDrainDebug > 5000) {
            int avail = SerialBT.available();
            Serial.printf("[BT-OTA] Drain alive: state=%d, queueFree=%u, serialAvail=%d\n",
                g_state, g_writeQueue ? uxQueueSpacesAvailable(g_writeQueue) : 0, avail);
            lastDrainDebug = millis();
        }
    }
}

// ================================================================
// Handle a single text command line
// ================================================================
void btOtaHandleTextCommand(const char* line) {
    g_lastActivityMs = millis();

    // GET_VERSION
    if (strncmp(line, "GET_VERSION", 11) == 0) {
        char version[32];
        storageGetFirmwareVersion(version, sizeof(version));
        Serial.printf("[BT-OTA] GET_VERSION: %s\n", version);
        SerialBT.printf("VERSION=%s\n", version);
        return;
    }

    // OTA_START:size=N
    if (strncmp(line, "OTA_START:", 10) == 0) {
        if (g_state != BT_OTA_IDLE) {
            Serial.printf("[BT-OTA] OTA_START while state=%d, forcing reset\n", g_state);
            btOtaReset();
        }

        uint32_t size = 0;
        if (!parseUint32(line, "size", &size) || size == 0) {
            SerialBT.println("OTA_ERR:invalid_size");
            return;
        }

        const esp_partition_t* running = esp_ota_get_running_partition();
        const esp_partition_t* update = esp_partition_find_first(
            ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_MAX, NULL);

        if (update == NULL || update == running) {
            update = esp_partition_find_first(
                ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_0, NULL);
            if (update == running) update = NULL;
        }
        if (update == NULL || update == running) {
            update = esp_partition_find_first(
                ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_1, NULL);
            if (update == running) update = NULL;
        }

        if (!update) {
            Serial.println("[BT-OTA] ERROR: no OTA partition found!");
            SerialBT.println("OTA_ERR:no_partition");
            return;
        }

        Serial.printf("[BT-OTA] OTA target: %s at 0x%X (size=%u)\n",
            update->label, update->address, update->size);

        esp_err_t err = esp_ota_begin(update, size, &g_otaHandle);
        if (err != ESP_OK) {
            Serial.printf("[BT-OTA] esp_ota_begin failed: 0x%x\n", err);
            SerialBT.printf("OTA_ERR:begin_failed 0x%x\n", err);
            abortOta("esp_ota_begin_failed");
            return;
        }

        g_expectedSize  = size;
        g_totalReceived = 0;
        g_state = BT_OTA_RECEIVING;
        g_otaActive = true;
        ledSetPattern(LED_OTA_UPDATE);

        mbedtls_sha256_init(&g_shaCtx);
        mbedtls_sha256_starts(&g_shaCtx, 0);
        g_shaActive = true;

        Serial.printf("[BT-OTA] Begin OTA (size=%u)\n", size);
        SerialBT.println("OTA_READY");
        return;
    }

    // OTA_DATA:seq=N:base64=...
    if (strncmp(line, "OTA_DATA:", 9) == 0) {
        Serial.printf("[BT-OTA] Received OTA_DATA command, state=%d\n", g_state);
        if (g_state != BT_OTA_RECEIVING && g_state != BT_OTA_WRITING) {
            SerialBT.println("OTA_ERR:not_started");
            Serial.printf("[BT-OTA] OTA_DATA rejected: wrong state=%d\n", g_state);
            return;
        }

        uint32_t seq = 0;
        if (!parseUint32(line, "seq", &seq)) {
            SerialBT.println("OTA_NAK:seq=0:missing_seq");
            return;
        }

        const char* b64start = strstr(line, "base64=");
        if (!b64start) {
            SerialBT.printf("OTA_NAK:seq=%u:missing_data\n", seq);
            return;
        }
        b64start += 7;

        uint8_t decoded[OTA_CHUNK_SIZE];
        size_t decodedLen = 0;
        if (base64DecodeChunk(b64start, strlen(b64start), decoded, &decodedLen) != 0 || decodedLen == 0) {
            SerialBT.printf("OTA_NAK:seq=%u:decode_error\n", seq);
            return;
        }

        Serial.printf("[BT-OTA] Decoded seq=%u, len=%u, queueing...\n", seq, decodedLen);

        // Queue for async write — drain loop stays free
        OtaWriteEntry_t entry;
        memcpy(entry.data, decoded, decodedLen);
        entry.dataLen = decodedLen;
        entry.seq = seq;

        if (g_writeQueue != NULL) {
            BaseType_t queueResult = xQueueSend(g_writeQueue, &entry, 0);
            Serial.printf("[BT-OTA] xQueueSend result=%d (1=success, 0=full)\n", queueResult);
            if (queueResult != pdTRUE) {
                SerialBT.printf("OTA_NAK:seq=%u:queue_full\n", seq);
            }
        } else {
            Serial.println("[BT-OTA] ERROR: g_writeQueue is NULL!");
            SerialBT.printf("OTA_NAK:seq=%u:queue_null\n", seq);
        }
        return;
    }

    // OTA_FINISH:sha256=HEX64
    if (strncmp(line, "OTA_FINISH:", 11) == 0) {
        if (g_state != BT_OTA_RECEIVING && g_state != BT_OTA_WRITING) {
            SerialBT.println("OTA_ERR:not_started");
            return;
        }

        // Wait for pending writes to complete (semaphore-based, non-polling)
        int waitCount = 0;
        while (g_writeDoneSem != NULL && xSemaphoreTake(g_writeDoneSem, pdMS_TO_TICKS(10)) != pdTRUE && g_state != BT_OTA_ERROR && waitCount < 5000) {
            waitCount += 10;
        }

        g_state = BT_OTA_VERIFYING;
        ledSetPattern(LED_IDLE);

        const char* hashStart = strstr(line, "sha256=");
        if (!hashStart) {
            SerialBT.println("OTA_ERR:missing_sha256");
            g_state = BT_OTA_ERROR;
            return;
        }
        hashStart += 7;

        if (g_totalReceived != g_expectedSize) {
            Serial.printf("[BT-OTA] Size mismatch: received=%u expected=%u\n", g_totalReceived, g_expectedSize);
            SerialBT.printf("OTA_ERR:size_mismatch\n");
            abortOta("size_mismatch");
            return;
        }

        uint8_t computedHash[32];
        if (g_shaActive) {
            mbedtls_sha256_finish(&g_shaCtx, computedHash);
            mbedtls_sha256_free(&g_shaCtx);
            g_shaActive = false;
        }

        uint8_t providedHash[32];
        size_t hashHexLen = strlen(hashStart);
        size_t hashIdx = 0;
        for (size_t h = 0; h < hashHexLen && hashIdx < 32; h += 2) {
            char hexByte[3] = { hashStart[h], hashStart[h + 1], '\0' };
            providedHash[hashIdx++] = (uint8_t)strtoul(hexByte, NULL, 16);
        }

        bool hashMatch = true;
        for (int i = 0; i < 32; i++) {
            if (computedHash[i] != providedHash[i]) {
                hashMatch = false;
                break;
            }
        }

        if (!hashMatch) {
            SerialBT.println("OTA_ERR:hash_mismatch");
            Serial.println("[BT-OTA] SHA256 mismatch!");
            g_state = BT_OTA_ERROR;
            return;
        }

        esp_err_t err = esp_ota_end(g_otaHandle);
        g_otaHandle = 0;

        if (err != ESP_OK) {
            Serial.printf("[BT-OTA] esp_ota_end failed: 0x%x\n", err);
            SerialBT.printf("OTA_ERR:end_failed 0x%x\n", err);
            g_state = BT_OTA_ERROR;
            return;
        }

        const esp_partition_t* update = esp_partition_find_first(
            ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_MAX, NULL);
        if (update == NULL) {
            update = esp_partition_find_first(
                ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_OTA_1, NULL);
        }
        err = esp_ota_set_boot_partition(update);
        if (err != ESP_OK) {
            Serial.printf("[BT-OTA] esp_ota_set_boot_partition failed: 0x%x\n", err);
            SerialBT.printf("OTA_ERR:boot_partition 0x%x\n", err);
            g_state = BT_OTA_ERROR;
            return;
        }

        g_state = BT_OTA_COMPLETE;
        SerialBT.println("OTA_COMPLETE");
        Serial.printf("[BT-OTA] OTA complete, total bytes: %u\n", g_totalReceived);

        if (storageSetFirmwareVersion(FIRMWARE_VERSION)) {
            Serial.println("[BT-OTA] Firmware version saved to NVS");
        }

        g_otaActive = false;
        return;
    }

    // OTA_ABORT
    if (strncmp(line, "OTA_ABORT", 9) == 0) {
        abortOta("user_abort");
        SerialBT.println("OTA_ABORTED");
        return;
    }

    // REBOOT
    if (strncmp(line, "REBOOT", 6) == 0) {
        SerialBT.println("REBOOT_ACK");
        Serial.println("[BT-OTA] Rebooting...");
        delay(100);
        esp_restart();
        return;
    }
}

// ================================================================
// Public API
// ================================================================
void btOtaInit(void) {
    g_state = BT_OTA_IDLE;
    g_otaHandle = 0;
    g_totalReceived = 0;
    g_expectedSize = 0;
    g_linePos = 0;
    g_shaActive = false;
    g_otaActive = false;
    g_lastActivityMs = millis();
    memset(g_lineBuf, 0, sizeof(g_lineBuf));

    // Create write queue + semaphore
    g_writeQueue = xQueueCreate(4, sizeof(OtaWriteEntry_t));
    g_writeDoneSem = xSemaphoreCreateBinary();

    // Start write task first (Core 0, lower priority)
    xTaskCreatePinnedToCore(btOtaWriteTask, "BtOtaWrite", BT_OTA_WRITE_STACK, NULL, 1, &g_btOtaWriteTaskHandle, 0);

    // Start drain task (Core 0, higher priority)
    xTaskCreatePinnedToCore(btOtaTask, "BtOtaTask", BT_OTA_TASK_STACK, NULL, 2, &g_btOtaTaskHandle, 0);

    Serial.println("[BT-OTA] Initialized");
}

void btOtaReset(void) {
    Serial.printf("[BT-OTA] Resetting state from %d to IDLE\n", g_state);
    if (g_state == BT_OTA_RECEIVING || g_state == BT_OTA_VERIFYING) {
        if (g_otaHandle != 0) {
            esp_ota_abort(g_otaHandle);
            g_otaHandle = 0;
        }
    }
    if (g_shaActive) {
        mbedtls_sha256_free(&g_shaCtx);
        g_shaActive = false;
    }
    g_state = BT_OTA_IDLE;
    g_totalReceived = 0;
    g_expectedSize = 0;
    g_linePos = 0;
    g_otaActive = false;
    memset(g_lineBuf, 0, sizeof(g_lineBuf));
    ledSetPattern(LED_IDLE);
}

BtOtaState_t btOtaGetState(void) {
    return g_state;
}

bool btOtaIsActive(void) {
    return g_otaActive;
}

#endif  // UNIT_TEST