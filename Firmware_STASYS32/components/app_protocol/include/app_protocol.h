#pragma once

#include <stdint.h>
#include <stddef.h>

#define STASYS_PACKET_SIZE 36u
#define STASYS_PACKET_PAYLOAD_SIZE 33u
#define STASYS_PACKET_HEADER_0 0xAAu
#define STASYS_PACKET_HEADER_1 0xBBu

#define STASYS_AUTH_VERSION 3u
#define STASYS_AUTH_NONCE_SIZE 32u
#define STASYS_AUTH_PROOF_SIZE 32u
#define STASYS_AUTH_PROOF_HEX_SIZE (STASYS_AUTH_PROOF_SIZE * 2u)
#define STASYS_AUTH_MAC_HEX_SIZE 12u
#define STASYS_AUTH_MAX_LINE 160u
#define STASYS_AUTH_TIMEOUT_MS 10000u
#define STASYS_AUTH_MAX_ATTEMPTS 3u
#define STASYS_AUTH_SALT_SIZE 32u
#define STASYS_AUTH_TRANSCRIPT_SIZE (14u + 6u + STASYS_AUTH_NONCE_SIZE)

typedef struct {
    float ax;
    float ay;
    float az;
    float gx;
    float gy;
    float gz;
    int16_t mag_x;
    int16_t mag_y;
    int16_t mag_z;
    uint16_t piezo;
    uint8_t battery;
} staysys_packet_payload_t;

#ifdef __cplusplus
static_assert(sizeof(float) == 4, "STASYS requires IEEE-754 float32");
extern "C" {
#endif

size_t staysys_packet_serialize(const staysys_packet_payload_t *payload,
                                uint8_t output[STASYS_PACKET_SIZE]);

typedef int (*staysys_key_provider_t)(const uint8_t **key, size_t *key_len, void *context);

void staysys_auth_set_key_provider(staysys_key_provider_t provider, void *context);
int staysys_auth_get_key(const uint8_t **key, size_t *key_len);
int staysys_auth_derive_key(const uint8_t *salt, size_t salt_len,
                            const uint8_t *identity, size_t identity_len,
                            uint8_t output[STASYS_AUTH_PROOF_SIZE]);
int staysys_auth_build_transcript(const uint8_t *identity, size_t identity_len,
                                  const uint8_t *nonce, size_t nonce_len,
                                  uint8_t output[STASYS_AUTH_TRANSCRIPT_SIZE]);
int staysys_auth_proof(const uint8_t *key, size_t key_len,
                       const uint8_t *transcript, size_t transcript_len,
                       uint8_t output[STASYS_AUTH_PROOF_SIZE]);
int staysys_constant_time_equal(const uint8_t *left, const uint8_t *right, size_t length);
void staysys_secure_zero(void *buffer, size_t length);

#ifdef __cplusplus
}
#endif
