// ============================================================
// battery.h — Battery Monitoring
// ============================================================
#ifndef BATTERY_H
#define BATTERY_H

#include <stdint.h>
#include <stdbool.h>

struct BatteryStatus {
    float voltage;
    uint8_t percent;
    bool isCharging;
    bool isLow;
};

void     initBattery();
void     updateBattery();
uint8_t  getBatteryPercent();
BatteryStatus readBattery();

#endif  // BATTERY_H
