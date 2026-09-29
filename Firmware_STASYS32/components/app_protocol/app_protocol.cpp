#include "app_protocol.h"

#include <string.h>

#include "mbedtls/md.h"

static staysys_key_provider_t s_key_provider;
static void *s_key_context;

void staysys_auth_set_key_provider(staysys_key_provider_t provider, void *context)
{
    s_key_provider = provider;
    s_key_context = context;
}

int staysys_auth_get_key(const uint8_t **key, size_t *key_len)
{
    if (key == NULL || key_len == NULL || s_key_provider == NULL) return -1;
    *key = NULL;
    *key_len = 0;
    if (s_key_provider(key, key_len, s_key_context) != 0 || *key == NULL || *key_len == 0) {
        *key = NULL;
        *key_len = 0;
        return -1;
    }
    return 0;
}

static void put_u16_le(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)(value & 0xffu);
    out[1] = (uint8_t)(value >> 8);
}

static void put_i16_le(uint8_t *out, int16_t value)
{
    put_u16_le(out, (uint16_t)value);
}

static void put_f32_le(uint8_t *out, float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    out[0] = (uint8_t)(bits & 0xffu);
    out[1] = (uint8_t)((bits >> 8) & 0xffu);
    out[2] = (uint8_t)((bits >> 16) & 0xffu);
    out[3] = (uint8_t)(bits >> 24);
}

size_t staysys_packet_serialize(const staysys_packet_payload_t *payload,
                                uint8_t output[STASYS_PACKET_SIZE])
{
    if (payload == NULL || output == NULL) return 0;
    output[0] = STASYS_PACKET_HEADER_0;
    output[1] = STASYS_PACKET_HEADER_1;
    put_f32_le(&output[2], payload->ax);
    put_f32_le(&output[6], payload->ay);
    put_f32_le(&output[10], payload->az);
    put_f32_le(&output[14], payload->gx);
    put_f32_le(&output[18], payload->gy);
    put_f32_le(&output[22], payload->gz);
    put_i16_le(&output[26], payload->mag_x);
    put_i16_le(&output[28], payload->mag_y);
    put_i16_le(&output[30], payload->mag_z);
    put_u16_le(&output[32], payload->piezo);
    output[34] = payload->battery;
    output[35] = 0;
    for (size_t i = 2; i < 35; ++i) output[35] ^= output[i];
    return STASYS_PACKET_SIZE;
}

void staysys_secure_zero(void *buffer, size_t length)
{
    if (buffer == NULL) return;
    volatile uint8_t *bytes = (volatile uint8_t *)buffer;
    while (length--) *bytes++ = 0;
}

int staysys_constant_time_equal(const uint8_t *left, const uint8_t *right,
                                size_t length)
{
    if (left == NULL || right == NULL) return 0;
    uint8_t difference = 0;
    for (size_t i = 0; i < length; ++i) difference |= left[i] ^ right[i];
    return difference == 0;
}

int staysys_auth_proof(const uint8_t *key, size_t key_len,
                       const uint8_t *transcript, size_t transcript_len,
                       uint8_t output[STASYS_AUTH_PROOF_SIZE])
{
    if (key == NULL || key_len == 0 || transcript == NULL || transcript_len == 0 ||
        output == NULL) return -1;
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (info == NULL) return -1;
    mbedtls_md_context_t context;
    mbedtls_md_init(&context);
    int result = mbedtls_md_setup(&context, info, 1);
    if (result == 0) result = mbedtls_md_hmac_starts(&context, key, key_len);
    if (result == 0) result = mbedtls_md_hmac_update(&context, transcript, transcript_len);
    if (result == 0) result = mbedtls_md_hmac_finish(&context, output);
    mbedtls_md_free(&context);
    if (result != 0) staysys_secure_zero(output, STASYS_AUTH_PROOF_SIZE);
    return result == 0 ? 0 : -1;
}
