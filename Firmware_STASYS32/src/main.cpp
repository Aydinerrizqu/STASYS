#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_spp_api.h"
#include "esp_bt_device.h"
#include "esp_mac.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "app_protocol.h"
#include "sensor_hal.h"
#include <cmath>
#include <cstdio>
#include <cstring>

#define FIRMWARE_VERSION "3.0.0"

static const char *TAG = "stasys";
static EventGroupHandle_t app_events;
static staysys_hal_t sensors;
static volatile uint8_t battery_percentage;
static portMUX_TYPE spp_lock = portMUX_INITIALIZER_UNLOCKED;
static SemaphoreHandle_t spp_tx_mutex;
static uint32_t spp_handle;
static bool spp_congested;

#define BT_CONNECTED BIT0
#define BT_AUTHENTICATED BIT1

/* Development shared secret; replace per production batch. */
static const uint8_t STASYS_AUTH_SALT[STASYS_AUTH_SALT_SIZE] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
};

enum class spp_auth_state : uint8_t {
    DISCONNECTED,
    WAITING_FOR_PROOF,
    AUTHENTICATED,
};

static spp_auth_state auth_state = spp_auth_state::DISCONNECTED;
static uint8_t auth_nonce[STASYS_AUTH_NONCE_SIZE];
static uint8_t auth_bt_mac[6];
static char auth_rx[STASYS_AUTH_MAX_LINE + 1];
static size_t auth_rx_len;
static uint8_t auth_attempts;
static int64_t auth_deadline_us;
static uint8_t device_key_derived[STASYS_AUTH_PROOF_SIZE];

static int device_key_provider(const uint8_t **key, size_t *key_len, void *)
{
    if (staysys_auth_derive_key(STASYS_AUTH_SALT, sizeof(STASYS_AUTH_SALT),
                                auth_bt_mac, sizeof(auth_bt_mac),
                                device_key_derived) != 0) {
        return -1;
    }
    *key = device_key_derived;
    *key_len = STASYS_AUTH_PROOF_SIZE;
    return 0;
}

static void reset_auth_state(void)
{
    auth_state = spp_auth_state::DISCONNECTED;
    auth_rx_len = 0;
    auth_attempts = 0;
    auth_deadline_us = 0;
    auth_rx[0] = '\0';
    staysys_secure_zero(auth_nonce, sizeof(auth_nonce));
    staysys_secure_zero(auth_bt_mac, sizeof(auth_bt_mac));
    staysys_secure_zero(device_key_derived, sizeof(device_key_derived));
}

static bool spp_write(uint32_t handle, const uint8_t *data, size_t length)
{
    if (handle == 0 || data == nullptr || length == 0 || spp_tx_mutex == nullptr) return false;
    if (xSemaphoreTake(spp_tx_mutex, pdMS_TO_TICKS(100)) != pdTRUE) return false;
    esp_err_t result = esp_spp_write(handle, (int)length, const_cast<uint8_t *>(data));
    xSemaphoreGive(spp_tx_mutex);
    return result == ESP_OK;
}

static void reset_spp_state(bool clear_handle)
{
    portENTER_CRITICAL(&spp_lock);
    spp_congested = false;
    if (clear_handle) spp_handle = 0;
    portEXIT_CRITICAL(&spp_lock);
    xEventGroupClearBits(app_events, BT_CONNECTED | BT_AUTHENTICATED);
    reset_auth_state();
}

static bool hex_nibble(char c, uint8_t *out)
{
    if (c >= '0' && c <= '9') {
        *out = (uint8_t)(c - '0');
        return true;
    }
    if (c >= 'a' && c <= 'f') {
        *out = (uint8_t)(c - 'a' + 10);
        return true;
    }
    if (c >= 'A' && c <= 'F') {
        *out = (uint8_t)(c - 'A' + 10);
        return true;
    }
    return false;
}

