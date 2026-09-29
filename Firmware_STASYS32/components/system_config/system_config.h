/* DUPLICATE HEADER: this file is kept in sync with the other copy —
 * components/system_config.h and components/system_config/system_config.h.
 * sensors/sensor_hal.h includes this via the component include path;
 * system_config/system_config.c includes its local copy.
 * Edit both together (or delete one only after updating all includes).
 * See plan: docs/superpowers/plans/2026-09-28-stasys-firmware-esp-idf-port.md Task 3.
 */
#pragma once

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_adc/adc_oneshot.h"

#define STASYS_BATTERY_GPIO GPIO_NUM_39
#define STASYS_PIEZO_GPIO GPIO_NUM_35
#define STASYS_I2C_SDA GPIO_NUM_21
#define STASYS_I2C_SCL GPIO_NUM_22
#define STASYS_MPU_ADDR 0x68
#define STASYS_QMC_ADDR 0x2c
#define STASYS_HMC_ADDR 0x1e
#define STASYS_OVERSAMPLE_LOOPS 10
#define STASYS_PACKET_PERIOD_US 10000
#define STASYS_SENSOR_DELAY_US 400
#define STASYS_BATTERY_MIN_VOLTAGE 3.0f
#define STASYS_BATTERY_MAX_VOLTAGE 4.2f
#define STASYS_VOLTAGE_DIVIDER_RATIO 2.0f

typedef struct {
    i2c_master_bus_handle_t bus;
    i2c_master_dev_handle_t mpu;
    i2c_master_dev_handle_t qmc;
    i2c_master_dev_handle_t hmc;
    adc_oneshot_unit_handle_t adc1;
    adc_channel_t battery_channel;
    adc_channel_t piezo_channel;
    bool initialized;
    bool mpu_ready;
    bool qmc_present;
    bool hmc_present;
} staysys_hal_t;
