#include "madgwick.h"
#include <cmath>

void madgwickInit(MadgwickFilter* filter, float beta) {
    filter->orientation = quatIdentity();
    filter->beta = beta;
}

void madgwickUpdate(MadgwickFilter* filter, const float gyro[3], const float accel[3], float dt) {
    float ax = accel[0], ay = accel[1], az = accel[2];
    float gx = gyro[0], gy = gyro[1], gz = gyro[2];

    float accel_norm = sqrtf(ax*ax + ay*ay + az*az);
    if (accel_norm < 1e-10f) return;

    ax /= accel_norm; ay /= accel_norm; az /= accel_norm;

    float q0 = filter->orientation.w;
    float q1 = filter->orientation.x;
    float q2 = filter->orientation.y;
    float q3 = filter->orientation.z;

    float _2q0 = 2.0f * q0;
    float _2q1 = 2.0f * q1;
    float _2q2 = 2.0f * q2;
    float _2q3 = 2.0f * q3;
    float _4q0 = 4.0f * q0;
    float _4q1 = 4.0f * q1;
    float _4q2 = 4.0f * q2;
    float _8q1 = 8.0f * q1;
    float _8q2 = 8.0f * q2;
    float q0q0 = q0 * q0;
    float q1q1 = q1 * q1;
    float q2q2 = q2 * q2;
    float q3q3 = q3 * q3;

    float s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
    float s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
    float s2 = 4.0f * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
    float s3 = 4.0f * q1q1 * q3 - _2q1 * ax + 4.0f * q2q2 * q3 - _2q2 * ay;

    float s_norm = sqrtf(s0*s0 + s1*s1 + s2*s2 + s3*s3);
    if (s_norm > 1e-10f) {
        s0 /= s_norm; s1 /= s_norm; s2 /= s_norm; s3 /= s_norm;
    }

    float qDot0 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz) - filter->beta * s0;
    float qDot1 = 0.5f * (q0 * gx + q2 * gz - q3 * gy) - filter->beta * s1;
    float qDot2 = 0.5f * (q0 * gy - q1 * gz + q3 * gx) - filter->beta * s2;
    float qDot3 = 0.5f * (q0 * gz + q1 * gy - q2 * gx) - filter->beta * s3;

    q0 += qDot0 * dt;
    q1 += qDot1 * dt;
    q2 += qDot2 * dt;
    q3 += qDot3 * dt;

    float q_norm = sqrtf(q0*q0 + q1*q1 + q2*q2 + q3*q3);
    q0 /= q_norm; q1 /= q_norm; q2 /= q_norm; q3 /= q_norm;

    filter->orientation.w = q0;
    filter->orientation.x = q1;
    filter->orientation.y = q2;
    filter->orientation.z = q3;
}

Quaternion madgwickGetOrientation(MadgwickFilter* filter) {
    return filter->orientation;
}