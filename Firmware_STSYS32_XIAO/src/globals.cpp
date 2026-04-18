#include "config.h"
#include "data.h"
#include "globals.h"
// =============================================================================
// STSYS32 - Global variable definitions
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


#ifndef ARDUINO
// =============================================================================
// STUB INSTANCES � non-Arduino (native test / standalone) builds
// =============================================================================
ImuSample   traceBuffer[TRACE_BUF_SIZE];
Quaternion  orientBuf[TRACE_BUF_SIZE];
volatile uint16_t traceTail = 0;
volatile uint16_t traceHead = 0;

uint32_t lastImuReadMs = 0;
uint32_t yellowStartMs = 0;
uint32_t shotDetectedMs = 0;
uint32_t lastMotionMs = 0;
uint32_t lastShotMs = 0;

volatile FirmwareState fwState = STATE_IDLE;

// Accessors for test harness
FirmwareState getFwState(void) { return fwState; }
void setFwState(FirmwareState s) { fwState = s; }

Quaternion aimRefQuat = {1, 0, 0, 0};
bool       aimRefValid = false;
uint8_t    aimSettleCount = 0;
Quaternion aimSettleAccum = {0, 0, 0, 0};

float  stabilityPitchBuf[STABILITY_BUF_SIZE];
float  stabilityRollBuf[STABILITY_BUF_SIZE];
uint16_t stabilitySampleCount = 0;

float    currentBatteryVoltage = 4.2f;
bool     usbPowered = false;
uint32_t lastBatteryCheckMs = 0;

volatile float   peakAccelG = 0.0f;
volatile bool    audioSpikeDetected = false;
volatile uint32_t audioSpikeMs = 0;

int16_t pdmBuffer[PDM_BUFFER_SIZE];

float   recoilStartPitch = 0.0f;
float   recoilStartRoll  = 0.0f;
float   peakPitchDelta  = 0.0f;
float   lateralMin      = 0.0f;
float   lateralMax      = 0.0f;
uint32_t recoilStartMs  = 0;
bool    recoilSettled   = false;

RecoilMetrics lastRecoilMetrics = {0};

DrawMetrics drawMetrics;
uint32_t    drawPhaseStartMs = 0;

// Serial instance for non-Arduino native builds
MockSerialClass Serial;

StubBLEService stasysService;
StubBLEChar traceChar;
StubBLEChar scoreChar;
StubBLEChar drawChar;
StubBLEChar cmdChar;
StubBLEChar aimTraceChar;
StubBLEChar stabilityChar;

bool    bleConnected = false;
bool    rifleMode = false;
uint16_t bleConnHandle = 0;
#else
// =============================================================================
// GLOBAL VARIABLES (Arduino build)
// =============================================================================
ImuSample   traceBuffer[TRACE_BUF_SIZE];
Quaternion  orientBuf[TRACE_BUF_SIZE];
volatile uint16_t traceTail = 0;
volatile uint16_t traceHead = 0;

uint32_t lastImuReadMs = 0;
uint32_t yellowStartMs = 0;
uint32_t shotDetectedMs = 0;
uint32_t lastMotionMs = 0;
uint32_t lastShotMs = 0;

volatile FirmwareState fwState = STATE_IDLE;

// Accessors for test harness
FirmwareState getFwState(void) { return fwState; }
void setFwState(FirmwareState s) { fwState = s; }

Quaternion aimRefQuat = {1, 0, 0, 0};
bool       aimRefValid = false;
uint8_t    aimSettleCount = 0;
Quaternion aimSettleAccum = {0, 0, 0, 0};

float  stabilityPitchBuf[STABILITY_BUF_SIZE];
float  stabilityRollBuf[STABILITY_BUF_SIZE];
uint16_t stabilitySampleCount = 0;

float    currentBatteryVoltage = 4.2f;
bool     usbPowered = false;
uint32_t lastBatteryCheckMs = 0;

volatile float   peakAccelG = 0.0f;
volatile bool    audioSpikeDetected = false;
volatile uint32_t audioSpikeMs = 0;

int16_t pdmBuffer[PDM_BUFFER_SIZE];

float   recoilStartPitch = 0.0f;
float   recoilStartRoll  = 0.0f;
float   peakPitchDelta  = 0.0f;
float   lateralMin      = 0.0f;
float   lateralMax      = 0.0f;
uint32_t recoilStartMs  = 0;
bool    recoilSettled   = false;

RecoilMetrics lastRecoilMetrics = {0};

DrawMetrics drawMetrics;
uint32_t    drawPhaseStartMs = 0;

BLEService        stasysService(BLE_SERVICE_UUID);
BLECharacteristic traceChar(BLE_TRACE_CHAR_UUID);
BLECharacteristic scoreChar(BLE_SCORE_CHAR_UUID);
BLECharacteristic drawChar(BLE_DRAW_CHAR_UUID);
BLECharacteristic cmdChar(BLE_CMD_CHAR_UUID);
BLECharacteristic aimTraceChar(BLE_AIM_TRACE_CHAR_UUID);
BLECharacteristic stabilityChar(BLE_STABILITY_CHAR_UUID);

bool    bleConnected = false;
bool    rifleMode = false;
uint16_t bleConnHandle = BLE_CONN_HANDLE_INVALID;
#endif
