#pragma once
#include <cmath>

struct Quaternion {
    float w, x, y, z;
};

inline Quaternion quatIdentity() {
    return {1.0f, 0.0f, 0.0f, 0.0f};
}

inline float quatMagnitude(Quaternion q) {
    return std::sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
}

inline Quaternion quatNormalize(Quaternion q) {
    float mag = quatMagnitude(q);
    if (mag < 1e-6f) return quatIdentity();
    return {q.w / mag, q.x / mag, q.y / mag, q.z / mag};
}

inline Quaternion quatMultiply(Quaternion a, Quaternion b) {
    Quaternion r;
    r.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
    r.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
    r.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
    r.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
    return r;
}

inline Quaternion quatFromAxisAngle(const float axis[3], float angleRad) {
    float half = angleRad * 0.5f;
    float s = std::sin(half);
    float c = std::cos(half);
    // assume axis is already normalized
    Quaternion q;
    q.w = c;
    q.x = axis[0] * s;
    q.y = axis[1] * s;
    q.z = axis[2] * s;
    return q;
}

// Rotate vector v by quaternion q (q must be unit)
inline void quatRotateVector(Quaternion q, const float v[3], float out[3]) {
    // v' = q * (0, v) * q^{-1},  q^{-1} = conj(q) because q is unit
    float qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    float vx = v[0], vy = v[1], vz = v[2];

    // result = q * (0, v)
    float tx =  qw * vx + qy * vz - qz * vy;
    float ty =  qw * vy + qz * vx - qx * vz;
    float tz =  qw * vz + qx * vy - qy * vx;
    float tw = -qx * vx - qy * vy - qz * vz;

    // multiply by conj(q)
    out[0] = tw * (-qx) + tx * qw - ty * qz + tz * qy;
    out[1] = tw * (-qy) + ty * qw - tz * qx + tx * qz;
    out[2] = tw * (-qz) + tz * qw - tx * qy + ty * qx;
}

// Convert quaternion to Euler angles (roll, pitch, yaw) in radians
inline void quatToEuler(Quaternion q, float* roll, float* pitch, float* yaw) {
    // roll (x‑axis rotation)
    float sinr_cosp = 2.0f * (q.w * q.x + q.y * q.z);
    float cosr_cosp = 1.0f - 2.0f * (q.x * q.x + q.y * q.y);
    *roll = std::atan2(sinr_cosp, cosr_cosp);

    // pitch (y‑axis rotation)
    float sinp = 2.0f * (q.w * q.y - q.z * q.x);
    if (std::fabs(sinp) >= 1.0f)
        *pitch = std::copysign(3.14159265358979323846f / 2.0f, sinp); // use 90 degrees if out of range
    else
        *pitch = std::asin(sinp);

    // yaw (z‑axis rotation)
    float siny_cosp = 2.0f * (q.w * q.z + q.x * q.y);
    float cosy_cosp = 1.0f - 2.0f * (q.y * q.y + q.z * q.z);
    *yaw = std::atan2(siny_cosp, cosy_cosp);
}

// Create a quaternion from accelerometer reading assuming yaw = 0
inline Quaternion quatFromAccel(const float accel[3], float /*gravityMag*/) {
    // Normalize the acceleration vector (treated as gravity direction)
    float ax = accel[0], ay = accel[1], az = accel[2];
    float norm = std::sqrt(ax * ax + ay * ay + az * az);
    if (norm < 1e-6f) return quatIdentity();
    ax /= norm; ay /= norm; az /= norm;

    // Align local up (0,0,1) with measured gravity vector
    // Axis = cross(up, gravity), angle = acos(dot(up, gravity))
    float dot = az; // up is (0,0,1)
    float angle = std::acos(std::fmin(std::fmax(dot, -1.0f), 1.0f));
    if (angle < 1e-6f) return quatIdentity();

    float sinHalf = std::sin(angle * 0.5f);
    float cosHalf = std::cos(angle * 0.5f);

    // axis = (ay, -ax, 0) normalized (cross product of up and accel)
    float sx = ay;
    float sy = -ax;
    float sz = 0.0f;
    float sNorm = std::sqrt(sx * sx + sy * sy);
    if (sNorm < 1e-6f) {
        // accel is colinear with up, rotate around x or any perpendicular axis
        return {cosHalf, sinHalf, 0.0f, 0.0f};
    }
    Quaternion q;
    q.w = cosHalf;
    q.x = (sx / sNorm) * sinHalf;
    q.y = (sy / sNorm) * sinHalf;
    q.z = sz * sinHalf;
    return q;
}