static bool decode_hex(const char *hex, size_t hex_len, uint8_t *out, size_t out_len)
{
    if (hex_len != out_len * 2) return false;
    for (size_t i = 0; i < out_len; ++i) {
        uint8_t hi = 0;
        uint8_t lo = 0;
        if (!hex_nibble(hex[i * 2], &hi) || !hex_nibble(hex[i * 2 + 1], &lo)) return false;
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return true;
}

static void auth_fail_attempt(uint32_t handle)
{
    ++auth_attempts;
    auth_rx_len = 0;
    auth_rx[0] = '\0';
    if (auth_attempts >= STASYS_AUTH_MAX_ATTEMPTS) {
        ESP_LOGW(TAG, "auth failed %u times, disconnecting", (unsigned)auth_attempts);
        reset_spp_state(true);
        esp_spp_disconnect(handle);
        return;
    }
    static const uint8_t fail_line[] = "FAIL\n";
    if (!spp_write(handle, fail_line, sizeof(fail_line) - 1)) {
        reset_spp_state(true);
        esp_spp_disconnect(handle);
    }
}

static void process_auth_line(uint32_t handle)
{
    if (auth_state != spp_auth_state::WAITING_FOR_PROOF) {
        auth_rx_len = 0;
        return;
    }
    int64_t now = esp_timer_get_time();
    if (auth_deadline_us > 0 && now > auth_deadline_us) {
        ESP_LOGW(TAG, "auth handshake timed out");
        reset_spp_state(true);
        esp_spp_disconnect(handle);
        return;
    }

    const char proof_prefix[] = "PROOF ";
    const size_t prefix_len = sizeof(proof_prefix) - 1;
    if (auth_rx_len < prefix_len + STASYS_AUTH_PROOF_HEX_SIZE ||
        memcmp(auth_rx, proof_prefix, prefix_len) != 0) {
        auth_fail_attempt(handle);
        return;
    }

    uint8_t received[STASYS_AUTH_PROOF_SIZE];
    if (!decode_hex(auth_rx + prefix_len, STASYS_AUTH_PROOF_HEX_SIZE,
                    received, sizeof(received))) {
        auth_fail_attempt(handle);
        return;
    }

    uint8_t transcript[STASYS_AUTH_TRANSCRIPT_SIZE];
    if (staysys_auth_build_transcript(auth_bt_mac, sizeof(auth_bt_mac),
                                      auth_nonce, sizeof(auth_nonce),
                                      transcript) != 0) {
        auth_fail_attempt(handle);
        return;
    }

    const uint8_t *device_key = nullptr;
    size_t device_key_len = 0;
    if (staysys_auth_get_key(&device_key, &device_key_len) != 0 ||
        device_key == nullptr || device_key_len != STASYS_AUTH_PROOF_SIZE) {
        auth_fail_attempt(handle);
        return;
    }

    uint8_t expected[STASYS_AUTH_PROOF_SIZE];
    if (staysys_auth_proof(device_key, device_key_len,
                           transcript, sizeof(transcript),
                           expected) != 0) {
        staysys_secure_zero(expected, sizeof(expected));
        auth_fail_attempt(handle);
        return;
    }

    bool ok = staysys_constant_time_equal(expected, received, sizeof(expected)) != 0;
    staysys_secure_zero(expected, sizeof(expected));
    staysys_secure_zero(received, sizeof(received));
    auth_rx_len = 0;
    if (!ok) {
        auth_fail_attempt(handle);
        return;
    }

    auth_state = spp_auth_state::AUTHENTICATED;
    static const uint8_t ok_line[] = "OK\n";
    if (!spp_write(handle, ok_line, sizeof(ok_line) - 1)) {
        reset_spp_state(true);
        esp_spp_disconnect(handle);
        return;
    }
    xEventGroupSetBits(app_events, BT_AUTHENTICATED);
    ESP_LOGI(TAG, "auth handshake succeeded");
}

static void spp_auth_feed(uint32_t handle, const uint8_t *data, size_t length)
{
    if (auth_state != spp_auth_state::WAITING_FOR_PROOF || data == nullptr || length == 0) return;
    for (size_t i = 0; i < length; ++i) {
        char c = (char)data[i];
        if (c == '\r') continue;
        if (c == '\n') {
            if (auth_rx_len > STASYS_AUTH_MAX_LINE) {
                auth_fail_attempt(handle);
                return;
            }
            auth_rx[auth_rx_len] = '\0';
            process_auth_line(handle);
            return;
        }
        if (auth_rx_len >= STASYS_AUTH_MAX_LINE) {
            auth_fail_attempt(handle);
            return;
        }
        auth_rx[auth_rx_len++] = c;
    }
}

static void spp_callback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param)
{
    switch (event) {
    case ESP_SPP_INIT_EVT:
        /* Answer inquiry only now that Bluedroid is enabled: Windows discovery
         * runs a BR/EDR inquiry and cannot see a NON_DISCOVERABLE device. */
        esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE);
        esp_spp_start_srv(ESP_SPP_SEC_NONE, ESP_SPP_ROLE_SLAVE, 0, "STASYS");
        break;
    case ESP_SPP_SRV_OPEN_EVT: {
        uint32_t handle = param->srv_open.handle;
        if (param->srv_open.status != ESP_SPP_SUCCESS) {
            esp_spp_disconnect(handle);
            break;
        }
        bool accept;
        portENTER_CRITICAL(&spp_lock);
        accept = spp_handle == 0;
        if (accept) {
            spp_handle = handle;
            spp_congested = false;
        }
        portEXIT_CRITICAL(&spp_lock);
        if (!accept) {
            esp_spp_disconnect(handle);
            break;
        }
        reset_auth_state();
        esp_read_mac(auth_bt_mac, ESP_MAC_BT);
        esp_fill_random(auth_nonce, sizeof(auth_nonce));
        auth_deadline_us = esp_timer_get_time() + (int64_t)STASYS_AUTH_TIMEOUT_MS * 1000;
        auth_state = spp_auth_state::WAITING_FOR_PROOF;

        static const char ready[] = "READY v=3\n";
        char auth_line[STASYS_AUTH_MAX_LINE];
        char nonce_hex[STASYS_AUTH_PROOF_HEX_SIZE + 1];
        char mac_hex[STASYS_AUTH_MAC_HEX_SIZE + 1];
        for (size_t i = 0; i < sizeof(auth_nonce); ++i) {
            snprintf(&nonce_hex[i * 2], 3, "%02x", auth_nonce[i]);
        }
        for (size_t i = 0; i < sizeof(auth_bt_mac); ++i) {
            snprintf(&mac_hex[i * 2], 3, "%02x", auth_bt_mac[i]);
        }
        int auth_len = snprintf(auth_line, sizeof(auth_line), "AUTH %s %s\n", nonce_hex, mac_hex);
        if (auth_len <= 0 || (size_t)auth_len >= sizeof(auth_line)) {
            reset_spp_state(true);
            esp_spp_disconnect(handle);
            break;
        }
        if (!spp_write(handle, reinterpret_cast<const uint8_t *>(ready), sizeof(ready) - 1) ||
            !spp_write(handle, reinterpret_cast<const uint8_t *>(auth_line), (size_t)auth_len)) {
            reset_spp_state(true);
            esp_spp_disconnect(handle);
            break;
        }
        xEventGroupSetBits(app_events, BT_CONNECTED);
        ESP_LOGI(TAG, "auth challenge sent");
        break;
    }
    case ESP_SPP_DATA_IND_EVT: {
        uint32_t handle = param->data_ind.handle;
        portENTER_CRITICAL(&spp_lock);
        bool current = handle != 0 && handle == spp_handle;
        portEXIT_CRITICAL(&spp_lock);
        if (!current) break;
        spp_auth_feed(handle, param->data_ind.data, (size_t)param->data_ind.len);
        break;
    }
    case ESP_SPP_CONG_EVT:
        portENTER_CRITICAL(&spp_lock);
        if (param->cong.handle == spp_handle) spp_congested = param->cong.cong;
        portEXIT_CRITICAL(&spp_lock);
        break;
    case ESP_SPP_CLOSE_EVT: {
        uint32_t closed = param->close.handle;
        portENTER_CRITICAL(&spp_lock);
        bool current = closed != 0 && closed == spp_handle;
        portEXIT_CRITICAL(&spp_lock);
        if (current) reset_spp_state(true);
        break;
    }
    default:
        break;
    }
}

