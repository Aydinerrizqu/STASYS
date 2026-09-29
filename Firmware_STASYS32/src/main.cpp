#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_random.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_spp_api.h"
#include "esp_bt_device.h"
#include "esp_mac.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "app_protocol.h"
#include "sensor_hal.h"
#include "driver/uart.h"
#include "provisioning.h"
#include <cmath>
#include <cstdio>
#include <cstring>

#define FIRMWARE_VERSION "2.0.0"
#define ENROLLMENT_WINDOW_MS (5 * 60 * 1000)  // documented in docs/provisioning.md

static const char *TAG = "stasys";
static EventGroupHandle_t app_events;
static staysys_hal_t sensors;
static volatile uint8_t battery_percentage;
static portMUX_TYPE spp_lock = portMUX_INITIALIZER_UNLOCKED;
static SemaphoreHandle_t spp_tx_mutex;
static uint32_t spp_handle;
static bool spp_congested;
static uint32_t spp_generation;
static uint8_t auth_nonce[STASYS_AUTH_NONCE_SIZE];
static char auth_rx[STASYS_AUTH_MAX_LINE + 1];
static size_t auth_rx_len;
static uint8_t auth_attempts;
static int64_t auth_deadline_us;

enum class spp_auth_state : uint8_t { DISCONNECTED, WAITING_FOR_PROOF, AUTHENTICATED };
static spp_auth_state auth_state = spp_auth_state::DISCONNECTED;

#define BT_CONNECTED BIT0
#define BT_AUTHENTICATED BIT1

extern "C" int staysys_provisioned_key(const uint8_t **key, size_t *key_len)
    __attribute__((weak));
static int device_key_provider(const uint8_t **key, size_t *key_len, void *)
{
    /* Production must override this with protected per-device provisioning.
     * The weak default deliberately fails closed and contains no credential. */
    if (staysys_provisioned_key == nullptr) return -1;
    return staysys_provisioned_key(key, key_len);
}

static bool spp_write(uint32_t handle, const uint8_t *data, size_t length)
{
    if (handle == 0 || data == nullptr || length == 0 || spp_tx_mutex == nullptr) return false;
    if (xSemaphoreTake(spp_tx_mutex, pdMS_TO_TICKS(100)) != pdTRUE) return false;
    esp_err_t result = esp_spp_write(handle, (int)length, const_cast<uint8_t *>(data));
    xSemaphoreGive(spp_tx_mutex);
    return result == ESP_OK;
}

static bool hex_decode(const char *input, size_t length, uint8_t *output, size_t output_len)
{
    if (input == nullptr || output == nullptr || length != output_len * 2u) return false;
    for (size_t i = 0; i < output_len; ++i) {
        auto nibble = [](char c) -> int {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            return -1;
        };
        int high = nibble(input[i * 2]);
        int low = nibble(input[i * 2 + 1]);
        if (high < 0 || low < 0) return false;
        output[i] = (uint8_t)((high << 4) | low);
    }
    return true;
}

static size_t build_auth_transcript(uint8_t *out, size_t capacity)
{
    uint8_t identity[6];
    esp_read_mac(identity, ESP_MAC_BT);
    const char domain[] = "STASYS-AUTH/v2\0";
    if (capacity < sizeof(domain) - 1 + sizeof(identity) + sizeof(spp_generation) + sizeof(auth_nonce)) return 0;
    size_t offset = 0;
    memcpy(out + offset, domain, sizeof(domain) - 1); offset += sizeof(domain) - 1;
    memcpy(out + offset, identity, sizeof(identity)); offset += sizeof(identity);
    uint32_t generation = spp_generation;
    memcpy(out + offset, &generation, sizeof(generation)); offset += sizeof(generation);
    memcpy(out + offset, auth_nonce, sizeof(auth_nonce)); offset += sizeof(auth_nonce);
    return offset;
}

static void reset_spp_state(bool clear_handle)
{
    portENTER_CRITICAL(&spp_lock);
    auth_state = spp_auth_state::DISCONNECTED;
    auth_rx_len = 0;
    auth_attempts = 0;
    auth_deadline_us = 0;
    memset(auth_nonce, 0, sizeof(auth_nonce));
    spp_congested = false;
    if (clear_handle) spp_handle = 0;
    portEXIT_CRITICAL(&spp_lock);
    xEventGroupClearBits(app_events, BT_CONNECTED | BT_AUTHENTICATED);
}

