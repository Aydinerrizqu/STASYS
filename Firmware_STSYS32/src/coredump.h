// ============================================================
// coredump.h — Crash Dump Storage
// ============================================================
#ifndef COREDUMP_H
#define COREDUMP_H

#include <stdint.h>
#include <stdbool.h>

bool   coredumpIsAvailable();
uint32_t coredumpGetSize();
uint32_t coredumpRead(uint8_t* out, uint32_t offset, uint32_t len);
void    coredumpErase();

#endif  // COREDUMP_H
