// ============================================================
// protocol.cpp — CRC16-CCITT, Packet Encoding/Decoding
// ============================================================
#include "protocol.h"
#include <Arduino.h>
#include <string.h>

// ================= CRC16-CCITT =================
// Standard parameters: poly=0x1021, init=0xFFFF, xor_out=0x0000
uint16_t crc16_ccitt(const uint8_t* data, uint16_t len) {
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= ((uint16_t)data[i]) << 8;
        for (uint8_t bit = 0; bit < 8; bit++) {
            if (crc & 0x8000) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc = crc << 1;
            }
            crc &= 0xFFFF;
        }
    }
    return crc;
}

// Debug CRC: print bytes being CRC'd + result
static uint32_t s_crcDebugCount = 0;
static void debugCRC(const uint8_t* data, uint16_t len, uint16_t crc) {
    if (s_crcDebugCount < 5 && len > 0) {
        Serial.printf("[CRC] type=0x%02X len=%u: ", (unsigned)data[0], (unsigned)len);
        for (uint16_t i = 0; i < len; i++) {
            Serial.printf("%02X ", (unsigned)data[i]);
        }
        Serial.printf("=> %04X (LE: %02X %02X)\n", (unsigned)crc, (unsigned)(crc & 0xFF), (unsigned)((crc >> 8) & 0xFF));
        s_crcDebugCount++;
    }
}

// ================= ENCODER =================
uint16_t encodePacket(uint8_t type, const void* payload, uint16_t len,
                      uint8_t* outBuffer) {
    if (len > MAX_PAYLOAD_SIZE) {
        Serial.printf("[PROTOCOL] WARNING: payload %u exceeds max %u\n", len, MAX_PAYLOAD_SIZE);
        len = MAX_PAYLOAD_SIZE;
    }

    uint16_t idx = 0;

    // Sync bytes
    outBuffer[idx++] = PKT_SYNC0;
    outBuffer[idx++] = PKT_SYNC1;

    // Type
    outBuffer[idx++] = type;

    // Length (little-endian)
    outBuffer[idx++] = len & 0xFF;
    outBuffer[idx++] = (len >> 8) & 0xFF;

    // Payload
    if (payload && len > 0) {
        memcpy(&outBuffer[idx], payload, len);
        idx += len;
    }

    // CRC over [TYPE(1)][LEN_LO(1)][LEN_HI(1)][payload(len)] = 3+len bytes
    uint16_t crc = crc16_ccitt(&outBuffer[2], 3 + len);
    debugCRC(&outBuffer[2], 3 + len, crc);
    outBuffer[idx++] = crc & 0xFF;
    outBuffer[idx++] = (crc >> 8) & 0xFF;

    return idx;  // Total frame size
}

// ================= DECODER =================
// Decoder is shared between the bluetooth task and command handlers.
// Only one instance needed per ESP32 (static state).

static DecoderState s_decState = DecoderState::WAIT_SYNC0;
static uint8_t  s_decType = 0;
static uint16_t s_decPayloadLen = 0;
static uint8_t  s_decBuffer[MAX_PAYLOAD_SIZE];
static uint16_t s_decBufIdx = 0;
static uint16_t s_decCrcComputed = 0xFFFF;

void initDecoder() {
    s_decState = DecoderState::WAIT_SYNC0;
    s_decType = 0;
    s_decPayloadLen = 0;
    s_decBufIdx = 0;
    s_decCrcComputed = 0xFFFF;
    memset(s_decBuffer, 0, sizeof(s_decBuffer));
}

static inline uint16_t updateCrc(uint16_t crc, uint8_t byte) {
    crc ^= ((uint16_t)byte) << 8;
    for (uint8_t bit = 0; bit < 8; bit++) {
        if (crc & 0x8000) {
            crc = (crc << 1) ^ 0x1021;
        } else {
            crc = crc << 1;
        }
        crc &= 0xFFFF;
    }
    return crc;
}

bool decodeByte(uint8_t byte, DecodedPacket* outPkt) {
    bool packetReady = false;

    switch (s_decState) {
        case DecoderState::WAIT_SYNC0:
            if (byte == PKT_SYNC0) {
                s_decState = DecoderState::WAIT_SYNC1;
            }
            break;

        case DecoderState::WAIT_SYNC1:
            if (byte == PKT_SYNC1) {
                s_decState = DecoderState::READ_TYPE;
                s_decCrcComputed = 0xFFFF;
            } else if (byte == PKT_SYNC0) {
                // Stay in WAIT_SYNC1, keep waiting for second sync byte
            } else {
                s_decState = DecoderState::WAIT_SYNC0;
            }
            break;

        case DecoderState::READ_TYPE:
            s_decType = byte;
            s_decCrcComputed = updateCrc(s_decCrcComputed, byte);
            s_decState = DecoderState::READ_LEN_LO;
            break;

        case DecoderState::READ_LEN_LO:
            s_decPayloadLen = byte;
            s_decCrcComputed = updateCrc(s_decCrcComputed, byte);
            s_decState = DecoderState::READ_LEN_HI;
            break;

        case DecoderState::READ_LEN_HI: {
            s_decPayloadLen |= ((uint16_t)byte) << 8;
            s_decCrcComputed = updateCrc(s_decCrcComputed, byte);

            if (s_decPayloadLen > MAX_PAYLOAD_SIZE) {
                Serial.printf("[PROTOCOL] WARNING: payload %u exceeds max, truncating\n", s_decPayloadLen);
                s_decPayloadLen = MAX_PAYLOAD_SIZE;
            }

            s_decBufIdx = 0;
            if (s_decPayloadLen == 0) {
                s_decState = DecoderState::READ_CRC_LO;
            } else {
                s_decState = DecoderState::READ_PAYLOAD;
            }
            break;
        }

        case DecoderState::READ_PAYLOAD:
            s_decBuffer[s_decBufIdx++] = byte;
            s_decCrcComputed = updateCrc(s_decCrcComputed, byte);
            if (s_decBufIdx >= s_decPayloadLen) {
                s_decState = DecoderState::READ_CRC_LO;
            }
            break;

        case DecoderState::READ_CRC_LO: {
            uint16_t crcReceived = byte;
            s_decState = DecoderState::READ_CRC_HI;
            // Store CRC low byte in s_decPayloadLen temporarily
            s_decPayloadLen = crcReceived;
            break;
        }

        case DecoderState::READ_CRC_HI: {
            uint16_t crcReceived = s_decPayloadLen | ((uint16_t)byte) << 8;

            if (s_decCrcComputed == crcReceived) {
                // Valid packet
                if (outPkt) {
                    outPkt->type = s_decType;
                    outPkt->payload_len = s_decPayloadLen;
                    if (s_decPayloadLen > 0) {
                        memcpy(outPkt->payload, s_decBuffer, s_decPayloadLen);
                    }
                }
                packetReady = true;
            } else {
                Serial.printf("[PROTOCOL] CRC mismatch: computed=0x%04X, received=0x%04X\n",
                             s_decCrcComputed, crcReceived);
            }

            // Reset state regardless of CRC match
            s_decState = DecoderState::WAIT_SYNC0;
            s_decPayloadLen = 0;
            s_decBufIdx = 0;
            s_decCrcComputed = 0xFFFF;
            break;
        }
    }

    return packetReady;
}
