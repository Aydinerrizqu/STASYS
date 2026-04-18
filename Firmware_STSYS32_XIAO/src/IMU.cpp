#include "config.h"
#include "data.h"
#include "globals.h"
#include <math.h>
// =============================================================================
// STSYS32 - LSM6DS3 IMU, Madgwick filter, BLE GATT streaming
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


// =============================================================================
// DEVICE INSTANCES  - defined here so the linker always includes them
// =============================================================================
LSM6DS3  imu(I2C_MODE, 0x6A);
Madgwick  madgwick;

// =============================================================================
// IMU CONFIGURATION
// =============================================================================
void configureIMU() {
  if (imu.begin() != 0) {
    Serial.println(F("[STSYS32-IMU] ERROR: begin() failed."));
    while (1) { digitalWrite(LED_RED, !digitalRead(LED_RED)); delay(200); }
  }

  // Accelerometer: 104 Hz, ±16 g  (CTRL1_XL)
  // ODR_XL=0100 (104Hz) | FS=01 (16g) = 0x44
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL1_XL, 0x44);

  // Gyroscope: 104 Hz, ±2000 dps  (CTRL2_G)
  // ODR_G=0100 (104Hz) | FS=11 (2000dps) = 0x4C
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL2_G, 0x4C);

  // BDU + auto-increment  (CTRL3_C)
  imu.writeRegister(LSM6DS3_ACC_GYRO_CTRL3_C, 0x44);

  // Disable FIFO (FIFO_CTRL5 = 0x00 = bypass mode)
  imu.writeRegister(LSM6DS3_ACC_GYRO_FIFO_CTRL5, 0x00);

  Serial.println(F("[STSYS32-IMU] Configured: 104Hz direct read | +-16g | +-2000dps | FIFO disabled"));
}

// =============================================================================
// DIRECT IMU READ
// =============================================================================
void readImuDirect() {
  static uint32_t readCount = 0;
  readCount++;

  if (readCount <= 5 || readCount % 500 == 0) {
    Serial.print(F("[STSYS32-IMU] Direct read #")); Serial.println(readCount);
  }

  uint16_t idx = traceTail % TRACE_BUF_SIZE;
  ImuSample& s = traceBuffer[idx];

  s.gx = imu.readFloatGyroX();
  s.gy = imu.readFloatGyroY();
  s.gz = imu.readFloatGyroZ();
  s.ax = imu.readFloatAccelX();
  s.ay = imu.readFloatAccelY();
  s.az = imu.readFloatAccelZ();
  s.timestamp = millis();

  // Debug: print first 10 samples raw values
  static uint32_t dbgCount = 0;
  dbgCount++;
  if (dbgCount <= 10) {
    Serial.print(F("[STSYS32-IMU-RAW] #")); Serial.print(dbgCount);
    Serial.print(F(" ax=")); Serial.print(s.ax, 4);
    Serial.print(F(" ay=")); Serial.print(s.ay, 4);
    Serial.print(F(" az=")); Serial.print(s.az, 4);
    Serial.print(F(" gx=")); Serial.print(s.gx, 4);
    Serial.print(F(" gy=")); Serial.print(s.gy, 4);
    Serial.print(F(" gz=")); Serial.print(s.gz, 4);
    Serial.println();
  }

  float mag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
  if (mag > peakAccelG)       peakAccelG = mag;
  if (mag > 0.05f)            lastMotionMs = millis();

  runMadgwick(s, idx);
  stateMachine(idx);
  traceTail++;

  if (bleConnected) sendTraceBle();
  if (bleConnected) sendAimTraceBle();
}

