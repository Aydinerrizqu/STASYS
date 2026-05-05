#include "calibration.h"
#include <math.h>
#include <string.h>

#define MAX_PASSES 3
#define SIGMA_THRESHOLD 3.0f

static struct {
    float gyroSamples[3][CAL_SAMPLE_BUF_SIZE];
    float accelSamples[3][CAL_SAMPLE_BUF_SIZE];
    uint16_t sampleIdx;
    uint16_t targetSamples;
    bool collecting;
    bool done;
    ImuCalibration result;
} g_cal;

static struct {
    float accelMags[ZUPT_WINDOW_SIZE];
    uint8_t headIdx;
    uint8_t count;
    bool initialized;
    float gyroBias[3];
} g_zupt;

void calibrationStart(uint16_t targetSamples) {
    memset(&g_cal, 0, sizeof(g_cal));
    g_cal.targetSamples = targetSamples;
    g_cal.collecting = true;
    g_cal.done = false;
}

void calibrationCollectSample(const float gyro[3], const float accel[3]) {
    if (!g_cal.collecting || g_cal.sampleIdx >= CAL_SAMPLE_BUF_SIZE) return;
    uint16_t idx = g_cal.sampleIdx;
    g_cal.gyroSamples[0][idx] = gyro[0];
    g_cal.gyroSamples[1][idx] = gyro[1];
    g_cal.gyroSamples[2][idx] = gyro[2];
    g_cal.accelSamples[0][idx] = accel[0];
    g_cal.accelSamples[1][idx] = accel[1];
    g_cal.accelSamples[2][idx] = accel[2];
    g_cal.sampleIdx++;
    if (g_cal.sampleIdx >= g_cal.targetSamples) {
        g_cal.collecting = false;
    }
}

static CalResult computeAxisStats(float axis_samples[CAL_SAMPLE_BUF_SIZE], uint16_t count, float gravityNormalize) {
    float mean = 0.0f, std = 1e9f;
    int16_t valid_idx[CAL_SAMPLE_BUF_SIZE];
    uint16_t valid_count = count;

    for (int pass = 0; pass < MAX_PASSES; pass++) {
        mean = 0.0f;
        for (uint16_t i = 0; i < valid_count; i++) mean += axis_samples[i];
        mean /= (float)valid_count;

        std = 0.0f;
        for (uint16_t i = 0; i < valid_count; i++) {
            float d = axis_samples[i] - mean;
            std += d * d;
        }
        std = sqrtf(std / (float)valid_count);

        if (pass < MAX_PASSES - 1) {
            uint16_t new_count = 0;
            for (uint16_t i = 0; i < valid_count; i++) {
                if (fabsf(axis_samples[i] - mean) <= SIGMA_THRESHOLD * std) {
                    valid_idx[new_count++] = i;
                }
            }
            if (new_count == valid_count) break;
            valid_count = new_count;
        }
    }

    mean = 0.0f;
    for (uint16_t i = 0; i < valid_count; i++) mean += axis_samples[i];
    mean /= (float)valid_count;

    std = 0.0f;
    for (uint16_t i = 0; i < valid_count; i++) {
        float d = axis_samples[i] - mean;
        std += d * d;
    }
    std = sqrtf(std / (float)valid_count);

    CalResult r = {mean, std};

    if (gravityNormalize > 0.0f) {
        float mag = sqrtf(
            g_cal.accelSamples[0][0]*g_cal.accelSamples[0][0] +
            g_cal.accelSamples[1][0]*g_cal.accelSamples[1][0] +
            g_cal.accelSamples[2][0]*g_cal.accelSamples[2][0]
        );
        (void)mag;
        float gx = 0.0f, gy = 0.0f, gz = 0.0f;
        for (uint16_t i = 0; i < valid_count; i++) {
            gx += g_cal.accelSamples[0][i];
            gy += g_cal.accelSamples[1][i];
            gz += g_cal.accelSamples[2][i];
        }
        gx /= valid_count; gy /= valid_count; gz /= valid_count;
        float accel_mag = sqrtf(gx*gx + gy*gy + gz*gz);
        if (accel_mag > 1e-10f) {
            float inv = 1.0f / accel_mag;
            float nx = gx * inv, ny = gy * inv, nz = gz * inv;
            r.bias = mean - (nx * gravityNormalize);
        }
    }

    return r;
}

