#include "sensor_hal.h"

#include <math.h>
#include <stdio.h>
#include <string.h>
#include "esp_err.h"
#include "esp_log.h"

static const char *TAG = "sensors";

static int read_register(i2c_master_dev_handle_t device, uint8_t reg,
                         uint8_t *data, size_t length)
{
    if (device == NULL || data == NULL || length == 0) return ESP_ERR_INVALID_ARG;
    return i2c_master_transmit_receive(device, &reg, 1, data, length, 20);
}

static int write_register(i2c_master_dev_handle_t device, uint8_t reg, uint8_t value)
{
    if (device == NULL) return ESP_ERR_INVALID_STATE;
    uint8_t data[] = {reg, value};
    return i2c_master_transmit(device, data, sizeof(data), 20);
}

void staysys_sensors_deinit(staysys_hal_t *hal)
{
    if (hal == NULL) return;
    if (hal->adc1 != NULL) {
        adc_oneshot_del_unit(hal->adc1);
        hal->adc1 = NULL;
    }
    if (hal->hmc != NULL) {
        i2c_master_bus_rm_device(hal->hmc);
        hal->hmc = NULL;
    }
    if (hal->qmc != NULL) {
        i2c_master_bus_rm_device(hal->qmc);
        hal->qmc = NULL;
    }
    if (hal->mpu != NULL) {
        i2c_master_bus_rm_device(hal->mpu);
        hal->mpu = NULL;
    }
    if (hal->bus != NULL) {
        i2c_del_master_bus(hal->bus);
        hal->bus = NULL;
    }
    hal->initialized = false;
    hal->mpu_ready = false;
    hal->qmc_present = false;
    hal->hmc_present = false;
}

int staysys_sensors_init(staysys_hal_t *hal)
{
    if (hal == NULL) return ESP_ERR_INVALID_ARG;
    memset(hal, 0, sizeof(*hal));
    i2c_master_bus_config_t bus_config = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = STASYS_I2C_SDA,
        .scl_io_num = STASYS_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags = {.enable_internal_pullup = true},
    };
    auto fail = [&](esp_err_t error) -> int { staysys_sensors_deinit(hal); return error; };
    esp_err_t err = i2c_new_master_bus(&bus_config, &hal->bus);
    if (err != ESP_OK) return fail(err);
    char scan[128] = {0};
    size_t scan_len = 0;
    for (int addr = 0x08; addr <= 0x77; ++addr) {
        if (i2c_master_probe(hal->bus, addr, 5) == ESP_OK) {
            scan_len += snprintf(scan + scan_len, sizeof(scan) - scan_len,
                                 "%s%02x", scan_len ? " " : "", addr);
        }
    }
    ESP_LOGI(TAG, "I2C scan: %s", scan_len ? scan : "no devices ACK");
    i2c_device_config_t mpu_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = STASYS_MPU_ADDR,
        .scl_speed_hz = 400000,
    };
    err = i2c_master_bus_add_device(hal->bus, &mpu_config, &hal->mpu);
    if (err != ESP_OK) return fail(err);
    uint8_t who_am_i = 0;
    err = read_register(hal->mpu, 0x75, &who_am_i, 1);
    if (err != ESP_OK || who_am_i != 0x68) {
        err = err == ESP_OK ? ESP_ERR_NOT_FOUND : err;
        return fail(err);
    }
    if (write_register(hal->mpu, 0x6b, 0x00) != ESP_OK ||
        write_register(hal->mpu, 0x1c, 0x08) != ESP_OK ||
        write_register(hal->mpu, 0x1b, 0x08) != ESP_OK ||
        write_register(hal->mpu, 0x1a, 0x00) != ESP_OK) {
        err = ESP_FAIL;
        return fail(err);
    }
    hal->mpu_ready = true;

    i2c_device_config_t qmc_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = STASYS_QMC_ADDR,
        .scl_speed_hz = 400000,
    };
    err = i2c_master_bus_add_device(hal->bus, &qmc_config, &hal->qmc);
    if (err == ESP_OK) {
        uint8_t chip_id = 0;
        hal->qmc_present = read_register(hal->qmc, 0x00, &chip_id, 1) == ESP_OK && chip_id == 0x80;
        if (hal->qmc_present && (write_register(hal->qmc, 0x0b, 0x00) != ESP_OK ||
                                 write_register(hal->qmc, 0x0a, 0x55) != ESP_OK)) {
            hal->qmc_present = false;
        }
        if (!hal->qmc_present) {
            i2c_master_bus_rm_device(hal->qmc);
            hal->qmc = NULL;
        }
    } else if (err != ESP_ERR_NOT_FOUND) {
        return fail(err);
    }
    ESP_LOGI(TAG, "mag probe: qmc@0x%02x present=%d", STASYS_QMC_ADDR, hal->qmc_present);
    if (hal->qmc_present) {
        uint8_t dump[13] = {0};
        int dump_err = read_register(hal->qmc, 0x00, dump, sizeof(dump));
        char hex[sizeof(dump) * 3 + 1] = {0};
        size_t hex_len = 0;
        for (size_t i = 0; i < sizeof(dump); ++i) {
            hex_len += snprintf(hex + hex_len, sizeof(hex) - hex_len, "%02x ", dump[i]);
        }
        ESP_LOGI(TAG, "mag dump@0x%02x err=%d: %s", STASYS_QMC_ADDR, dump_err, hex);
    }

    i2c_device_config_t hmc_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = STASYS_HMC_ADDR,
        .scl_speed_hz = 400000,
    };
    err = i2c_master_bus_add_device(hal->bus, &hmc_config, &hal->hmc);
    if (err == ESP_OK) {
        uint8_t id[3] = {0};
        int id_err = read_register(hal->hmc, 0x0a, id, sizeof(id));
        hal->hmc_present = id_err == ESP_OK &&
                           id[0] == 'H' && id[1] == '4' && id[2] == '3';
        if (hal->hmc_present && (write_register(hal->hmc, 0x00, 0x70) != ESP_OK ||
                                 write_register(hal->hmc, 0x01, 0x20) != ESP_OK ||
                                 write_register(hal->hmc, 0x02, 0x00) != ESP_OK)) {
            hal->hmc_present = false;
        }
        if (!hal->hmc_present) {
            i2c_master_bus_rm_device(hal->hmc);
            hal->hmc = NULL;
        }
        ESP_LOGI(TAG, "mag probe: hmc@0x%02x id_err=%d id=%02x%02x%02x present=%d",
                 STASYS_HMC_ADDR, id_err, id[0], id[1], id[2], hal->hmc_present);
    } else if (err != ESP_ERR_NOT_FOUND) {
        return fail(err);
    }

    adc_oneshot_unit_init_cfg_t adc_config = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    err = adc_oneshot_new_unit(&adc_config, &hal->adc1);
    if (err != ESP_OK) return fail(err);
    hal->battery_channel = ADC_CHANNEL_3;
    hal->piezo_channel = ADC_CHANNEL_7;
    adc_oneshot_chan_cfg_t channel_config = {
        .atten = ADC_ATTEN_DB_11,
        .bitwidth = ADC_BITWIDTH_12,
    };
    err = adc_oneshot_config_channel(hal->adc1, hal->battery_channel, &channel_config);
    if (err == ESP_OK) err = adc_oneshot_config_channel(hal->adc1, hal->piezo_channel, &channel_config);
    if (err != ESP_OK) return fail(err);
    hal->initialized = true;
    return ESP_OK;
}

