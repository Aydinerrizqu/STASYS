#include "config.h"
#include "data.h"
#include "globals.h"
#include <math.h>
// =============================================================================
// STSYS32 - State machine, shot detection, recoil & draw analysis
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


// =============================================================================
// SHOT DETECTION � with peak confirmation + debounce
// =============================================================================
bool detectShot(uint16_t idx, bool* outLiveFire) {
  ImuSample& s = traceBuffer[idx];
  float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);

  // Pre-filter already done by caller (s.az > SHOT_ACCEL_THRESHOLD_G)

  // Debounce: ignore shots too close together (skip if lastShotMs is 0 = no previous shot)
  if (lastShotMs > 0 && millis() - lastShotMs < SHOT_DEBOUNCE_MS) return false;

  // Look for peak within window
  uint16_t windowSamples = (uint16_t)((float)SHOT_ACCEL_PEAK_WINDOW_MS * IMU_ODR_HZ / 1000.0f);
  float peakMag = aMag;
  for (uint16_t i = 1; i < windowSamples; i++) {
    uint16_t checkIdx = (traceTail + TRACE_BUF_SIZE - 1 - i) % TRACE_BUF_SIZE;
    ImuSample& prev = traceBuffer[checkIdx];
    float prevMag = sqrtf(prev.ax * prev.ax + prev.ay * prev.ay + prev.az * prev.az);
    if (prevMag > peakMag) peakMag = prevMag;
  }

  // Peak must exceed minimum for real shot
  if (peakMag < SHOT_ACCEL_PEAK_MIN_G) return false;

  bool liveFire = false;
  if (audioSpikeDetected) {
    uint32_t dt = abs((int32_t)(s.timestamp - audioSpikeMs));
    if (dt < SHOT_WINDOW_MS) {
      audioSpikeDetected = false;
      liveFire = true;
    }
  }

  if (outLiveFire) *outLiveFire = liveFire;

  if (liveFire) {
    Serial.println(F("[STSYS32-SHOT] LIVE FIRE (IMU + audio)"));
  } else {
    Serial.println(F("[STSYS32-SHOT] DRY FIRE (IMU only)"));
  }
  return true;
}

// =============================================================================
// STATE MACHINE
// =============================================================================
void stateMachine(uint16_t idx) {
  ImuSample& s  = traceBuffer[idx];
  Quaternion& q = orientBuf[idx];

  float gMag = sqrtf(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
  float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);

  switch (fwState) {
    case STATE_IDLE:
      // Reset aim reference when going idle
      aimRefValid = false;
      aimSettleCount = 0;
      aimSettleAccum = (Quaternion){0, 0, 0, 0};
      if (gMag > 5.0f || aMag > 0.3f) {
        fwState = STATE_AIMING;
        stabilitySampleCount = 0;  // reset stability accumulation
        Serial.println(F("[STSYS32-STATE] -> AIMING (Blue)"));
      }
      if (s.az > 1.5f && aMag > 1.8f) {
        fwState = STATE_DRAW;
        drawPhaseStartMs = millis();
        drawMetrics = {0};
        Serial.println(F("[STSYS32-STATE] -> DRAW"));
      }
      break;

    case STATE_AIMING:
      // Accumulate stability samples
      if (stabilitySampleCount < STABILITY_MAX_SAMPLES) {
        stabilityPitchBuf[stabilitySampleCount] = s.dPitch;
        stabilityRollBuf[stabilitySampleCount]  = s.dRoll;
        stabilitySampleCount++;
      }

      if (gMag < 2.0f) {
        fwState       = STATE_TRIGGER;
        yellowStartMs = millis();
        Serial.println(F("[STSYS32-STATE] -> TRIGGER PRESS (Yellow)"));
      }
      if (s.az > SHOT_ACCEL_THRESHOLD_G && detectShot(idx, NULL)) {
        shotDetectedMs = s.timestamp;
        fwState = STATE_SHOT;
      }
      break;

    case STATE_TRIGGER:
      if (aMag > SHOT_ACCEL_THRESHOLD_G && detectShot(idx, NULL)) {
        shotDetectedMs = s.timestamp;
        fwState = STATE_SHOT;
        Serial.print(F("[STSYS32-STATE] -> SHOT. Pre-window: "));
        Serial.print(millis() - yellowStartMs);
        Serial.println(F("ms"));
      }
      if (gMag > 30.0f) { fwState = STATE_AIMING; }
      break;

    case STATE_SHOT: {
      bool isLiveFire = false;
      detectShot(idx, &isLiveFire);
      finaliseShot(isLiveFire);
      recoilStartPitch = quaternionPitch(q);
      recoilStartRoll  = quaternionRoll(q);
      peakPitchDelta = 0.0f;
      lateralMin     = 1000.0f;   // ensure first actual sample always updates
      lateralMax     = -1000.0f;  // ensure first actual sample always updates
      recoilStartMs  = millis();
      recoilSettled  = false;
      aimRefValid    = false;  // reset aim reference after shot
      fwState = STATE_RECOIL;
      Serial.println(F("[STSYS32-STATE] -> RECOIL (Red)"));
      break;
    }

    case STATE_RECOIL: {
      float dp = quaternionPitch(q) - recoilStartPitch;
      float dr = quaternionRoll(q)  - recoilStartRoll;
      if (dp > peakPitchDelta) peakPitchDelta = dp;
      if (dr < lateralMin)     lateralMin     = dr;
      if (dr > lateralMax)     lateralMax     = dr;
      if (gMag < 3.0f && !recoilSettled) recoilSettled = true;
      if (millis() - shotDetectedMs > RED_FOLLOW_THROUGH_MS) {
        analyseRecoil();
        peakAccelG = 0.0f;
        fwState = STATE_AIMING;
        stabilitySampleCount = 0;  // reset for next shot
        Serial.println(F("[STSYS32-STATE] -> AIMING (post-recoil)"));
      }
      break;
    }

    case STATE_DRAW:
      analyseDrawStroke(s, idx);
      break;
  }
}

