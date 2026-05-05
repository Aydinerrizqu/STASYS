#ifndef STATUS_LED_H
#define STATUS_LED_H

#include <stdint.h>
#include <stdbool.h>

#define LED_BLUE_PIN  2
#define LED_RED_PIN   4

typedef enum {
    LED_IDLE,
    LED_CONNECTING,
    LED_STREAMING,
    LED_SENSOR_ERROR,
    LED_LOW_BATTERY,
    LED_CRITICAL_BAT,
    LED_CHARGING,
    LED_OTA_UPDATE,
    LED_OFF
} LedPattern_t;

void ledInit(void);
void ledSetPattern(LedPattern_t pattern);
LedPattern_t ledGetCurrentPattern(void);
void ledBlinkCount(uint8_t count);
void ledDeinit(void);

#endif  // STATUS_LED_H