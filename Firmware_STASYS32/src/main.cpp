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
#include "app_protocol.h"
#include "sensor_hal.h"
#include <cmath>
#include <cstdio>
#include <cstring>

#define FIRMWARE_VERSION "2.0.0"

static const char *TAG = "stasys";
static EventGroupHandle_t app_events;
static staysys_hal_t sensors;
static volatile uint8_t battery_percentage;
static portMUX_TYPE spp_lock = portMUX_INITIALIZER_UNLOCKED;
static SemaphoreHandle_t spp_tx_mutex;
static uint32_t spp_handle;
static bool spp_congested;

#define BT_CONNECTED BIT0

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
    xEventGroupClearBits(app_events, BT_CONNECTED);
}

static void spp_callback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param)
{
    switch (event) {
    case ESP_SPP_INIT_EVT:
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
        static const uint8_t greeting[] = "READY v=2\n";
        if (!spp_write(handle, greeting, sizeof(greeting) - 1)) {
            reset_spp_state(true);
            esp_spp_disconnect(handle);
            break;
        }
        xEventGroupSetBits(app_events, BT_CONNECTED);
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
    // Stage 1: full-rate monitoring of candidate pins GPIO32 (ADC1 ch4) and
    // GPIO33 (ADC1 ch5), the only channels showing activity in the ADC scan.
    adc_oneshot_chan_cfg_t cand_config = {
        .atten = ADC_ATTEN_DB_11,
        .bitwidth = ADC_BITWIDTH_12,
    };
    adc_oneshot_config_channel(sensors.adc1, ADC_CHANNEL_4, &cand_config);
    adc_oneshot_config_channel(sensors.adc1, ADC_CHANNEL_5, &cand_config);
    int diag_max_gpio32 = 0;
    int diag_max_gpio33 = 0;
    while (true) {
        int64_t deadline = esp_timer_get_time() + STASYS_PACKET_PERIOD_US;
        have_mpu = false;

        float peak[3] = {0};
        float max_jerk = -1.0f;
        int64_t gyro_sum[3] = {0};
        int successful_mpu_reads = 0;
        uint16_t max_piezo = 0;
        for (int i = 0; i < STASYS_OVERSAMPLE_LOOPS; ++i) {
            int cand_sample = 0;
            if (adc_oneshot_read(sensors.adc1, ADC_CHANNEL_4, &cand_sample) == ESP_OK &&
                cand_sample > diag_max_gpio32) {
                diag_max_gpio32 = cand_sample;
            }
            cand_sample = 0;
            if (adc_oneshot_read(sensors.adc1, ADC_CHANNEL_5, &cand_sample) == ESP_OK &&
                cand_sample > diag_max_gpio33) {
                diag_max_gpio33 = cand_sample;
            }
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
            ESP_LOGI(TAG, "CAND gpio32=%d gpio33=%d", diag_max_gpio32, diag_max_gpio33);
            diag_max_gpio32 = 0;
            diag_max_gpio33 = 0;

            const adc_channel_t scan_channels[] = {
                ADC_CHANNEL_0, ADC_CHANNEL_1, ADC_CHANNEL_2, ADC_CHANNEL_3,
                ADC_CHANNEL_4, ADC_CHANNEL_5, ADC_CHANNEL_6, ADC_CHANNEL_7,
            };
            const int scan_gpios[] = {36, 37, 38, 39, 32, 33, 34, 35};
            adc_oneshot_chan_cfg_t scan_config = {
                .atten = ADC_ATTEN_DB_11,
                .bitwidth = ADC_BITWIDTH_12,
            };
            adc_oneshot_chan_cfg_t piezo_restore_config = {
                .atten = ADC_ATTEN_DB_11,
                .bitwidth = ADC_BITWIDTH_12,
            };
            for (int channel_index = 0; channel_index < 8; ++channel_index) {
                adc_channel_t channel = scan_channels[channel_index];
                if (channel == sensors.battery_channel) continue;
                int config_err = adc_oneshot_config_channel(sensors.adc1, channel, &scan_config);
                int channel_min = 4095, channel_max = 0;
                if (config_err == ESP_OK) {
                    for (int sample_index = 0; sample_index < 20; ++sample_index) {
                        int sample = 0;
                        if (adc_oneshot_read(sensors.adc1, channel, &sample) == ESP_OK) {
                            if (sample < channel_min) channel_min = sample;
                            if (sample > channel_max) channel_max = sample;
                        }
                    }
                } else {
                    channel_min = channel_max = -config_err;
                }
                ESP_LOGI(TAG, "ADCSCAN ch=%d gpio=%d min=%d max=%d",
                         (int)channel, scan_gpios[channel_index], channel_min, channel_max);
            }
            if (adc_oneshot_config_channel(sensors.adc1, sensors.piezo_channel,
                                           &piezo_restore_config) != ESP_OK) {
                ESP_LOGE(TAG, "failed to restore piezo ADC config");
            }
            next_log_deadline = now + diagnostic_interval_us;
        }
        uint8_t packet[STASYS_PACKET_SIZE];
        staysys_packet_serialize(&payload, packet);
        if (!spp_congested && (xEventGroupGetBits(app_events) & BT_CONNECTED)) {
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
