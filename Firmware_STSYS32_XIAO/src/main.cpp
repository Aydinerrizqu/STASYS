#include <Arduino.h>
#include <Wire.h>
#include <PDM.h>
#include "config.h"
#include "data.h"
#include "globals.h"
// =============================================================================
// STSYS32 - Firmware entry point for Seeed XIAO nRF52840 Sense
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// Hardware: Seeed XIAO nRF52840 Sense + LSM6DS3 + PDM Mic + BLE
// =============================================================================


// =============================================================================
// SETUP
// =============================================================================
void setup() {
  Serial.begin(115200);
  uint32_t t = millis();
  while (!Serial && millis() - t < 2000) {}
  Serial.println(F("[STSYS32] Booting v3.0.0 (XIAO nRF52840 Sense)..."));

  pinMode(LED_RED,   OUTPUT); digitalWrite(LED_RED,   HIGH);
  pinMode(LED_GREEN, OUTPUT); digitalWrite(LED_GREEN, HIGH);
  pinMode(LED_BLUE,  OUTPUT); digitalWrite(LED_BLUE,  HIGH);

  pinMode(BAT_ENABLE_PIN, OUTPUT);
  digitalWrite(BAT_ENABLE_PIN, LOW);
  analogReference(AR_INTERNAL_3_0);
  analogReadResolution(12);

  Wire.begin();
  Wire.setClock(400000);

  configureIMU();
  configurePDM();

  madgwick.begin(IMU_ODR_HZ);

  configureBLE();

  lastMotionMs   = millis();
  lastImuReadMs  = millis();
  Serial.println(F("[STSYS32] Ready. Direct IMU @ 100Hz. Advertising BLE..."));
}

// =============================================================================
// MAIN LOOP
// =============================================================================
void loop() {
  // ── 1. IMU direct read at 100 Hz ─────────────────────────────────────────
  uint32_t now = millis();
  if (now - lastImuReadMs >= IMU_READ_INTERVAL_MS) {
    lastImuReadMs = now;
    readImuDirect();
  }

  // ── 2. Idle timeout ──────────────────────────────────────────────────────
  if (fwState == STATE_IDLE &&
      (millis() - lastMotionMs > MOTION_IDLE_TIMEOUT_MS)) {
    Serial.println(F("[STSYS32-PWR] Entering System OFF..."));
    delay(100);
    enterDeepSleep();
  }

  // ── 3. Battery + LEDs ─────────────────────────────────────────────────────
  checkBattery();
  updateLEDs();
}
