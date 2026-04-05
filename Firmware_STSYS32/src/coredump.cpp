// ============================================================
// coredump.cpp — Crash Dump Storage (stub)
// ============================================================
#include "coredump.h"
#include <Arduino.h>
#include <esp_system.h>

bool coredumpIsAvailable() {
    return false;  // Stub: full impl uses esp_core_dump_image_* APIs
}

uint32_t coredumpGetSize() {
    return 0;
}

uint32_t coredumpRead(uint8_t* out, uint32_t offset, uint32_t len) {
    (void)out; (void)offset; (void)len;
    return 0;
}

void coredumpErase() {
    Serial.println("[COREDUMP] Erase (stub)");
}