/* Legacy (pre-SSP) pairing has no place in the Just Works policy: the device
 * has no display or keyboard, so accepting a peer-chosen or fixed PIN would
 * add a credential path the device cannot justify. Reject and let the
 * peer fail cleanly instead of hanging on an unanswered PIN request. */
static void gap_callback(esp_bt_gap_cb_event_t event, esp_bt_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_BT_GAP_AUTH_CMPL_EVT: {
        const char *status = param->auth_cmpl.stat == ESP_BT_STATUS_SUCCESS ? "success" : "failed";
        ESP_LOGI(TAG, "pairing %s status:%d dev:\"%s\"",
                 status,
                 (int)param->auth_cmpl.stat,
                 (const char *)param->auth_cmpl.device_name);
        break;
    }
    case ESP_BT_GAP_CFM_REQ_EVT:
        ESP_LOGI(TAG, "SSP confirm requested, accepting (num:%06u)", (unsigned)param->cfm_req.num_val);
        esp_bt_gap_ssp_confirm_reply(param->cfm_req.bda, true);
        break;
    case ESP_BT_GAP_PIN_REQ_EVT:
        ESP_LOGW(TAG, "legacy PIN pairing requested, rejecting (policy: Just Works only)");
        {
            esp_bt_pin_code_t rejected_code = {0};
            esp_bt_gap_pin_reply(param->pin_req.bda, false, 0, rejected_code);
        }
        break;
    case ESP_BT_GAP_KEY_REQ_EVT:
        ESP_LOGI(TAG, "pairing passkey requested by peer (no input available)");
        break;
    default:
        ESP_LOGD(TAG, "GAP event %d", (int)event);
        break;
    }
}