// =============================================================================
// MADGWICK FILTER + AIM REFERENCE SETTLING
// =============================================================================
static Quaternion quaternionNormalize(Quaternion q) {
  float mag = sqrtf(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
  if (mag < 1e-6f) return (Quaternion){1, 0, 0, 0};
  float inv = 1.0f / mag;
  return (Quaternion){ q.w * inv, q.x * inv, q.y * inv, q.z * inv };
}

void runMadgwick(ImuSample& s, uint16_t idx) {
  madgwick.updateIMU(s.gx, s.gy, s.gz, s.ax, s.ay, s.az);

  float r = madgwick.getRollRadians();
  float p = madgwick.getPitchRadians();
  float y = madgwick.getYawRadians();

  // Store raw Euler angles in sample
  s.pitch = p * RAD_TO_DEG;
  s.roll  = r * RAD_TO_DEG;
  s.yaw   = y * RAD_TO_DEG;

  float cr = cosf(r * 0.5f), sr = sinf(r * 0.5f);
  float cp = cosf(p * 0.5f), sp = sinf(p * 0.5f);
  float cy = cosf(y * 0.5f), sy = sinf(y * 0.5f);

  Quaternion q = {
    cr * cp * cy + sr * sp * sy,
    sr * cp * cy - cr * sp * sy,
    cr * sp * cy + sr * cp * sy,
    cr * cp * sy - sr * sp * cy
  };
  orientBuf[idx] = q;

  // ── Aim reference settling ────────────────────────────────────────────────
  if (!aimRefValid && fwState == STATE_AIMING) {
    float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    float gMag = sqrtf(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);

    if (aMag < AIM_SETTLE_ACCEL_MAX && gMag < AIM_SETTLE_GYRO_MAX) {
      aimSettleAccum.w += q.w;
      aimSettleAccum.x += q.x;
      aimSettleAccum.y += q.y;
      aimSettleAccum.z += q.z;
      aimSettleCount++;

      if (aimSettleCount >= AIM_SETTLE_SAMPLES) {
        aimRefQuat = quaternionNormalize(aimSettleAccum);
        aimRefValid = true;
        aimSettleCount = 0;
        aimSettleAccum = (Quaternion){0, 0, 0, 0};
        Serial.println(F("[STSYS32-AIM] Reference established"));
      }
    } else {
      // Motion interrupted - reset accumulation
      aimSettleCount = 0;
      aimSettleAccum = (Quaternion){0, 0, 0, 0};
    }
  }

  // ── Compute deviation from reference ────────────────────────────────────
  s.dPitch = 0.0f;
  s.dRoll  = 0.0f;
  if (aimRefValid) {
    // Shortest arc delta from reference
    float pitchRef = quaternionPitch(aimRefQuat);
    float rollRef  = quaternionRoll(aimRefQuat);
    float dPitch = s.pitch - pitchRef;
    float dRoll  = s.roll  - rollRef;
    // Wrap to ±180°
    if (dPitch >  180.0f) dPitch -= 360.0f;
    if (dPitch < -180.0f) dPitch += 360.0f;
    if (dRoll  >  180.0f) dRoll  -= 360.0f;
    if (dRoll  < -180.0f) dRoll  += 360.0f;
    s.dPitch = dPitch;
    s.dRoll  = dRoll;
  }
}

// =============================================================================
// BLE CALLBACKS
// =============================================================================
void bleConnectCallback(uint16_t connHandle) {
  bleConnected  = true;
  bleConnHandle = connHandle;
  BLEConnection* conn = Bluefruit.Connection(connHandle);
  conn->requestMtuExchange(BLE_MTU);
  conn->requestConnectionParameter(BLE_CONN_INTERVAL_MIN, BLE_CONN_INTERVAL_MAX);
  Serial.print(F("[STSYS32-BLE] Connected. Handle: ")); Serial.println(connHandle);
}

void bleDisconnectCallback(uint16_t connHandle, uint8_t reason) {
  (void)connHandle; (void)reason;
  bleConnected  = false;
  bleConnHandle = BLE_CONN_HANDLE_INVALID;
  Serial.println(F("[STSYS32-BLE] Disconnected"));
  Bluefruit.Advertising.start(0);
}

// =============================================================================
// BLE CONFIGURATION
// =============================================================================
void configureBLE() {
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("STASYS-1");
  Bluefruit.Periph.setConnectCallback(bleConnectCallback);
  Bluefruit.Periph.setDisconnectCallback(bleDisconnectCallback);

  stasysService.begin();

  traceChar.setProperties(CHR_PROPS_NOTIFY);
  traceChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  traceChar.setMaxLen(20);
  traceChar.begin();

  scoreChar.setProperties(CHR_PROPS_NOTIFY | CHR_PROPS_READ);
  scoreChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  scoreChar.setFixedLen(sizeof(ShotScore));
  scoreChar.begin();

  drawChar.setProperties(CHR_PROPS_NOTIFY | CHR_PROPS_READ);
  drawChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  drawChar.setFixedLen(sizeof(DrawMetrics));
  drawChar.begin();

  cmdChar.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  cmdChar.setPermission(SECMODE_NO_ACCESS, SECMODE_OPEN);
  cmdChar.setFixedLen(4);
  cmdChar.setWriteCallback(cmdWriteCallback);
  cmdChar.begin();

  aimTraceChar.setProperties(CHR_PROPS_NOTIFY);
  aimTraceChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  aimTraceChar.setFixedLen(sizeof(BleAimTrace));
  aimTraceChar.begin();

  stabilityChar.setProperties(CHR_PROPS_NOTIFY);
  stabilityChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  stabilityChar.setFixedLen(sizeof(StabilityScore));
  stabilityChar.begin();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(stasysService);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);
  Serial.println(F("[STSYS32-BLE] Advertising. GATT service live."));
}

