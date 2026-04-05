// ============================================================
// security.h — HMAC-SHA256 Auth, AES-128-CCM Encryption
// ============================================================
#ifndef SECURITY_H
#define SECURITY_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <esp_err.h>

// ================= AUTH STATE =================
enum class AuthState {
    UNAUTHENTICATED,
    CHALLENGE_SENT,
    AUTHENTICATED
};

struct SecurityState {
    AuthState auth_state;
    bool      link_encrypted;
    uint8_t   session_key[16];
    uint8_t   nonce[8];
    uint8_t   rx_nonce[8];
    uint32_t  session_id;
    uint8_t   challenge[16];
};

// ================= EXTERNALS =================
extern SecurityState g_secState;

// ================= FUNCTIONS =================
void     initSecurity();
bool     isLinkEncrypted();
void     generateChallenge(uint8_t* outChallenge);
bool     verifyAuthToken(const uint8_t* token, uint32_t session_id);
void     setSessionAuthenticated(uint32_t session_id);
bool     getDeviceSecret(uint8_t* outSecret, size_t* outLen);
bool     isDeviceSecretProvisioned();

#endif  // SECURITY_H
