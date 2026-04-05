// ============================================================
// session.cpp — Session State Management
// ============================================================
#include "session.h"
#include <Arduino.h>
#include <esp_timer.h>

SessionState g_sessionState = SessionState::IDLE;

SessionSummary g_lastSession = {
    .session_id = 0,
    .start_time_us = 0,
    .duration_ms = 0,
    .shot_count = 0,
    .battery_start = 0,
    .battery_end = 0,
    .sensor_health_flags = 0,
};

static uint16_t s_sessionShotCount = 0;

SessionState startSession(uint32_t session_id, uint8_t battery_pct) {
    if (g_sessionState != SessionState::IDLE) {
        Serial.printf("[SESSION] Cannot start: already in state %d\n", (int)g_sessionState);
        return g_sessionState;
    }

    g_sessionState = SessionState::STREAMING;
    g_lastSession.session_id = session_id;
    g_lastSession.start_time_us = esp_timer_get_time();
    g_lastSession.shot_count = 0;
    g_lastSession.battery_start = battery_pct;
    s_sessionShotCount = 0;

    Serial.printf("[SESSION] Started: id=%lu\n", (unsigned long)session_id);
    return g_sessionState;
}

SessionState stopSession() {
    if (g_sessionState != SessionState::STREAMING) {
        return g_sessionState;
    }

    g_sessionState = SessionState::STOPPING;

    uint32_t now_us = esp_timer_get_time();
    g_lastSession.duration_ms = (now_us - g_lastSession.start_time_us) / 1000;
    g_lastSession.shot_count = s_sessionShotCount;
    g_sessionState = SessionState::IDLE;

    Serial.printf("[SESSION] Stopped: %u shots in %lu ms\n",
                  s_sessionShotCount, (unsigned long)g_lastSession.duration_ms);

    return g_sessionState;
}

SessionState getSessionState() {
    return g_sessionState;
}

void addShotToSession(const ShotEvent* event) {
    if (g_sessionState == SessionState::STREAMING) {
        s_sessionShotCount++;
        g_lastSession.shot_count = s_sessionShotCount;
    }
}

SessionSummary getSessionSummary() {
    return g_lastSession;
}