bool calibrationFinish(uint16_t numSamples) {
    (void)numSamples;
    if (g_cal.sampleIdx == 0) return false;

    for (int axis = 0; axis < 3; axis++) {
        g_cal.result.gyro[axis] = computeAxisStats(g_cal.gyroSamples[axis], g_cal.sampleIdx, 0.0f);
    }
    for (int axis = 0; axis < 3; axis++) {
        g_cal.result.accel[axis] = computeAxisStats(g_cal.accelSamples[axis], g_cal.sampleIdx, GRAVITY_MAG);
    }

    g_cal.done = true;
    g_cal.collecting = false;
    g_cal.result.isCalibrated = true;
    return true;
}

CalResult calibrationComputeStats(const float* samples, uint16_t count) {
    float data[CAL_SAMPLE_BUF_SIZE];
    for (uint16_t i = 0; i < count && i < CAL_SAMPLE_BUF_SIZE; i++) data[i] = samples[i];
    return computeAxisStats(data, count, 0.0f);
}

bool calibrationIsDone(void) {
    return g_cal.done || g_cal.sampleIdx >= g_cal.targetSamples;
}

uint16_t calibrationGetCount(void) {
    return g_cal.sampleIdx;
}

void calibrationReset(void) {
    memset(&g_cal, 0, sizeof(g_cal));
}

ImuCalibration* calibrationGetResult(void) {
    return &g_cal.result;
}

void calibrationSetOffsets(const float gyroOff[3], const float accelOff[3]) {
    for (int i = 0; i < 3; i++) {
        g_cal.result.gyro[i].bias = gyroOff[i];
        g_cal.result.accel[i].bias = accelOff[i];
    }
    g_cal.result.isCalibrated = true;
}

void calibrationGetOffsets(float gyroOff[3], float accelOff[3]) {
    for (int i = 0; i < 3; i++) {
        gyroOff[i] = g_cal.result.gyro[i].bias;
        accelOff[i] = g_cal.result.accel[i].bias;
    }
}

void zuptInit(void) {
    memset(&g_zupt, 0, sizeof(g_zupt));
    g_zupt.initialized = true;
    g_zupt.gyroBias[0] = g_zupt.gyroBias[1] = g_zupt.gyroBias[2] = 0.0f;
}

bool zuptUpdate(const float accel[3]) {
    if (!g_zupt.initialized) zuptInit();

    float mag = sqrtf(accel[0]*accel[0] + accel[1]*accel[1] + accel[2]*accel[2]);
    g_zupt.accelMags[g_zupt.headIdx] = mag;
    g_zupt.headIdx = (g_zupt.headIdx + 1) % ZUPT_WINDOW_SIZE;
    if (g_zupt.count < ZUPT_WINDOW_SIZE) g_zupt.count++;

    if (g_zupt.count < 5) return false;

    float sum = 0.0f;
    for (uint8_t i = 0; i < g_zupt.count; i++) sum += g_zupt.accelMags[i];
    float mean = sum / g_zupt.count;

    float sum_sq = 0.0f;
    for (uint8_t i = 0; i < g_zupt.count; i++) {
        float d = g_zupt.accelMags[i] - mean;
        sum_sq += d * d;
    }
    float std = sqrtf(sum_sq / g_zupt.count);

    return std < ZUPT_STATIC_THRESHOLD;
}

bool zuptIsStatic(void) {
    if (!g_zupt.initialized || g_zupt.count < 5) return false;
    float sum = 0.0f;
    for (uint8_t i = 0; i < g_zupt.count; i++) sum += g_zupt.accelMags[i];
    float mean = sum / g_zupt.count;
    float sum_sq = 0.0f;
    for (uint8_t i = 0; i < g_zupt.count; i++) {
        float d = g_zupt.accelMags[i] - mean;
        sum_sq += d * d;
    }
    float std = sqrtf(sum_sq / g_zupt.count);
    return std < ZUPT_STATIC_THRESHOLD;
}

void zuptUpdateBias(const float gyro[3]) {
    for (int i = 0; i < 3; i++) {
        g_zupt.gyroBias[i] = (1.0f - ZUPT_ALPHA) * g_zupt.gyroBias[i] + ZUPT_ALPHA * gyro[i];
    }
}

float* zuptGetGyroBias(void) {
    return g_zupt.gyroBias;
}