static void spp_callback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param)
{
    switch (event) {
    case ESP_SPP_INIT_EVT:
        esp_spp_start_srv(ESP_SPP_SEC_AUTHENTICATE | ESP_SPP_SEC_ENCRYPT, ESP_SPP_ROLE_SLAVE, 0, "STASYS");
        break;
    case ESP_SPP_SRV_OPEN_EVT: {
        if (xEventGroupGetBits(app_events) & BT_CONNECTED) {
            esp_spp_disconnect(param->srv_open.handle);
            break;
        }
        portENTER_CRITICAL(&spp_lock);
        ++spp_generation;
        if (spp_generation == 0) ++spp_generation;
        spp_handle = param->srv_open.handle;
        spp_congested = false;
        auth_rx_len = 0;
        auth_attempts = 0;
        auth_deadline_us = esp_timer_get_time() + (int64_t)STASYS_AUTH_TIMEOUT_MS * 1000;
        auth_state = spp_auth_state::WAITING_FOR_PROOF;
        for (size_t i = 0; i < sizeof(auth_nonce); i += sizeof(uint32_t)) {
            uint32_t random = esp_random();
            size_t count = sizeof(auth_nonce) - i;
            if (count > sizeof(random)) count = sizeof(random);
            memcpy(auth_nonce + i, &random, count);
        }
        uint32_t handle = spp_handle;
        portEXIT_CRITICAL(&spp_lock);
        xEventGroupSetBits(app_events, BT_CONNECTED);
        char nonce_hex[STASYS_AUTH_NONCE_SIZE * 2 + 1];
        static const char hex[] = "0123456789abcdef";
        for (size_t i = 0; i < sizeof(auth_nonce); ++i) {
            nonce_hex[i * 2] = hex[auth_nonce[i] >> 4];
            nonce_hex[i * 2 + 1] = hex[auth_nonce[i] & 0xf];
        }
        nonce_hex[sizeof(nonce_hex) - 1] = '\0';
        char greeting[sizeof(nonce_hex) + 40];
        int greeting_len = snprintf(greeting, sizeof(greeting),
                                    "READY v=%u gen=%u\nAUTH %s\n",
                                    STASYS_AUTH_VERSION, (unsigned)spp_generation, nonce_hex);
        if (greeting_len <= 0 || !spp_write(handle, (const uint8_t *)greeting, (size_t)greeting_len)) {
            esp_spp_disconnect(handle);
        }
        break;
    }
    case ESP_SPP_DATA_IND_EVT: {
        spp_auth_state state;
        uint32_t handle;
        int64_t deadline;
        portENTER_CRITICAL(&spp_lock);
        state = auth_state;
        handle = spp_handle;
        deadline = auth_deadline_us;
        portEXIT_CRITICAL(&spp_lock);
        if (state == spp_auth_state::AUTHENTICATED) break;
        if (state != spp_auth_state::WAITING_FOR_PROOF ||
            esp_timer_get_time() > deadline) {
            if (handle != 0) esp_spp_disconnect(handle);
            break;
        }
        for (uint16_t i = 0; i < param->data_ind.len; ++i) {
            uint8_t byte = param->data_ind.data[i];
            if (byte == '\n') {
                auth_rx[auth_rx_len] = '\0';
                const char prefix[] = "PROOF ";
                bool valid_line = auth_rx_len == sizeof(prefix) - 1 + STASYS_AUTH_PROOF_HEX_SIZE &&
                                  memcmp(auth_rx, prefix, sizeof(prefix) - 1) == 0;
                uint8_t received[STASYS_AUTH_PROOF_SIZE] = {0};
                uint8_t expected[STASYS_AUTH_PROOF_SIZE] = {0};
                uint8_t transcript[sizeof("STASYS-AUTH/v2\0") - 1 + 6 + 4 + STASYS_AUTH_NONCE_SIZE];
                const uint8_t *key = nullptr;
                size_t key_len = 0;
                size_t transcript_len = build_auth_transcript(transcript, sizeof(transcript));
                bool success = valid_line && hex_decode(auth_rx + sizeof(prefix) - 1,
                                                         STASYS_AUTH_PROOF_HEX_SIZE,
                                                         received, sizeof(received)) &&
                               staysys_auth_get_key(&key, &key_len) == 0 &&
                               transcript_len != 0 &&
                               staysys_auth_proof(key, key_len, transcript, transcript_len, expected) == 0 &&
                               staysys_constant_time_equal(received, expected, sizeof(received));
                staysys_secure_zero(expected, sizeof(expected));
                staysys_secure_zero(received, sizeof(received));
                staysys_secure_zero(transcript, sizeof(transcript));
                auth_rx_len = 0;
                if (success) {
                    auth_state = spp_auth_state::AUTHENTICATED;
                    xEventGroupSetBits(app_events, BT_AUTHENTICATED);
                    static const uint8_t ok[] = "OK\n";
                    if (!spp_write(handle, ok, sizeof(ok) - 1)) esp_spp_disconnect(handle);
                } else if (++auth_attempts >= STASYS_AUTH_MAX_ATTEMPTS) {
                    esp_spp_disconnect(handle);
                } else {
                    static const uint8_t fail[] = "FAIL\n";
                    (void)spp_write(handle, fail, sizeof(fail) - 1);
                }
            } else if (byte != '\r') {
                if (auth_rx_len >= STASYS_AUTH_MAX_LINE) {
                    auth_rx_len = 0;
                    if (++auth_attempts >= STASYS_AUTH_MAX_ATTEMPTS) esp_spp_disconnect(handle);
                } else {
                    auth_rx[auth_rx_len++] = (char)byte;
                }
            }
        }
        break;
    }
    case ESP_SPP_CONG_EVT:
        portENTER_CRITICAL(&spp_lock);
        spp_congested = param->cong.cong;
        portEXIT_CRITICAL(&spp_lock);
        break;
    case ESP_SPP_CLOSE_EVT:
        reset_spp_state(true);
        break;
    default:
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
    ESP_ERROR_CHECK(esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE));
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
            ESP_LOGI(TAG, "SENS accel[m/s2]=(%.3f,%.3f,%.3f) gyro[rad/s]=(%.3f,%.3f,%.3f) mag[raw]=(%d,%d,%d)",
                     payload.ax, payload.ay, payload.az,
                     payload.gx, payload.gy, payload.gz,
                     payload.mag_x, payload.mag_y, payload.mag_z);
            next_log_deadline = now + diagnostic_interval_us;
        }
        uint8_t packet[STASYS_PACKET_SIZE];
        staysys_packet_serialize(&payload, packet);
        if (!spp_congested && (xEventGroupGetBits(app_events) & BT_CONNECTED)) {
            uint32_t handle;
            portENTER_CRITICAL(&spp_lock);
            handle = spp_handle;
            bool can_send = auth_state == spp_auth_state::AUTHENTICATED && !spp_congested && handle != 0;
            portEXIT_CRITICAL(&spp_lock);
            if (can_send && !spp_write(handle, packet, sizeof(packet))) {
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

static void enrollment_task(void *)
{
    vTaskDelay(pdMS_TO_TICKS(ENROLLMENT_WINDOW_MS));
    esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_NON_DISCOVERABLE);
    ESP_LOGW(TAG, "enrollment window closed; device no longer discoverable");
    vTaskDelete(NULL);
}

static void provisioning_task(void *)
{
    uint8_t c;
    char line[96];
    size_t pos = 0;
    bool dropping = false;
    printf("PROVISION_READY\n");
    for (;;) {
        int n = uart_read_bytes(UART_NUM_0, &c, 1, pdMS_TO_TICKS(100));
        if (n <= 0) continue;
        if (c == '\n' || c == '\r') {
            if (dropping) {
                printf("PROVISION_ERR:line_too_long\n");
                memset(line, 0, sizeof(line));
            } else if (pos > 0) {
                line[pos] = '\0';
                if (strcmp(line, "PROVISION_STATUS") == 0) {
                    provisioning_print_status();
                } else {
                    provisioning_handle_line(line);
                }
                memset(line, 0, sizeof(line));
            }
            pos = 0;
            dropping = false;
        } else if (!dropping && pos < sizeof(line) - 1) {
            line[pos++] = (char)c;
        } else {
            dropping = true;
        }
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
    staysys_auth_set_key_provider(device_key_provider, nullptr);
    ESP_ERROR_CHECK(staysys_sensors_init(&sensors));
    if (xTaskCreatePinnedToCore(provisioning_task, "provision", 4096, NULL, 1, NULL, 0) != pdPASS) abort();
    bt_init();
    if (xTaskCreatePinnedToCore(enrollment_task, "enroll", 2048, NULL, 1, NULL, 0) != pdPASS) abort();
    TaskHandle_t sensor_handle = NULL;
    TaskHandle_t battery_handle = NULL;
    if (xTaskCreatePinnedToCore(sensor_task, "sensor", 6144, NULL, 1, &sensor_handle, 1) != pdPASS || sensor_handle == NULL) abort();
    if (xTaskCreatePinnedToCore(battery_task, "battery", 3072, NULL, 1, &battery_handle, 0) != pdPASS || battery_handle == NULL) abort();
    ESP_LOGI(TAG, "STASYS firmware %s starting (ESP-IDF app_main)", FIRMWARE_VERSION);
}
