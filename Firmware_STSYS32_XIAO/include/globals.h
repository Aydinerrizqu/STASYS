#ifndef GLOBALS_H
#define GLOBALS_H

// =============================================================================
// STSYS32 - Globals for Seeed XIAO nRF52840 Sense
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


#include "config.h"
#include "data.h"
#include <math.h>

// =============================================================================
// HARDWARE INCLUDES � only available in embedded (Arduino) builds
// =============================================================================
#if defined(ARDUINO)
#include <bluefruit.h>
#include <LSM6DS3.h>
#include <MadgwickAHRS.h>
#elif defined(PLATFORMIO_NATIVE_TEST)
// native test build � use mocks from test/mocks/
#include "Arduino.h"
#include "firmware.h"
#else
// Standalone build: define minimal stubs
#include <stdint.h>
#include <stdbool.h>
#define RAD_TO_DEG (180.0f / M_PI)
#define constrain(val, lo, hi) ((val) < (lo) ? (lo) : (val) > (hi) ? (hi) : (val))
#define F(x) x
#define HEX 16
#define millis() ((uint32_t)0)
class MockSerial {
public:
    template<typename T> void print(T) {}
    template<typename T> void print(T, int) {}
    template<typename T> void println(T) {}
    template<typename T> void println(T, int) {}
    void println() {}
    void flush() {}
};
extern MockSerial Serial;
#endif

// =============================================================================
// FORWARD DECLARATIONS (implemented in other .cpp files)
// =============================================================================

// IMU.cpp
void configureIMU();
void readImuDirect();
void runMadgwick(ImuSample& s, uint16_t idx);
void configureBLE();
void sendTraceBle();
void sendAimTraceBle();
#ifdef ARDUINO
void cmdWriteCallback(uint16_t connHandle, BLECharacteristic* chr, uint8_t* data, uint16_t len);
#else
void cmdWriteCallback(uint16_t connHandle, void* chr, uint8_t* data, uint16_t len);
#endif
void handleBleCommand(uint8_t* data, uint16_t len);

// math.cpp
StabilityMetrics computeStability(const float* pitchBuf, const float* rollBuf, uint16_t count);
uint8_t stabilityToScore(float rmsDeviationDeg);

// PDM.cpp
void configurePDM();

// state.cpp
void stateMachine(uint16_t idx);
bool detectShot(uint16_t idx, bool* outLiveFire);
void finaliseShot(bool isLiveFire);
void analyseRecoil();
void analyseDrawStroke(ImuSample& s, uint16_t idx);

// power.cpp
bool isUsbPowered();
void checkBattery();
void updateLEDs();
void enterDeepSleep();

// math.cpp
float quaternionPitch(const Quaternion& q);
float quaternionRoll(const Quaternion& q);
float quaternionYaw(const Quaternion& q);
float angularDeviation(const Quaternion& a, const Quaternion& b);
uint8_t scoreFromDeviation(float d);

// =============================================================================
// DEVICE INSTANCES � only in Arduino builds
// =============================================================================
#ifdef ARDUINO
extern LSM6DS3  imu;
extern Madgwick madgwick;
#else
// Stub for native test builds
struct StubLSM6DS3 {
    int begin() { return 0; }
};
struct StubMadgwick {};
#define LSM6DS3 StubLSM6DS3
#define Madgwick StubMadgwick
#endif

// =============================================================================
// GLOBAL VARIABLES (defined in globals.cpp)
// =============================================================================

extern ImuSample   traceBuffer[TRACE_BUF_SIZE];
extern Quaternion  orientBuf[TRACE_BUF_SIZE];
extern volatile uint16_t traceTail;
extern volatile uint16_t traceHead;

extern uint32_t lastImuReadMs;
extern uint32_t yellowStartMs;
extern uint32_t shotDetectedMs;
extern uint32_t lastMotionMs;
extern uint32_t lastShotMs;

extern volatile FirmwareState fwState;
FirmwareState getFwState(void);
void setFwState(FirmwareState s);

extern Quaternion aimRefQuat;
extern bool      aimRefValid;
extern uint8_t   aimSettleCount;
extern Quaternion aimSettleAccum;

#define STABILITY_BUF_SIZE  100
extern float  stabilityPitchBuf[STABILITY_BUF_SIZE];
extern float  stabilityRollBuf[STABILITY_BUF_SIZE];
extern uint16_t stabilitySampleCount;

extern float    currentBatteryVoltage;
extern bool     usbPowered;
extern uint32_t lastBatteryCheckMs;

extern volatile float   peakAccelG;
extern volatile bool    audioSpikeDetected;
extern volatile uint32_t audioSpikeMs;

extern int16_t pdmBuffer[PDM_BUFFER_SIZE];

extern float   recoilStartPitch;
extern float   recoilStartRoll;
extern float   peakPitchDelta;
extern float   lateralMin;
extern float   lateralMax;
extern uint32_t recoilStartMs;
extern bool    recoilSettled;

extern RecoilMetrics lastRecoilMetrics;

extern DrawMetrics drawMetrics;
extern uint32_t    drawPhaseStartMs;

#ifdef ARDUINO
extern BLEService        stasysService;
extern BLECharacteristic traceChar;
extern BLECharacteristic scoreChar;
extern BLECharacteristic drawChar;
extern BLECharacteristic cmdChar;
extern BLECharacteristic aimTraceChar;
extern BLECharacteristic stabilityChar;
extern bool              bleConnected;
extern bool              rifleMode;
extern uint16_t          bleConnHandle;
#else
// Stubs for native/standalone builds
struct StubBLEService { template<typename T> void begin() {} };
struct StubBLEChar {
    template<typename T> void setProperties(T) {}
    template<typename T> void setPermission(T, T) {}
    void setMaxLen(size_t) {}
    void setFixedLen(size_t) {}
    template<typename T> void setWriteCallback(T) {}
    void begin() {}
    bool notifyEnabled() { return false; }
    void notify(const uint8_t*, size_t) {}
};
using BLEService = StubBLEService;
using BLECharacteristic = StubBLEChar;
extern BLECharacteristic traceChar;
extern BLECharacteristic scoreChar;
extern BLECharacteristic drawChar;
extern BLECharacteristic cmdChar;
extern BLECharacteristic aimTraceChar;
extern BLECharacteristic stabilityChar;
extern bool bleConnected;
extern bool rifleMode;
#define BLE_CONN_HANDLE_INVALID 0
extern uint16_t bleConnHandle;
#endif

#endif // GLOBALS_H