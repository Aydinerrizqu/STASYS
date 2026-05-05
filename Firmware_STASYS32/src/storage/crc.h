#ifndef CRC_H
#define CRC_H

#include <stdint.h>
#include <stddef.h>

uint16_t crc16_ccitt(const uint8_t* data, size_t len);
uint16_t crc16_ccitt_update(uint16_t crc, uint8_t data);

#endif  // CRC_H