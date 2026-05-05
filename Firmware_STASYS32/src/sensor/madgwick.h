#pragma once
#include "quaternion.h"

/** @brief Madgwick AHRS filter */
typedef struct {
    Quaternion orientation;   /**< current orientation quaternion */
    float      beta;          /**< filter gain */
} MadgwickFilter;

/** @brief Initialize the filter.
    @param filter Pointer to the filter instance.
    @param beta   Filter gain (e.g., 0.1). */
void madgwickInit(MadgwickFilter* filter, float beta);

/** @brief Update the filter with new sensor data.
    @param filter Pointer to the filter instance.
    @param gyro   Gyroscope readings (rad/s) [x, y, z].
    @param accel  Accelerometer readings (g) [x, y, z].
    @param dt     Time step since last call (s). */
void madgwickUpdate(MadgwickFilter* filter,
                    const float gyro[3],
                    const float accel[3],
                    float dt);

/** @brief Retrieve the current orientation.
    @param filter Pointer to the filter instance.
    @return Orientation quaternion. */
Quaternion madgwickGetOrientation(MadgwickFilter* filter);