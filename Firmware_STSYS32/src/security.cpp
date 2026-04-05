// security.cpp -- Auth module (stub for PlatformIO ESP32 build)
// REQUIRE_AUTH is disabled in main.cpp, auth flow not enforced
#include "security.h"
#include <Arduino.h>

SecurityState g_secState = {
    .auth_state = AuthState::UNAUTHENTICATED,
    .link_encrypted = false,
    .session_id = 0
};

void initSecurity() {
    g_secState.auth_state = AuthState::UNAUTHENTICATED;
    Serial.println("[SECURITY] Stub module loaded (auth disabled)");
}

void generateChallenge(uint8_t out[16]) {
    for (int i = 0; i < 16; i++) out[i] = random(256);
    memcpy(g_secState.challenge, out, 16);
    g_secState.auth_state = AuthState::CHALLENGE_SENT;
}

bool verifyAuthToken(const uint8_t token[32], uint32_t session_id) {
    // Auth verification skipped in stub mode
    g_secState.session_id = session_id;
    g_secState.auth_state = AuthState::AUTHENTICATED;
    return true;
}

void setSessionAuthenticated(uint32_t session_id) {
    g_secState.session_id = session_id;
    g_secState.auth_state = AuthState::AUTHENTICATED;
}

bool isLinkEncrypted() { return false; }

bool getDeviceSecret(uint8_t* out, size_t* outLen) { return false; }
bool isDeviceSecretProvisioned() { return false; }
