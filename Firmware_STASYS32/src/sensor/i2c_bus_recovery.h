#ifndef I2C_BUS_RECOVERY_H
#define I2C_BUS_RECOVERY_H

#include <stdint.h>

/**
 * @brief Attempt to recover a stuck I2C bus by clocking out any stuck slave.
 *
 * Algorithm:
 *  1. Toggle SCL 9+ times to let any stuck slave release SDA
 *  2. Send START → STOP to clear any leftover bus state
 *
 * @param sdaPin GPIO pin used for SDA
 * @param sclPin GPIO pin used for SCL
 */
void recoverI2CBus(uint8_t sdaPin, uint8_t sclPin);

#endif // I2C_BUS_RECOVERY_H