// =============================================================================
// SHOT FINALISATION
// =============================================================================
void finaliseShot(bool isLiveFire) {
  lastShotMs = millis();

  uint16_t lookback = (uint16_t)((float)YELLOW_PRE_SHOT_MS * IMU_ODR_HZ / 1000.0f);
  uint16_t searIdx  = (traceTail + TRACE_BUF_SIZE - 1) % TRACE_BUF_SIZE;
  uint16_t refIdx   = (traceTail + TRACE_BUF_SIZE - 1 - lookback) % TRACE_BUF_SIZE;

  float deviation = angularDeviation(orientBuf[refIdx], orientBuf[searIdx]);
  float precision = rifleMode ? RIFLE_PRECISION_DEG : PISTOL_PRECISION_DEG;
  uint8_t score   = scoreFromDeviation(deviation / precision);

  ShotScore result;
  result.deviationDeg = deviation;
  result.scorePercent = score;
  result.isLiveFire   = isLiveFire;
  result.recoil       = lastRecoilMetrics;

  Serial.print(F("[STSYS32-SCORE] ")); Serial.print(deviation, 3);
  Serial.print(F("deg | ")); Serial.print(score); Serial.println(F("%"));

  if (bleConnected) scoreChar.notify((uint8_t*)&result, sizeof(result));

  // Compute and send stability score
  StabilityMetrics metrics = computeStability(stabilityPitchBuf, stabilityRollBuf, stabilitySampleCount);
  uint8_t stabScore = stabilityToScore(metrics.rmsDeviationDeg);

  StabilityScore stabResult;
  stabResult.score                  = stabScore;
  stabResult.rmsDeviationDeg_x100  = (int16_t)(metrics.rmsDeviationDeg  * 100.0f);
  stabResult.maxDeviationDeg_x100  = (int16_t)(metrics.maxDeviationDeg  * 100.0f);
  stabResult.stdDevPitchDeg_x100    = (int16_t)(metrics.stdDevPitchDeg   * 100.0f);
  stabResult.stdDevRollDeg_x100     = (int16_t)(metrics.stdDevRollDeg    * 100.0f);

  Serial.print(F("[STSYS32-STABILITY] Score:")); Serial.print(stabScore);
  Serial.print(F(" | RMS:")); Serial.print(metrics.rmsDeviationDeg, 3); Serial.println(F("deg"));

  if (bleConnected) stabilityChar.notify((uint8_t*)&stabResult, sizeof(stabResult));
}

// =============================================================================
// RECOIL ANALYSIS
// =============================================================================
void analyseRecoil() {
  uint32_t recovMs = recoilSettled ? (millis() - recoilStartMs) : RED_FOLLOW_THROUGH_MS;
  lastRecoilMetrics.muzzleRiseDeg  = peakPitchDelta;
  lastRecoilMetrics.recoveryTimeMs = recovMs;
  lastRecoilMetrics.recoilAngleDeg = (lateralMax + lateralMin) / 2.0f;
  lastRecoilMetrics.recoilWidthDeg = lateralMax - lateralMin;

  Serial.print(F("[STSYS32-RECOIL] Rise:")); Serial.print(lastRecoilMetrics.muzzleRiseDeg, 1);
  Serial.print(F("deg Recov:")); Serial.print(recovMs);
  Serial.println(F("ms"));
}

// =============================================================================
// DRAW STROKE ANALYSIS
// =============================================================================
void analyseDrawStroke(ImuSample& s, uint16_t idx) {
  (void)idx;
  static uint8_t drawSubPhase = 0;
  float gMag = sqrtf(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
  float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
  uint32_t now = millis();

  switch (drawSubPhase) {
    case 0:
      if (s.az > 2.0f) {
        drawMetrics.gripTimeMs = now - drawPhaseStartMs;
        drawPhaseStartMs = now;
        drawSubPhase = 1;
      }
      break;
    case 1:
      if (aMag > 1.5f && s.gy > 20.0f) {
        drawMetrics.pullTimeMs = now - drawPhaseStartMs;
        drawPhaseStartMs = now;
        drawSubPhase = 2;
      }
      break;
    case 2:
      if (gMag < 15.0f) {
        drawMetrics.rotationTimeMs = now - drawPhaseStartMs;
        drawPhaseStartMs = now;
        drawSubPhase = 3;
      }
      break;
    case 3:
      if (gMag < 5.0f && aMag < 0.2f) {
        drawMetrics.acquisitionTimeMs = now - drawPhaseStartMs;
        drawMetrics.totalTimeMs = drawMetrics.gripTimeMs + drawMetrics.pullTimeMs +
                                 drawMetrics.rotationTimeMs + drawMetrics.acquisitionTimeMs;
        Serial.print(F("[STSYS32-DRAW] Total:")); Serial.print(drawMetrics.totalTimeMs); Serial.println(F("ms"));
        if (bleConnected) drawChar.notify((uint8_t*)&drawMetrics, sizeof(drawMetrics));
        drawSubPhase = 0;
        fwState = STATE_AIMING;
      }
      break;
  }
}
