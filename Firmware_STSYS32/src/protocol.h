// ============================================================
// protocol.h — Packet Framing, Types, and CRC
// ============================================================
#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Force 1-byte packing for all packet structs
#pragma pack(push, 1)

// ================= PACKET TYPES =================

// Commands (host → device)
#define PKT_TYPE_CMD_START_SESSION      0x01
#define PKT_TYPE_CMD_STOP_SESSION      0x02
#define PKT_TYPE_CMD_GET_INFO          0x03
#define PKT_TYPE_CMD_GET_CONFIG        0x04
#define PKT_TYPE_CMD_SET_CONFIG        0x05
#define PKT_TYPE_CMD_AUTH              0x06
#define PKT_TYPE_CMD_FACTORY_RESET     0x0B
#define PKT_TYPE_CMD_OTA_START          0x0C
#define PKT_TYPE_CMD_OTA_DATA          0x0D
#define PKT_TYPE_CMD_OTA_END           0x0E
#define PKT_TYPE_CMD_OTA_ABORT         0x0F
#define PKT_TYPE_CMD_OTA_STATUS        0x11
#define PKT_TYPE_CMD_GET_SESSIONS      0x20
#define PKT_TYPE_CMD_GET_SESSION_DATA  0x21
#define PKT_TYPE_CMD_DELETE_SESSION    0x22
#define PKT_TYPE_CMD_CALIBRATE_START   0x23
#define PKT_TYPE_CMD_CALIBRATE_STATUS  0x24
#define PKT_TYPE_CMD_SET_MOUNT_MODE    0x25
#define PKT_TYPE_CMD_GET_CALIBRATION   0x26
#define PKT_TYPE_CMD_GET_SHOT_STATS   0x43

// Encrypted wrapper
#define PKT_TYPE_ENCRYPTED             0xF0

// Events (device → host)
#define PKT_TYPE_EVT_SESSION_STARTED   0x10
#define PKT_TYPE_EVT_SESSION_STOPPED   0x11
#define PKT_TYPE_EVT_SHOT_DETECTED     0x12
#define PKT_TYPE_EVT_SENSOR_HEALTH     0x13
#define PKT_TYPE_EVT_AUTH_CHALLENGE    0x14
#define PKT_TYPE_EVT_AUTH_SUCCESS     0x15

// Data
#define PKT_TYPE_DATA_RAW_SAMPLE       0x20

// Responses
#define PKT_TYPE_RSP_ERROR             0x80
#define PKT_TYPE_RSP_INFO              0x81
#define PKT_TYPE_RSP_CONFIG            0x82
#define PKT_TYPE_RSP_ACK               0x83
#define PKT_TYPE_RSP_OTA_STATUS        0x84
#define PKT_TYPE_RSP_SHOT_STATS        0x85

// ================= SYNC & FRAMING =================
#define PKT_SYNC0          0xAA
#define PKT_SYNC1          0x55
#define PKT_HEADER_SIZE    6   // SYNC(2) + TYPE(1) + LEN(2)
#define PKT_CRC_SIZE       2   // CRC16-CCITT

// Max payload sizes
#define MAX_PAYLOAD_SIZE   64
#define MAX_PACKET_SIZE    (PKT_HEADER_SIZE + MAX_PAYLOAD_SIZE + PKT_CRC_SIZE)

// ================= FEATURE FLAGS =================
#define FEATURE_OTA_SUPPORTED         0x0001
#define FEATURE_STORAGE_SUPPORTED     0x0002
#define FEATURE_ENCRYPTED             0x0004
#define FEATURE_AUTH_REQUIRED         0x0008
#define FEATURE_PWM_LED               0x0010
#define FEATURE_HAPTIC_PWM           0x0020
#define FEATURE_DEGRADED_MODE         0x0040
#define FEATURE_CALIBRATED           0x0080
#define FEATURE_COREDUMP             0x0100

// ================= PACKET STRUCTS =================

// DATA_RAW_SAMPLE (24 bytes — compiler-aligned)
struct PktRawSample {
    uint32_t sample_counter;
    uint32_t timestamp_us;
    int16_t  accel_x;
    int16_t  accel_y;
    int16_t  accel_z;
    int16_t  gyro_x;
    int16_t  gyro_y;
    int16_t  gyro_z;
    uint16_t piezo;
    uint16_t reserved;    // was: temperature
};  // 24 bytes (compiler packs struct to 24)

