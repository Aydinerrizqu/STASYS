// ============================================================
// storage.cpp — Flash Session Storage
// ============================================================
#include "storage.h"
#include <Arduino.h>
#include <SPIFFS.h>

static bool s_storageInit = false;

void initStorage() {
    if (!s_storageInit) {
        if (!SPIFFS.begin(true)) {
            Serial.println("[STORAGE] SPIFFS mount failed");
        } else {
            Serial.println("[STORAGE] SPIFFS initialized");
            s_storageInit = true;
        }
    }
}

uint16_t enumerateSessions(uint32_t* ids, uint16_t maxCount) {
    if (!s_storageInit) return 0;
    // Stub: returns 0 sessions (full implementation writes session headers to SPIFFS)
    (void)ids;
    (void)maxCount;
    return 0;
}

bool loadSessionHeader(uint32_t session_id, SessionHeader* out) {
    (void)session_id; (void)out;
    return false;
}

uint16_t loadSession(uint32_t session_id, const SessionHeader* hdr,
                     struct ShotEvent* shots, uint16_t maxCount) {
    (void)session_id; (void)hdr; (void)shots; (void)maxCount;
    return 0;
}

bool deleteSession(uint32_t session_id) {
    (void)session_id;
    return false;
}
