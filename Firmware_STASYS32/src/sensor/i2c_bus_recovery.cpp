#include "i2c_bus_recovery.h"
#ifndef UNIT_TEST
#include <Arduino.h>
#include <driver/gpio.h>
#include <driver/i2c.h>
#include <rom/gpio.h>

void recoverI2CBus(uint8_t sdaPin, uint8_t sclPin) {
    // 1. Reconfigure both pins as GPIO outputs (disable open-drain/pull-up from I2C driver)
    gpio_set_direction((gpio_num_t)sdaPin, GPIO_MODE_OUTPUT_OD);
    gpio_set_direction((gpio_num_t)sclPin, GPIO_MODE_OUTPUT_OD);
    gpio_set_level((gpio_num_t)sdaPin, 1);
    gpio_set_level((gpio_num_t)sclPin, 1);
    delayMicroseconds(5);

    // 2. Toggle SCL 9+ times to clock out any stuck slave
    for (int i = 0; i < 10; i++) {
        gpio_set_level((gpio_num_t)sclPin, 0);
        delayMicroseconds(5);
        gpio_set_level((gpio_num_t)sclPin, 1);
        delayMicroseconds(5);
    }

    // 3. Send START condition: SDA 1→0 while SCL is high
    gpio_set_level((gpio_num_t)sdaPin, 1);
    delayMicroseconds(5);
    gpio_set_level((gpio_num_t)sclPin, 1);
    delayMicroseconds(5);
    gpio_set_level((gpio_num_t)sdaPin, 0);  // START
    delayMicroseconds(5);
    gpio_set_level((gpio_num_t)sclPin, 0);
    delayMicroseconds(5);

    // 4. Send STOP condition: SCL 0→1 while SDA is low
    gpio_set_level((gpio_num_t)sdaPin, 0);
    delayMicroseconds(5);
    gpio_set_level((gpio_num_t)sclPin, 1);
    delayMicroseconds(5);
    gpio_set_level((gpio_num_t)sdaPin, 1);  // STOP
    delayMicroseconds(5);

    // 5. Return pins to input state (I2C driver will reconfigure them)
    gpio_reset_pin((gpio_num_t)sdaPin);
    gpio_reset_pin((gpio_num_t)sclPin);
}

#endif  // UNIT_TEST