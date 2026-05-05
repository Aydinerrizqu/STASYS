#include "status_led.h"
#ifndef UNIT_TEST
#include <Arduino.h>
#include <driver/gpio.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#ifdef LED_TYPE_WS2812B
#include <Adafruit_NeoPixel.h>
static Adafruit_NeoPixel* strip = nullptr;
#else
// Discrete LED driver — two GPIO pins for blue and red
static bool g_blueState = false;
static bool g_redState = false;
#endif

static TaskHandle_t g_ledTaskHandle = NULL;
static volatile LedPattern_t g_currentPattern = LED_IDLE;
static volatile uint8_t g_diagBlinkCount = 0;
static bool g_initialized = false;

#define LED_TASK_STACK 2048

// Timing (ms)
#define BLINK_FAST_MS   200
#define BLINK_SLOW_MS   800

static void ledTask(void* parameter) {
    (void)parameter;
    TickType_t lastTick = xTaskGetTickCount();

    while (true) {
        LedPattern_t pattern = g_currentPattern;
        uint8_t diagCount = g_diagBlinkCount;

        // Handle diagnostic blink count (overrides pattern temporarily)
        if (diagCount > 0) {
#ifdef LED_TYPE_WS2812B
            if (strip) {
                strip->setPixelColor(0, 255, 0, 0); // Red for diagnostics
                strip->show();
            }
#else
            gpio_set_level((gpio_num_t)LED_RED_PIN, 1);
            gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
#endif
            vTaskDelay(pdMS_TO_TICKS(100));
#ifdef LED_TYPE_WS2812B
            if (strip) {
                strip->setPixelColor(0, 0, 0, 0);
                strip->show();
            }
#else
            gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
#endif
            g_diagBlinkCount--;
            lastTick = xTaskGetTickCount();
            vTaskDelay(pdMS_TO_TICKS(BLINK_FAST_MS));
            continue;
        }

        switch (pattern) {
            case LED_IDLE:
                // Slow blue blink: on for 300ms, off for 500ms
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(300));
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(BLINK_SLOW_MS));
                break;

            case LED_CONNECTING:
                // Fast blue blink
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(100));
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(BLINK_FAST_MS));
                break;

            case LED_STREAMING:
                // Solid blue
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(500));
                break;

            case LED_SENSOR_ERROR:
                // Red blink
                gpio_set_level((gpio_num_t)LED_RED_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(200));
                gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(BLINK_FAST_MS));
                break;

            case LED_LOW_BATTERY:
                // Orange (blue + red at reduced intensity via blink)
                gpio_set_level((gpio_num_t)LED_RED_PIN, 1);
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(150));
                gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(BLINK_FAST_MS));
                break;

            case LED_CRITICAL_BAT:
                // Solid red
                gpio_set_level((gpio_num_t)LED_RED_PIN, 1);
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(500));
                break;

            case LED_CHARGING:
                // Green — using blue+red off, this would be a special pattern
                // For discrete LEDs, use slow blue blink to indicate charging
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(500));
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(500));
                break;

            case LED_OTA_UPDATE:
                // Purple blink (red + blue together)
                gpio_set_level((gpio_num_t)LED_RED_PIN, 1);
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 1);
                vTaskDelay(pdMS_TO_TICKS(150));
                gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(BLINK_FAST_MS));
                break;

            case LED_OFF:
            default:
                gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
                gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
                vTaskDelay(pdMS_TO_TICKS(100));
                break;
        }
    }
}

void ledInit(void) {
    if (g_initialized) return;

#ifdef LED_TYPE_WS2812B
    strip = new Adafruit_NeoPixel(1, STATUS_LED_PIN, NEO_GRB + NEO_KHZ800);
    strip->begin();
    strip->setPixelColor(0, 0, 0, 0);
    strip->show();
#else
    gpio_set_direction((gpio_num_t)LED_BLUE_PIN, GPIO_MODE_OUTPUT);
    gpio_set_direction((gpio_num_t)LED_RED_PIN, GPIO_MODE_OUTPUT);
    gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
    gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
#endif

    xTaskCreatePinnedToCore(ledTask, "LedTask", LED_TASK_STACK, NULL, 0, &g_ledTaskHandle, 0);
    g_initialized = true;
    Serial.println("[LED] Initialized");
}

void ledSetPattern(LedPattern_t pattern) {
    if (!g_initialized) return;
    g_currentPattern = pattern;
}

LedPattern_t ledGetCurrentPattern(void) {
    return g_currentPattern;
}

void ledBlinkCount(uint8_t count) {
    g_diagBlinkCount = count;
}

void ledDeinit(void) {
    if (g_ledTaskHandle) {
        vTaskDelete(g_ledTaskHandle);
        g_ledTaskHandle = NULL;
    }
#ifdef LED_TYPE_WS2812B
    if (strip) {
        strip->setPixelColor(0, 0, 0, 0);
        strip->show();
        delete strip;
        strip = nullptr;
    }
#else
    gpio_set_level((gpio_num_t)LED_BLUE_PIN, 0);
    gpio_set_level((gpio_num_t)LED_RED_PIN, 0);
#endif
    g_initialized = false;
}

#endif  // UNIT_TEST