int staysys_mpu_read(staysys_hal_t *hal, int16_t raw[6])
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    if (!hal->initialized || !hal->mpu_ready || hal->mpu == NULL) return ESP_ERR_INVALID_STATE;
    uint8_t data[14];
    if (read_register(hal->mpu, 0x3b, data, sizeof(data)) != ESP_OK) return ESP_FAIL;
    for (int i = 0; i < 3; ++i) raw[i] = (int16_t)((data[i * 2] << 8) | data[i * 2 + 1]);
    for (int i = 0; i < 3; ++i) raw[i + 3] = (int16_t)((data[8 + i * 2] << 8) | data[9 + i * 2]);
    return ESP_OK;
}

int staysys_qmc_read(staysys_hal_t *hal, int16_t raw[3])
{
    if (raw == NULL) return ESP_ERR_INVALID_ARG;
    memset(raw, 0, sizeof(int16_t) * 3);
    if (hal == NULL) return ESP_ERR_INVALID_ARG;
    if (!hal->initialized || !hal->qmc_present || hal->qmc == NULL) return ESP_ERR_INVALID_STATE;
    uint8_t data[6];
    if (read_register(hal->qmc, 0x01, data, sizeof(data)) != ESP_OK) {
        hal->qmc_present = false;
        return ESP_FAIL;
    }
    for (int i = 0; i < 3; ++i) raw[i] = (int16_t)((data[i * 2 + 1] << 8) | data[i * 2]);
    return ESP_OK;
}

int staysys_hmc_read(staysys_hal_t *hal, int16_t raw[3])
{
    if (raw == NULL) return ESP_ERR_INVALID_ARG;
    memset(raw, 0, sizeof(int16_t) * 3);
    if (hal == NULL) return ESP_ERR_INVALID_ARG;
    if (!hal->initialized || !hal->hmc_present || hal->hmc == NULL) return ESP_ERR_INVALID_STATE;
    uint8_t data[6];
    if (read_register(hal->hmc, 0x03, data, sizeof(data)) != ESP_OK) {
        hal->hmc_present = false;
        return ESP_FAIL;
    }
    raw[0] = (int16_t)((data[0] << 8) | data[1]);
    raw[1] = (int16_t)((data[4] << 8) | data[5]);
    raw[2] = (int16_t)((data[2] << 8) | data[3]);
    return ESP_OK;
}

int staysys_mag_read(staysys_hal_t *hal, int16_t raw[3])
{
    if (raw == NULL) return ESP_ERR_INVALID_ARG;
    memset(raw, 0, sizeof(int16_t) * 3);
    if (hal == NULL) return ESP_ERR_INVALID_ARG;
    if (hal->qmc_present) return staysys_qmc_read(hal, raw);
    if (hal->hmc_present) return staysys_hmc_read(hal, raw);
    return ESP_ERR_NOT_FOUND;
}

int staysys_piezo_read(staysys_hal_t *hal, int *raw)
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    if (!hal->initialized || hal->adc1 == NULL) return ESP_ERR_INVALID_STATE;
    return adc_oneshot_read(hal->adc1, hal->piezo_channel, raw);
}

int staysys_battery_read(staysys_hal_t *hal, int *raw)
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    if (!hal->initialized || hal->adc1 == NULL) return ESP_ERR_INVALID_STATE;
    return adc_oneshot_read(hal->adc1, hal->battery_channel, raw);
}

int staysys_battery_percentage(float voltage)
{
    if (!isfinite(voltage) || STASYS_BATTERY_MAX_VOLTAGE <= STASYS_BATTERY_MIN_VOLTAGE) return 0;
    if (voltage >= STASYS_BATTERY_MAX_VOLTAGE) return 100;
    if (voltage <= STASYS_BATTERY_MIN_VOLTAGE) return 0;
    return (int)(((voltage - STASYS_BATTERY_MIN_VOLTAGE) /
                  (STASYS_BATTERY_MAX_VOLTAGE - STASYS_BATTERY_MIN_VOLTAGE)) * 100.0f);
}
