#ifndef BT_OTA_COMMANDS_H
#define BT_OTA_COMMANDS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Reduced from 512 to 128 bytes to prevent BT RX buffer overflow on ESP32.
// At 115200 baud, 512 bytes raw → ~688 bytes base64 → ~700 bytes BT transfer.
// ESP32 BT RX buffer is ~200 bytes. 700 bytes overflows before drain loop can read.
// 128 bytes raw → ~172 bytes base64 → ~200 bytes BT transfer. Fits in buffer.
#define OTA_CHUNK_SIZE 128

typedef enum {
    BT_OTA_IDLE,
    BT_OTA_RECEIVING,
    BT_OTA_WRITING,
    BT_OTA_VERIFYING,
    BT_OTA_COMPLETE,
    BT_OTA_ERROR
} BtOtaState_t;

typedef struct {
    uint16_t seq;
    uint8_t data[OTA_CHUNK_SIZE];
    size_t dataLen;
    uint16_t crc16;
} __attribute__((packed)) OtaDataChunk_t;

#endif  // BT_OTA_COMMANDS_H
