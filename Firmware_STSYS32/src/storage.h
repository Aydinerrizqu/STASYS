// ============================================================
// storage.h — Flash Session Storage
// ============================================================
#ifndef STORAGE_H
#define STORAGE_H

#include <stdint.h>
#include <stdbool.h>
#include "protocol.h"

#define MAX_SESSIONS 32

struct SessionHeader {
    uint32_t session_id;
    uint32_t start_time_us;
    uint32_t duration_ms;
    uint16_t shot_count;
    uint8_t  battery_start;
    uint8_t  battery_end;
    uint8_t  sensor_health_flags;
};

// ================= FUNCTIONS =================
void     initStorage();
uint16_t enumerateSessions(uint32_t* ids, uint16_t maxCount);
bool     loadSessionHeader(uint32_t session_id, SessionHeader* out);
uint16_t loadSession(uint32_t session_id, const SessionHeader* hdr,
                     struct ShotEvent* shots, uint16_t maxCount);
bool     deleteSession(uint32_t session_id);

#endif  // STORAGE_H
