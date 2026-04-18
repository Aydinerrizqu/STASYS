#include <Arduino.h>
#include <PDM.h>
#include <LSM6DS3.h>
#include <bluefruit.h>
#include "config.h"
#include "data.h"
#include "globals.h"
#include <math.h>
#ifdef ARDUINO
#include <nrf_power.h>
#include <nrf_gpio.h>
#endif

// =============================================================================
// STSYS32 - Power management, battery monitoring, LED state machine
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================

// =============================================================================
// POWER MANAGEMENT
// =============================================================================

bool isUsbPowered() {
  return nrf_power_usbregstatus_get(NRF_POWER) & NRF_POWER_USBREGSTATUS_VBUSDETECT_MASK;
}

void checkBattery() {
  if (millis() - lastBatteryCheckMs > 10000) {
    lastBatteryCheckMs = millis();
    usbPowered = isUsbPowered();

    if (usbPowered) {
      currentBatteryVoltage = 4.2f;
      Serial.println(F("[STSYS32-BAT] USB powered"));
      return;
    }

    int rawADC = analogRead(BAT_VOLT_PIN);
    currentBatteryVoltage = ((float)rawADC / 4095.0f) * 3.0f * 2.0f;

    Serial.print(F("[STSYS32-BAT] ")); Serial.print(currentBatteryVoltage, 2); Serial.println(F("V"));
    if (currentBatteryVoltage <= LOW_BATTERY_V) {
      Serial.println(F("[STSYS32-BAT] WARNING: Low!"));
    }
  }
}

void updateLEDs() {
  uint32_t now = millis();
  static uint32_t lastBlinkMs = 0;
  static bool blinkState = false;
  uint32_t blinkInterval = (currentBatteryVoltage <= LOW_BATTERY_V) ? 150 : 500;

  if (now - lastBlinkMs > blinkInterval) {
    blinkState = !blinkState;
    lastBlinkMs = now;
  }

  bool r = true, g = true, b = true;
  bool lowBat = (!usbPowered) && (currentBatteryVoltage <= LOW_BATTERY_V);

  if (lowBat) {
    if (blinkState) r = false;
  } else {
    switch (fwState) {
      case STATE_IDLE:
        if (bleConnected) { g = false; }
        else { if (blinkState) b = false; }
        break;
      case STATE_AIMING:   b = false; break;
      case STATE_TRIGGER:  r = false; g = false; break;
      case STATE_SHOT:
      case STATE_RECOIL:   r = false; break;
      case STATE_DRAW:     if (blinkState) { r = false; b = false; } break;
    }
  }

  digitalWrite(LED_RED,   r);
  digitalWrite(LED_GREEN, g);
  digitalWrite(LED_BLUE,  b);
}

void enterDeepSleep() {
  if (isUsbPowered())    { lastMotionMs = millis(); return; }
  if (bleConnected)      { lastMotionMs = millis(); return; }

  Bluefruit.Advertising.stop();
  PDM.end();

  // Configure IMU for wake-on-motion
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL1_XL, 0x10);  // Power down accel
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL2_G,  0x00);  // Power down gyro

  Serial.println(F("[PWR] Entering System OFF..."));
  Serial.flush();
  delay(10);
  digitalWrite(LED_RED, HIGH);
  digitalWrite(LED_GREEN, HIGH);
  digitalWrite(LED_BLUE, HIGH);

  nrf_power_system_off(NRF_POWER);
  __DSB();
  while (1) {}
}
