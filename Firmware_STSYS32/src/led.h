// ============================================================
// led.h — LED Feedback Control
// ============================================================
#ifndef LED_H
#define LED_H

#include <stdint.h>
#include <stdbool.h>

enum class LEDMode {
    IDLE,
    CONNECTED,
    STREAMING,
    SHOT_DETECTED,
    CALIBRATING,
    LOW_BATTERY,
    ERROR
};

void  initLED();
void  setLEDMode(LEDMode mode);
void  triggerShotFeedback();
void  ledTask(void* param);

#endif  // LED_H