static void bt_init(void)
{
    esp_bt_controller_config_t config = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&config));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_CLASSIC_BT));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());
    /* Bluedroid drops pairing events (confirm/PIN/auth complete) unless a GAP
     * callback is registered. Register it before starting the SPP server. */
    ESP_ERROR_CHECK(esp_bt_gap_register_callback(gap_callback));
    esp_bt_sp_param_t param_type = ESP_BT_SP_IOCAP_MODE;
    esp_bt_io_cap_t iocap = ESP_BT_IO_CAP_NONE;
    ESP_ERROR_CHECK(esp_bt_gap_set_security_param(param_type, &iocap, sizeof(iocap)));
    ESP_ERROR_CHECK(esp_spp_register_callback(spp_callback));
    esp_spp_cfg_t spp_cfg = {
        .mode = ESP_SPP_MODE_CB,
        .enable_l2cap_ertm = false,
        .tx_buffer_size = 0,
    };
    ESP_ERROR_CHECK(esp_spp_enhanced_init(&spp_cfg));

    uint64_t mac = 0;
    esp_read_mac((uint8_t *)&mac, ESP_MAC_BT);
    char name[24];
    snprintf(name, sizeof(name), "STASYS-%04X", (uint16_t)(mac >> 32));
    ESP_ERROR_CHECK(esp_bt_dev_set_device_name(name));
    staysys_auth_set_key_provider(device_key_provider, nullptr);
}

