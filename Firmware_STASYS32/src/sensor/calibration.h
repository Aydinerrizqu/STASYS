#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

#define GRAVITY_MAG 9.80665f

typedef struct {
    float bias;
    float stdDev;
} CalResult;

typedef struct {
    CalResult gyro[3];
    CalResult accel[3];
    bool isCalibrated;
} ImuCalibration;

#define CAL_SAMPLE_BUF_SIZE 500

void calibrationStart(uint16_t targetSamples);
void calibrationCollectSample(const float gyro[3], const float accel[3]);
bool calibrationFinish(uint16_t numSamples);
CalResult calibrationComputeStats(const float* samples, uint16_t count);
bool calibrationIsDone(void);
uint16_t calibrationGetCount(void);
void calibrationReset(void);
ImuCalibration* calibrationGetResult(void);

void calibrationSetOffsets(const float gyroOff[3], const float accelOff[3]);
void calibrationGetOffsets(float gyroOff[3], float accelOff[3]);

#define ZUPT_WINDOW_SIZE 50
#define ZUPT_STATIC_THRESHOLD 0.05f
#define ZUPT_ALPHA 0.01f

void zuptInit(void);
bool zuptUpdate(const float accel[3]);
bool zuptIsStatic(void);
void zuptUpdateBias(const float gyro[3]);
float* zuptGetGyroBias(void);

#ifdef __cplusplus
}
#endif