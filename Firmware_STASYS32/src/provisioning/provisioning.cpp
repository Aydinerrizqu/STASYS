#include "provisioning.h"
#include <stdio.h>
#include <string.h>
#include "nvs.h"
#include "esp_log.h"

static const char *TAG = "provision";
static const char *NVS_NS = "auth";
static const char *NVS_KEY = "device_key";
static const int KEY_LEN = 32;

static uint8_t s_key[KEY_LEN];
static bool s_key_loaded = false;
static bool s_key_valid = false;

static int hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static bool hex_decode_32(const char *hex, uint8_t out[KEY_LEN])
{
    if (hex == NULL || strlen(hex) != (size_t)KEY_LEN * 2) return false;
    for (int i = 0; i < KEY_LEN; ++i) {
        int high = hex_nibble(hex[i * 2]);
        int low = hex_nibble(hex[i * 2 + 1]);
        if (high < 0 || low < 0) return false;
        out[i] = (uint8_t)((high << 4) | low);
    }
    return true;
}

int staysys_provisioned_key(const uint8_t **key, size_t *key_len)
{
    if (s_key_valid) {
        *key = s_key;
        *key_len = KEY_LEN;
        return 0;
    }
    if (s_key_loaded) {
        *key = NULL;
        *key_len = 0;
        return -1;
    }
    s_key_loaded = true;
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) {
        *key = NULL;
        *key_len = 0;
        return -1;
    }
    size_t len = KEY_LEN;
    int rc = nvs_get_blob(h, NVS_KEY, s_key, &len);
    nvs_close(h);
    s_key_valid = (rc == ESP_OK && len == KEY_LEN);
    if (!s_key_valid) memset(s_key, 0, sizeof(s_key));
    *key = s_key_valid ? s_key : NULL;
    *key_len = s_key_valid ? KEY_LEN : 0;
    return s_key_valid ? 0 : -1;
}

bool provisioning_handle_line(const char *line)
{
    const char prefix[] = "PROVISION_KEY:";
    if (strncmp(line, prefix, sizeof(prefix) - 1) != 0) return false;
    const char *hex = line + sizeof(prefix) - 1;
    uint8_t decoded[KEY_LEN];
    if (!hex_decode_32(hex, decoded)) {
        ESP_LOGW(TAG, "provisioning rejected: malformed key (expected 64 hex chars)");
        printf("PROVISION_ERR:malformed\n");
        return true;
    }
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) {
        memset(decoded, 0, sizeof(decoded));
        printf("PROVISION_ERR:nvs\n");
        return true;
    }
    esp_err_t err = nvs_set_blob(h, NVS_KEY, decoded, KEY_LEN);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    memset(decoded, 0, sizeof(decoded));
    if (err != ESP_OK) {
        printf("PROVISION_ERR:write\n");
        return true;
    }
    /* Invalidate cache so next auth read uses new key. */
    memset(s_key, 0, sizeof(s_key));
    s_key_loaded = false;
    s_key_valid = false;
    printf("PROVISION_OK\n");
    return true;
}

void provisioning_print_status(void)
{
    const uint8_t *k;
    size_t n;
    const char *status = staysys_provisioned_key(&k, &n) == 0 ? "ok" : "absent";
    printf("PROVISION_STATUS:%s\n", status);
}
