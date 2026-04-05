// ============================================================
// battery.cpp — Battery Monitoring
// ============================================================
#include "battery.h"
#include <Arduino.h>

#define BATTERY_PIN            39  // ADC1_CH3
#define VOLTAGE_DIVIDER_RATIO  2.0
#define BATTERY_MAX_VOLTAGE    4.2
#define BATTERY_MIN_VOLTAGE    3.0

static uint8_t s_batteryPercent = 100;
static bool s_isCharging = false;

BatteryStatus readBattery() {
    long sum = 0;
    for (int i = 0; i < 16; i++) sum += analogRead(BATTERY_PIN);
    float voltage = ((sum / 16.0) / 4095.0) * 3.3 * VOLTAGE_DIVIDER_RATIO;

    uint8_t percent = 100;
    if (voltage >= BATTERY_MAX_VOLTAGE) {
        percent = 100;
    } else if (voltage <= BATTERY_MIN_VOLTAGE) {
        percent = 0;
    } else {
        percent = (uint8_t)constrain(
            (int)((voltage - BATTERY_MIN_VOLTAGE) / (BATTERY_MAX_VOLTAGE - BATTERY_MIN_VOLTAGE) * 100.0),
            0, 100);
    }

    BatteryStatus st;
    st.voltage = voltage;
    st.percent = percent;
    st.isCharging = s_isCharging;
    st.isLow = (percent < 20);
    return st;
}

void initBattery() {
    pinMode(BATTERY_PIN, INPUT);
    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);
    updateBattery();
    Serial.printf("[BATTERY] Initialized: %d%%\n", getBatteryPercent());
}

void updateBattery() {
    BatteryStatus st = readBattery();
    s_batteryPercent = st.percent;
}

uint8_t getBatteryPercent() {
    return s_batteryPercent;
}
