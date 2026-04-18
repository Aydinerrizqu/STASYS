#ifndef DATA_H
#define DATA_H

// =============================================================================
// STSYS32 - Data structures for Seeed XIAO nRF52840 Sense
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


#include <stdint.h>
#include <stdbool.h>

// =============================================================================
// IMU SAMPLE
// =============================================================================
struct ImuSample {
  float   ax, ay, az;
  float   gx, gy, gz;
  uint32_t timestamp;
  float   pitch, roll, yaw;   // Euler angles from Madgwick (degrees)
  float   dPitch, dRoll;      // deviation from aim reference (degrees)
};

// =============================================================================
// QUATERNION
// =============================================================================
struct Quaternion {
  float w, x, y, z;
};

// =============================================================================
// FIRMWARE STATE
// =============================================================================
enum FirmwareState {
  STATE_IDLE    = 0,
  STATE_AIMING  = 1,
  STATE_TRIGGER = 2,
  STATE_SHOT    = 3,
  STATE_RECOIL  = 4,
  STATE_DRAW    = 5
};

// =============================================================================
// SHOT PHASE
// =============================================================================
enum ShotPhase {
  PHASE_BLUE   = 0,
  PHASE_YELLOW = 1,
  PHASE_RED    = 2
};

// =============================================================================
// BLE TRACE PACKET
// =============================================================================
struct __attribute__((packed)) BleTraceSample {
  int16_t gx, gy, gz;
  int16_t ax, ay, az;
  uint8_t phase;
  uint8_t reserved;
};

// =============================================================================
// BLE AIM TRACE PACKET (live aim deviation)
// =============================================================================
struct __attribute__((packed)) BleAimTrace {
  int16_t dPitch;     // scaled x100 (0.01� resolution, range �327.67�)
  int16_t dRoll;      // scaled x100
  uint8_t phase;     // ShotPhase
  uint8_t sampleIdx;  // rolling counter
};

// =============================================================================
// STABILITY METRICS
// =============================================================================
struct StabilityMetrics {
  float  rmsDeviationDeg;
  float  maxDeviationDeg;
  float  stdDevPitchDeg;
  float  stdDevRollDeg;
  uint16_t sampleCount;
};

// =============================================================================
// STABILITY SCORE BLE PACKET
// =============================================================================
struct __attribute__((packed)) StabilityScore {
  uint8_t  score;                 // 0-100
  int16_t  rmsDeviationDeg_x100;
  int16_t  maxDeviationDeg_x100;
  int16_t  stdDevPitchDeg_x100;
  int16_t  stdDevRollDeg_x100;
};

// =============================================================================
// RECOIL METRICS
// =============================================================================
struct RecoilMetrics {
  float   muzzleRiseDeg;
  uint32_t recoveryTimeMs;
  float   recoilAngleDeg;
  float   recoilWidthDeg;
};

// =============================================================================
// DRAW METRICS
// =============================================================================
struct DrawMetrics {
  uint32_t gripTimeMs;
  uint32_t pullTimeMs;
  uint32_t rotationTimeMs;
  uint32_t acquisitionTimeMs;
  uint32_t totalTimeMs;
};

// =============================================================================
// SHOT SCORE
// =============================================================================
struct ShotScore {
  float   deviationDeg;
  uint8_t scorePercent;
  bool    isLiveFire;
  RecoilMetrics recoil;
};

#endif // DATA_H