// EVT_SHOT_DETECTED (30 bytes)
struct PktShotDetected {
    uint32_t session_id;
    uint32_t timestamp_us;
    uint16_t shot_number;
    uint16_t piezo_peak;
    int16_t  accel_peak_x;
    int16_t  accel_peak_y;
    int16_t  accel_peak_z;
    int16_t  gyro_peak_x;
    int16_t  gyro_peak_y;
    int16_t  gyro_peak_z;
    int8_t   recoil_axis;    // 0=X, 1=Y, 2=Z
    int8_t   recoil_sign;    // +1 or -1
};  // 30 bytes

// EVT_AUTH_CHALLENGE (20 bytes)
struct PktAuthChallenge {
    uint32_t session_id;
    uint8_t  challenge[16];
};  // 20 bytes

// EVT_AUTH_SUCCESS (4 bytes)
struct PktAuthSuccess {
    uint32_t session_id;
};  // 4 bytes

// CMD_AUTH payload (36 bytes)
struct PktAuth {
    uint32_t session_id;
    uint8_t  token[32];  // HMAC-SHA256 response
};  // 36 bytes

// EVT_SESSION_STARTED (17 bytes)
struct PktSessionStarted {
    uint32_t session_id;
    uint32_t timestamp_us;
    uint8_t  battery_percent;
    uint8_t  sensor_health;
    uint32_t free_heap;
};  // 17 bytes

// EVT_SESSION_STOPPED (14 bytes)
struct PktSessionStopped {
    uint32_t session_id;
    uint32_t duration_ms;
    uint16_t shot_count;
    uint8_t  battery_end;
    uint8_t  sensor_health;
};  // 14 bytes

// RSP_INFO (16 bytes)
struct PktInfo {
    uint32_t firmware_version;   // e.g. 0x010000 = v1.0.0
    uint8_t  hardware_rev;
    uint32_t build_timestamp;
    uint16_t supported_features;
    uint8_t  mpu_whoami;
    uint8_t  reserved[2];
};  // 16 bytes

// RSP_ERROR (33 bytes)
struct PktError {
    uint8_t  error_code;
    char     message[32];
};  // 33 bytes

// RSP_ACK (2 bytes)
struct PktAck {
    uint8_t  command_id;
    uint8_t  status;
};  // 2 bytes

// RSP_SHOT_STATS (Phase 1.3 adaptive threshold)
struct PktShotStats {
    uint16_t shot_count;
    uint16_t mean_peak;
    uint16_t stddev_peak;
    uint32_t adaptive_threshold;
    uint8_t  adaptive_enabled;
    uint8_t  reserved[3];
};  // 14 bytes

// ================= TX PACKET BUFFER =================
struct TXItem {
    uint8_t  data[MAX_PACKET_SIZE];
    uint16_t length;
};

// Restore default packing
#pragma pack(pop)

// ================= DECODED PACKET =================
struct DecodedPacket {
    uint8_t  type;
    uint16_t payload_len;
    uint8_t  payload[MAX_PAYLOAD_SIZE];
};

// ================= CRC =================
// CRC16-CCITT: poly=0x1021, init=0xFFFF, xor_out=0x0000, reflect_in=false, reflect_out=false
uint16_t crc16_ccitt(const uint8_t* data, uint16_t len);

// ================= ENCODER =================
// Build a framed packet. Returns total frame size.
uint16_t encodePacket(uint8_t type, const void* payload, uint16_t len,
                      uint8_t* outBuffer);

// ================= DECODER STATE MACHINE =================
enum class DecoderState {
    WAIT_SYNC0,
    WAIT_SYNC1,
    READ_TYPE,
    READ_LEN_LO,
    READ_LEN_HI,
    READ_PAYLOAD,
    READ_CRC_LO,
    READ_CRC_HI,
};

void     initDecoder();
bool     decodeByte(uint8_t byte, DecodedPacket* outPkt);

#endif  // PROTOCOL_H