// =============================================================================
// BLE TRACE STREAMING
// =============================================================================
void sendTraceBle() {
  if (!bleConnected || !traceChar.notifyEnabled()) return;

  static BleTraceSample pkt;
  static uint32_t notifCount = 0;

  while (traceHead != traceTail) {
    uint16_t i = traceHead % TRACE_BUF_SIZE;
    ImuSample& s = traceBuffer[i];
    traceHead++;

    ShotPhase phase = PHASE_BLUE;
    if (s.timestamp >= shotDetectedMs && s.timestamp < shotDetectedMs + RED_FOLLOW_THROUGH_MS) {
      phase = PHASE_RED;
    } else if (s.timestamp >= yellowStartMs && s.timestamp < shotDetectedMs) {
      phase = PHASE_YELLOW;
    }

    pkt.gx = (int16_t)(s.gx * GYRO_SCALE);
    pkt.gy = (int16_t)(s.gy * GYRO_SCALE);
    pkt.gz = (int16_t)(s.gz * GYRO_SCALE);
    pkt.ax = (int16_t)(s.ax * ACCEL_SCALE);
    pkt.ay = (int16_t)(s.ay * ACCEL_SCALE);
    pkt.az = (int16_t)(s.az * ACCEL_SCALE);
    pkt.phase    = (uint8_t)phase;
    pkt.reserved = 0;

    notifCount++;
    if (notifCount <= 5 || notifCount % 200 == 0) {
      Serial.print(F("[STSYS32-BLE] Trace notify #")); Serial.println(notifCount);
    }
    traceChar.notify((uint8_t*)&pkt, sizeof(pkt));
  }
}

// =============================================================================
// BLE AIM TRACE STREAMING (20Hz - every 5th sample)
// =============================================================================
void sendAimTraceBle() {
  if (!bleConnected || !aimTraceChar.notifyEnabled()) return;

  static BleAimTrace pkt;
  static uint8_t sampleIdx = 0;
  static uint8_t throttleCounter = 0;

  throttleCounter++;
  if (throttleCounter < 5) return;  // send every 5th sample = 20Hz
  throttleCounter = 0;

  // Stream the latest sample from the buffer
  uint16_t idx = (traceTail + TRACE_BUF_SIZE - 1) % TRACE_BUF_SIZE;
  ImuSample& s = traceBuffer[idx];

  pkt.dPitch    = (int16_t)(s.dPitch * 100.0f);   // x100 for 0.01° resolution
  pkt.dRoll     = (int16_t)(s.dRoll  * 100.0f);
  pkt.phase     = (uint8_t)PHASE_BLUE;
  if (s.timestamp >= shotDetectedMs && s.timestamp < shotDetectedMs + RED_FOLLOW_THROUGH_MS) {
    pkt.phase = (uint8_t)PHASE_RED;
  } else if (s.timestamp >= yellowStartMs && s.timestamp < shotDetectedMs) {
    pkt.phase = (uint8_t)PHASE_YELLOW;
  }
  pkt.sampleIdx = sampleIdx++;

  aimTraceChar.notify((uint8_t*)&pkt, sizeof(pkt));
}

// =============================================================================
// BLE COMMAND HANDLING
// =============================================================================
void cmdWriteCallback(uint16_t connHandle, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  (void)connHandle; (void)chr;
  handleBleCommand(data, len);
}

void handleBleCommand(uint8_t* data, uint16_t len) {
  if (len < 1) return;
  switch (data[0]) {
    case 0x01:
      rifleMode = false;
      Serial.println(F("[STSYS32-CMD] Mode: PISTOL"));
      break;
    case 0x02:
      rifleMode = true;
      Serial.println(F("[STSYS32-CMD] Mode: RIFLE"));
      break;
    case 0x10:
      fwState = STATE_IDLE;
      traceHead = traceTail = 0;
      Serial.println(F("[STSYS32-CMD] Session RESET"));
      break;
    case 0x20:
      Serial.println(F("[STSYS32-CMD] Force deep sleep"));
      enterDeepSleep();
      break;
    default:
      Serial.print(F("[STSYS32-CMD] Unknown: 0x")); Serial.println(data[0], HEX);
      break;
  }
}