static void sensor_task(void *)
{
        int16_t last_mpu[6] = {0};
        int16_t last_mag[3] = {0};
        bool have_mpu = false;
    float previous[3] = {0};
    const int64_t diagnostic_interval_us = 500000;
    int64_t next_log_deadline = 0;
    while (true) {
        int64_t deadline = esp_timer_get_time() + STASYS_PACKET_PERIOD_US;
        have_mpu = false;

        float peak[3] = {0};
        float max_jerk = -1.0f;
        int64_t gyro_sum[3] = {0};
        int successful_mpu_reads = 0;
        uint16_t max_piezo = 0;
        for (int i = 0; i < STASYS_OVERSAMPLE_LOOPS; ++i) {
            if (staysys_mpu_read(&sensors, last_mpu) != ESP_OK) {
                esp_rom_delay_us(STASYS_SENSOR_DELAY_US);
                continue;
            }
            have_mpu = true;
            ++successful_mpu_reads;
            int piezo = 0;
            if (staysys_piezo_read(&sensors, &piezo) == ESP_OK && piezo > max_piezo) {
                max_piezo = (uint16_t)piezo;
            }
            float current[3] = {
                last_mpu[0] / 8192.0f * 9.81f,
                last_mpu[1] / 8192.0f * 9.81f,
                last_mpu[2] / 8192.0f * 9.81f,
            };
            float jerk = fabsf(current[0] - previous[0]) +
                         fabsf(current[1] - previous[1]) +
                         fabsf(current[2] - previous[2]);
            if (jerk > max_jerk) {
                max_jerk = jerk;
                memcpy(peak, current, sizeof(peak));
            }
            previous[0] = current[0]; previous[1] = current[1]; previous[2] = current[2];
            gyro_sum[0] += last_mpu[3]; gyro_sum[1] += last_mpu[4]; gyro_sum[2] += last_mpu[5];
            esp_rom_delay_us(STASYS_SENSOR_DELAY_US);
        }
        if (!have_mpu || successful_mpu_reads == 0) continue;
        bool have_mag = staysys_mag_read(&sensors, last_mag) == ESP_OK;
        if (!have_mag) memset(last_mag, 0, sizeof(last_mag));
        float gyro[3] = {
            (gyro_sum[0] / (float)successful_mpu_reads) / 65.5f * 0.0174533f,
            (gyro_sum[1] / (float)successful_mpu_reads) / 65.5f * 0.0174533f,
            (gyro_sum[2] / (float)successful_mpu_reads) / 65.5f * 0.0174533f,
        };
        staysys_packet_payload_t payload = {
            .ax = peak[0], .ay = peak[1], .az = peak[2],
            .gx = gyro[0], .gy = gyro[1], .gz = gyro[2],
            .mag_x = last_mag[0], .mag_y = last_mag[1], .mag_z = last_mag[2],
            .piezo = max_piezo, .battery = battery_percentage,
        };
        int64_t now = esp_timer_get_time();
        if (now >= next_log_deadline) {
            ESP_LOGI(TAG, "SENS accel[m/s2]=(%.3f,%.3f,%.3f) gyro[rad/s]=(%.3f,%.3f,%.3f) mag[raw]=(%d,%d,%d) piezo[raw]=%u",
                     payload.ax, payload.ay, payload.az,
                     payload.gx, payload.gy, payload.gz,
                     payload.mag_x, payload.mag_y, payload.mag_z,
                     (unsigned)payload.piezo);

            int piezo_min = 4095, piezo_max = 0, piezo_sum = 0;
            int piezo_nonzero = 0, piezo_errors = 0;
            const int piezo_burst_count = 200;
            int64_t piezo_burst_start = esp_timer_get_time();
            for (int i = 0; i < piezo_burst_count; ++i) {
                int sample = 0;
                if (staysys_piezo_read(&sensors, &sample) != ESP_OK) {
                    ++piezo_errors;
                    continue;
                }
                if (sample < piezo_min) piezo_min = sample;
                if (sample > piezo_max) piezo_max = sample;
                piezo_sum += sample;
                if (sample != 0) ++piezo_nonzero;
            }
            int64_t piezo_burst_duration = esp_timer_get_time() - piezo_burst_start;
            int piezo_valid_count = piezo_burst_count - piezo_errors;
            ESP_LOGI(TAG, "PIEZO n=%d min=%d max=%d mean=%d nonzero=%d errs=%d dt_us=%lld",
                     piezo_burst_count,
                     piezo_valid_count ? piezo_min : 0,
                     piezo_max,
                     piezo_valid_count ? piezo_sum / piezo_valid_count : 0,
                     piezo_nonzero,
                     piezo_errors,
                     (long long)piezo_burst_duration);
            next_log_deadline = now + diagnostic_interval_us;
        }
        uint8_t packet[STASYS_PACKET_SIZE];
        staysys_packet_serialize(&payload, packet);
        EventBits_t link_bits = xEventGroupGetBits(app_events);
        if (!spp_congested && (link_bits & (BT_CONNECTED | BT_AUTHENTICATED)) == (BT_CONNECTED | BT_AUTHENTICATED)) {
            uint32_t handle;
            portENTER_CRITICAL(&spp_lock);
            handle = spp_handle;
            bool can_send = !spp_congested && handle != 0;
            portEXIT_CRITICAL(&spp_lock);
            if (can_send && !spp_write(handle, packet, sizeof(packet))) {
                reset_spp_state(true);
                esp_spp_disconnect(handle);
            }
        }
        int64_t remaining = deadline - esp_timer_get_time();
        if (remaining > 0) esp_rom_delay_us((uint32_t)remaining);
    }
}

static void battery_task(void *)
{
    while (true) {
        int sum = 0;
        int successful = 0;
        for (int i = 0; i < 16; ++i) {
            int raw = 0;
            if (staysys_battery_read(&sensors, &raw) == ESP_OK) {
                sum += raw;
                ++successful;
            }
        }
        if (successful > 0) {
            float voltage = (sum / (float)successful) / 4095.0f * 3.3f * STASYS_VOLTAGE_DIVIDER_RATIO;
            battery_percentage = (uint8_t)staysys_battery_percentage(voltage);
        }
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

extern "C" void app_main(void)
{
    esp_err_t nvs = nvs_flash_init();
    if (nvs == ESP_ERR_NVS_NO_FREE_PAGES || nvs == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs);
    app_events = xEventGroupCreate();
    if (app_events == NULL) abort();
    spp_tx_mutex = xSemaphoreCreateMutex();
    if (spp_tx_mutex == NULL) abort();
    ESP_ERROR_CHECK(staysys_sensors_init(&sensors));
    bt_init();
    TaskHandle_t sensor_handle = NULL;
    TaskHandle_t battery_handle = NULL;
    if (xTaskCreatePinnedToCore(sensor_task, "sensor", 6144, NULL, 1, &sensor_handle, 1) != pdPASS || sensor_handle == NULL) abort();
    if (xTaskCreatePinnedToCore(battery_task, "battery", 3072, NULL, 1, &battery_handle, 0) != pdPASS || battery_handle == NULL) abort();
    ESP_LOGI(TAG, "STASYS firmware %s starting (ESP-IDF app_main)", FIRMWARE_VERSION);
}
