// ============================================================
// led.cpp — LED Feedback Control
// ============================================================
#include "led.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#define LED_PIN 2  // Built-in LED on most ESP32 dev boards

static LEDMode s_currentMode = LEDMode::IDLE;
static bool s_shotFlashPending = false;

void initLED() {
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);
    Serial.println("[LED] Initialized on GPIO2");
}

void setLEDMode(LEDMode mode) {
    s_currentMode = mode;
    switch (mode) {
        case LEDMode::IDLE:
            digitalWrite(LED_PIN, LOW);  // Off
            break;
        case LEDMode::CONNECTED:
            digitalWrite(LED_PIN, HIGH);  // On (connected indicator)
            break;
        case LEDMode::STREAMING:
            // Slow blink
            digitalWrite(LED_PIN, HIGH);
            break;
        case LEDMode::SHOT_DETECTED:
            s_shotFlashPending = true;
            break;
        case LEDMode::CALIBRATING:
            // Fast blink
            break;
        case LEDMode::LOW_BATTERY:
            // Slow blink pattern
            break;
        case LEDMode::ERROR:
            // Rapid blink
            break;
    }
}

void triggerShotFeedback() {
    s_shotFlashPending = true;
}

void ledTask(void* param) {
    (void)param;
    uint32_t lastToggle = 0;
    bool ledState = false;

    for (;;) {
        uint32_t now = millis();
        LEDMode mode = s_currentMode;

        switch (mode) {
            case LEDMode::IDLE:
                digitalWrite(LED_PIN, LOW);
                break;

            case LEDMode::CONNECTED:
                digitalWrite(LED_PIN, HIGH);
                break;

            case LEDMode::STREAMING:
                // Slow blink (1Hz)
                if (now - lastToggle > 500) {
                    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
                    ledState = !ledState;
                    lastToggle = now;
                }
                break;

            case LEDMode::SHOT_DETECTED:
                // Flash pattern on shot
                digitalWrite(LED_PIN, HIGH);
                vTaskDelay(pdMS_TO_TICKS(50));
                digitalWrite(LED_PIN, LOW);
                s_shotFlashPending = false;
                break;

            case LEDMode::LOW_BATTERY:
                if (now - lastToggle > 2000) {
                    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
                    ledState = !ledState;
                    lastToggle = now;
                }
                break;

            case LEDMode::ERROR:
                if (now - lastToggle > 100) {
                    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
                    ledState = !ledState;
                    lastToggle = now;
                }
                break;

            default:
                break;
        }

        // Handle pending shot flash
        if (s_shotFlashPending && mode != LEDMode::SHOT_DETECTED) {
            digitalWrite(LED_PIN, HIGH);
            vTaskDelay(pdMS_TO_TICKS(50));
            digitalWrite(LED_PIN, LOW);
            s_shotFlashPending = false;
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
