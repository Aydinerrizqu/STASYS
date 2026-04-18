#include "config.h"
#include "data.h"
#include "globals.h"
#include <math.h>
// =============================================================================
// STSYS32 - Quaternion math and stability metrics
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


// =============================================================================
// QUATERNION MATH
// =============================================================================

float quaternionPitch(const Quaternion& q) {
  float sinp = 2.0f * (q.w * q.y - q.z * q.x);
  sinp = constrain(sinp, -1.0f, 1.0f);
  return asinf(sinp) * RAD_TO_DEG;
}

float quaternionRoll(const Quaternion& q) {
  return atan2f(2.0f * (q.w * q.x + q.y * q.z), 1.0f - 2.0f * (q.x * q.x + q.y * q.y)) * RAD_TO_DEG;
}

float quaternionYaw(const Quaternion& q) {
  return atan2f(2.0f * (q.w * q.z + q.x * q.y), 1.0f - 2.0f * (q.z * q.z + q.y * q.y)) * RAD_TO_DEG;
}

float angularDeviation(const Quaternion& a, const Quaternion& b) {
  float dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
  dot = constrain(dot, -1.0f, 1.0f);
  return 2.0f * acosf(fabsf(dot)) * RAD_TO_DEG;
}

uint8_t scoreFromDeviation(float d) {
  if (d < 0.5f)  return 100;
  if (d > 10.0f) return 0;
  return (uint8_t)constrain(100.0f - (d - 0.5f) * (100.0f / 9.5f), 0.0f, 100.0f);
}

// =============================================================================
// STABILITY METRICS
// =============================================================================

StabilityMetrics computeStability(const float* pitchBuf, const float* rollBuf, uint16_t count) {
  StabilityMetrics m = {0};
  m.sampleCount = count;
  if (count == 0) return m;

  float sumPitch = 0.0f, sumRoll = 0.0f;
  float sumPitch2 = 0.0f, sumRoll2 = 0.0f;
  float maxDev = 0.0f;

  for (uint16_t i = 0; i < count; i++) {
    float p = pitchBuf[i];
    float r = rollBuf[i];
    sumPitch += p;
    sumRoll  += r;
    sumPitch2 += p * p;
    sumRoll2  += r * r;

    float dev = sqrtf(p * p + r * r);
    if (dev > maxDev) maxDev = dev;
  }

  float invN = 1.0f / (float)count;
  float meanPitch = sumPitch * invN;
  float meanRoll  = sumRoll  * invN;
  float varPitch  = (sumPitch2 * invN) - (meanPitch * meanPitch);
  float varRoll   = (sumRoll2  * invN) - (meanRoll  * meanRoll);

  m.stdDevPitchDeg   = sqrtf(varPitch > 0.0f ? varPitch : 0.0f);
  m.stdDevRollDeg    = sqrtf(varRoll  > 0.0f ? varRoll  : 0.0f);
  m.maxDeviationDeg  = maxDev;

  // RMS of combined deviation
  float rmsPitch = sqrtf(sumPitch2 * invN);
  float rmsRoll  = sqrtf(sumRoll2  * invN);
  m.rmsDeviationDeg = sqrtf(rmsPitch * rmsPitch + rmsRoll * rmsRoll);

  return m;
}

uint8_t stabilityToScore(float rmsDeviationDeg) {
  if (rmsDeviationDeg <= STABILITY_GOOD_DEG) return 100;
  if (rmsDeviationDeg >= STABILITY_POOR_DEG)  return 0;
  float t = (rmsDeviationDeg - STABILITY_GOOD_DEG) / (STABILITY_POOR_DEG - STABILITY_GOOD_DEG);
  return (uint8_t)constrain(100.0f * (1.0f - t), 0.0f, 100.0f);
}
