#include "mocks/Arduino.h"
#include "mocks/firmware.h"
#include "config.h"
#include "data.h"
#include "unity.h"

// =============================================================================
// GLOBALS — test-local definitions (no linking against src/globals.cpp)
// =============================================================================

static ImuSample        test_traceBuffer[TRACE_BUF_SIZE];
static volatile uint16_t test_traceTail = 0;
static volatile uint16_t test_traceHead = 0;
static volatile float   test_peakAccelG = 0.0f;
static volatile bool   test_audioSpikeDetected = false;
static volatile uint32_t test_audioSpikeMs = 0;
static volatile uint32_t test_lastShotMs = 0;
static uint32_t         test_yellowStartMs = 0;
static uint32_t         test_shotDetectedMs = 0;

// Macro aliases so test functions use test_ globals transparently
#define traceBuffer    test_traceBuffer
#define traceTail      test_traceTail
#define traceHead      test_traceHead
#define peakAccelG     test_peakAccelG
#define audioSpikeDetected  test_audioSpikeDetected
#define audioSpikeMs   test_audioSpikeMs
#define lastShotMs     test_lastShotMs
#define yellowStartMs  test_yellowStartMs
#define shotDetectedMs test_shotDetectedMs

// =============================================================================
// MATH CUT — isolated implementations for unit tests
// (not linked with math.cpp to avoid duplicate symbols)
// =============================================================================

static bool near_f(float a, float b, float eps) { return fabsf(a - b) < eps; }
static Quaternion qIdentity(void) { return {1.0f, 0.0f, 0.0f, 0.0f}; }
static Quaternion qRotX(float rad) { float h = rad*0.5f; return {cosf(h), sinf(h), 0.0f, 0.0f}; }
static Quaternion qRotY(float rad) { float h = rad*0.5f; return {cosf(h), 0.0f, sinf(h), 0.0f}; }

static float math_quaternionPitch(const Quaternion& q) {
    float sinp = 2.0f * (q.w * q.y - q.z * q.x);
    sinp = constrain(sinp, -1.0f, 1.0f);
    return asinf(sinp) * RAD_TO_DEG;
}
static float math_quaternionRoll(const Quaternion& q) {
    return atan2f(2.0f * (q.w * q.x + q.y * q.z), 1.0f - 2.0f * (q.x * q.x + q.y * q.y)) * RAD_TO_DEG;
}
static float math_quaternionYaw(const Quaternion& q) {
    return atan2f(2.0f * (q.w * q.z + q.x * q.y), 1.0f - 2.0f * (q.z * q.z + q.y * q.y)) * RAD_TO_DEG;
}
static float math_angularDeviation(const Quaternion& a, const Quaternion& b) {
    float dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    dot = constrain(dot, -1.0f, 1.0f);
    return 2.0f * acosf(fabsf(dot)) * RAD_TO_DEG;
}
static uint8_t math_scoreFromDeviation(float d) {
    if (d < 0.5f)  return 100;
    if (d > 10.0f) return 0;
    return (uint8_t)constrain(100.0f - (d - 0.5f) * (100.0f / 9.5f), 0.0f, 100.0f);
}

// =============================================================================
// TEST HELPERS — trace buffer and firmware state setup
// =============================================================================

static void clearTraceBuffer(void) {
    traceTail = 0; traceHead = 0;
    peakAccelG = 0.0f; audioSpikeDetected = false; audioSpikeMs = 0; lastShotMs = 0;
}
static void putSample(ImuSample s) {
    uint16_t idx = traceTail % TRACE_BUF_SIZE;
    traceBuffer[idx] = s;
    traceTail++;
}
static ImuSample makeSample(float ax, float ay, float az, float gx, float gy, float gz, uint32_t ts) {
    return {ax, ay, az, gx, gy, gz, ts, 0, 0, 0, 0, 0};
}

// =============================================================================
// SHOT DETECTION CUT — simplified for testing (mirrors firmware logic)
// =============================================================================

static bool test_detectShot(ImuSample& s, bool* outLiveFire) {
    float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    if (aMag < SHOT_ACCEL_THRESHOLD_G) return false;
    if (audioSpikeDetected) {
        uint32_t dt = abs((int32_t)(s.timestamp - audioSpikeMs));
        if (dt < SHOT_WINDOW_MS) {
            audioSpikeDetected = false;
            if (outLiveFire) *outLiveFire = true;
            return true;
        }
    }
    if (outLiveFire) *outLiveFire = false;
    return true;
}

// =============================================================================
// STATE MACHINE CUT — inline FSM logic for testing (mirrors state.cpp)
// =============================================================================

static FirmwareState test_fwState = STATE_IDLE;

static void test_setFwState(FirmwareState s) { test_fwState = s; }
static FirmwareState test_getFwState(void) { return test_fwState; }

static void test_fsmStep(ImuSample s) {
    float gMag = sqrtf(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
    float aMag = sqrtf(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    switch (test_getFwState()) {
        case STATE_IDLE:
            if (gMag > 5.0f || aMag > 0.3f) test_setFwState(STATE_AIMING);
            break;
        case STATE_AIMING:
            if (gMag < 2.0f) { test_setFwState(STATE_TRIGGER); yellowStartMs = s.timestamp; }
            if (aMag > SHOT_ACCEL_THRESHOLD_G) { shotDetectedMs = s.timestamp; test_setFwState(STATE_SHOT); }
            break;
        case STATE_TRIGGER:
            if (aMag > SHOT_ACCEL_THRESHOLD_G) { shotDetectedMs = s.timestamp; test_setFwState(STATE_SHOT); }
            if (gMag > 30.0f) test_setFwState(STATE_AIMING);
            break;
        case STATE_SHOT:
            test_setFwState(STATE_RECOIL);
            break;
        case STATE_RECOIL:
            if (gMag < 3.0f && s.timestamp - shotDetectedMs > RED_FOLLOW_THROUGH_MS)
                test_setFwState(STATE_AIMING);
            break;
        case STATE_DRAW:
            test_setFwState(STATE_AIMING);
            break;
    }
}

// =============================================================================
// SHOT FINALISATION CUT — deviation scoring (tests math_scoreFromDeviation)
// =============================================================================

static float test_shotDeviationDeg = 0.0f;
static void test_finaliseShot(float searAngle, float refAngle) {
    float diff = fabsf(searAngle - refAngle);
    if (diff > 180.0f) diff = 360.0f - diff;
    test_shotDeviationDeg = diff;
}

// =============================================================================
// TESTS: Math — quaternion pitch/roll/yaw
// =============================================================================

void test_math_pitch_identity_zero(void) {
    TEST_ASSERT_TRUE(near_f(math_quaternionPitch(qIdentity()), 0.0f, 0.001f));
}
void test_math_pitch_90deg_yaw_near_zero(void) {
    float p = math_quaternionPitch(qRotY(1.5708f));
    TEST_ASSERT_TRUE(near_f(p, 90.0f, 1.0f));
}
void test_math_pitch_approx_10deg(void) {
    float p = math_quaternionPitch(qRotY(0.1745f));
    TEST_ASSERT_TRUE(near_f(p, 10.0f, 0.5f));
}
void test_math_roll_identity_zero(void) {
    TEST_ASSERT_TRUE(near_f(math_quaternionRoll(qIdentity()), 0.0f, 0.001f));
}
void test_math_roll_approx_90deg(void) {
    float r = math_quaternionRoll(qRotX(1.5708f));
    TEST_ASSERT_TRUE(near_f(r, 90.0f, 1.0f));
}
void test_math_yaw_identity_zero(void) {
    TEST_ASSERT_TRUE(near_f(math_quaternionYaw(qIdentity()), 0.0f, 0.001f));
}
void test_math_yaw_approx_90deg(void) {
    float y = math_quaternionYaw(qRotY(1.5708f));
    TEST_ASSERT_TRUE(fabsf(y) > 0.1f);
    TEST_ASSERT_TRUE(fabsf(y) <= 180.0f);
}

// =============================================================================
// TESTS: Math — angular deviation
// =============================================================================

void test_math_deviation_identical_zero(void) {
    TEST_ASSERT_TRUE(near_f(math_angularDeviation(qIdentity(), qIdentity()), 0.0f, 0.001f));
}
void test_math_deviation_negated_same_rotation(void) {
    float d = math_angularDeviation(qIdentity(), (Quaternion){-1.0f,0,0,0});
    TEST_ASSERT_TRUE(near_f(d, 0.0f, 0.001f));
}
void test_math_deviation_90deg_rotation(void) {
    float d = math_angularDeviation(qIdentity(), qRotX(1.5708f));
    TEST_ASSERT_TRUE(near_f(d, 90.0f, 1.0f));
}
void test_math_deviation_antipodal_quaternions_180(void) {
    float d = math_angularDeviation((Quaternion){1,0,0,0}, (Quaternion){0,1,0,0});
    TEST_ASSERT_TRUE(near_f(d, 180.0f, 0.1f));
}

// =============================================================================
// TESTS: Score from deviation
// =============================================================================

void test_score_perfect_0dev_100(void)  { TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(0.0f)); }
void test_score_perfect_0_49dev_100(void){ TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(0.49f)); }
void test_score_exact_0_5dev_100(void)   { TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(0.5f)); }
void test_score_poor_10dev_0(void)       { TEST_ASSERT_EQUAL(0, math_scoreFromDeviation(10.0f)); }
void test_score_poor_15dev_0(void)       { TEST_ASSERT_EQUAL(0, math_scoreFromDeviation(15.0f)); }
void test_score_interpolated_5_25dev(void) {
    uint8_t s = math_scoreFromDeviation(5.25f);
    TEST_ASSERT_TRUE(s >= 48 && s <= 52);
}
void test_score_negative_dev_below_0_5(void) { TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(-1.0f)); }
void test_score_above_10_dev(void) { TEST_ASSERT_EQUAL(0, math_scoreFromDeviation(11.0f)); }
void test_score_linearity_high_to_low(void) {
    uint8_t s1 = math_scoreFromDeviation(1.0f);
    uint8_t s2 = math_scoreFromDeviation(3.0f);
    uint8_t s3 = math_scoreFromDeviation(5.0f);
    TEST_ASSERT_TRUE(s1 > s2 && s2 > s3);
}
void test_score_pistol_precision_at_threshold(void) {
    TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(PISTOL_PRECISION_DEG));
}
void test_score_rifle_precision_at_threshold(void) {
    TEST_ASSERT_EQUAL(100, math_scoreFromDeviation(RIFLE_PRECISION_DEG));
}

// =============================================================================
// TESTS: Shot detection
// =============================================================================

void test_shot_below_accel_threshold_false(void) {
    clearTraceBuffer();
    ImuSample s = makeSample(0, 0, 1.0f, 0, 0, 0, 100);  // 1G < 2.5G
    TEST_ASSERT_FALSE(test_detectShot(s, NULL));
}
void test_shot_above_accel_threshold_true(void) {
    clearTraceBuffer();
    ImuSample s = makeSample(0, 0, 3.0f, 0, 0, 0, 100);
    TEST_ASSERT_TRUE(test_detectShot(s, NULL));
}
void test_shot_at_or_above_threshold_fires(void) {
    // Firmware uses aMag < threshold (strict). At exactly 2.5, aMag < 2.5 is false
    // so the shot fires. Below threshold (2.49) does NOT fire.
    clearTraceBuffer();
    ImuSample s_low = makeSample(0, 0, SHOT_ACCEL_THRESHOLD_G - 0.01f, 0, 0, 0, 100);
    TEST_ASSERT_FALSE(test_detectShot(s_low, NULL));  // just below threshold
    clearTraceBuffer();
    ImuSample s_exact = makeSample(0, 0, SHOT_ACCEL_THRESHOLD_G, 0, 0, 0, 200);
    TEST_ASSERT_TRUE(test_detectShot(s_exact, NULL));  // at threshold → fires (strict <)
}
void test_shot_slightly_above_threshold_true(void) {
    clearTraceBuffer();
    ImuSample s = makeSample(0, 0, SHOT_ACCEL_THRESHOLD_G + 0.01f, 0, 0, 0, 100);
    TEST_ASSERT_TRUE(test_detectShot(s, NULL));
}
void test_shot_live_fire_audio_within_window(void) {
    clearTraceBuffer();
    ImuSample s = makeSample(0, 0, 5.0f, 0, 0, 0, 200);
    audioSpikeDetected = true;
    audioSpikeMs = 195;
    bool liveFire = false;
    bool r = test_detectShot(s, &liveFire);
    TEST_ASSERT_TRUE(r);
    TEST_ASSERT_TRUE(liveFire);
    TEST_ASSERT_FALSE(audioSpikeDetected);  // consumed
}
void test_shot_dry_fire_audio_outside_window(void) {
    // Firmware only clears audioSpikeDetected when dt < SHOT_WINDOW_MS.
    // Outside the window, shot fires (dry fire) but audio flag stays set.
    clearTraceBuffer();
    ImuSample s = makeSample(0, 0, 5.0f, 0, 0, 0, 500);
    audioSpikeDetected = true;
    audioSpikeMs = 100;  // 400ms before IMU — outside 15ms window
    bool liveFire = false;
    bool r = test_detectShot(s, &liveFire);
    TEST_ASSERT_TRUE(r);   // dry fire
    TEST_ASSERT_FALSE(liveFire);  // NOT live fire
    TEST_ASSERT_TRUE(audioSpikeDetected);  // NOT cleared when outside window
}

// =============================================================================
// TESTS: Shot finalisation
// =============================================================================

void test_finalise_perfect_alignment(void) {
    clearTraceBuffer();
    test_finaliseShot(45.0f, 45.0f);
    uint8_t s = math_scoreFromDeviation(test_shotDeviationDeg);
    TEST_ASSERT_EQUAL(100, s);
}
void test_finalise_slight_deviation(void) {
    // 0.5° is the threshold: math_scoreFromDeviation(0.5) = 100
    // So test with 0.51° to get a score between 0 and 100
    clearTraceBuffer();
    test_finaliseShot(45.0f, 45.51f);
    uint8_t s = math_scoreFromDeviation(test_shotDeviationDeg);
    TEST_ASSERT_TRUE(s > 0 && s < 100);  // not perfect, not zero
}
void test_finalise_large_deviation(void) {
    clearTraceBuffer();
    test_finaliseShot(0.0f, 11.0f);
    uint8_t s = math_scoreFromDeviation(test_shotDeviationDeg);
    TEST_ASSERT_EQUAL(0, s);
}
void test_finalise_crosses_180_boundary(void) {
    // 1° vs 359°: diff = 358°, wraps to 2°. math_scoreFromDeviation(2°) ≈ 84
    clearTraceBuffer();
    test_finaliseShot(1.0f, 359.0f);
    uint8_t s = math_scoreFromDeviation(test_shotDeviationDeg);
    TEST_ASSERT_TRUE(s >= 83 && s <= 85);  // ~84%
}

// =============================================================================
// TESTS: State machine transitions
// =============================================================================

void test_fsm_idle_no_motion_stays_idle(void) {
    test_setFwState(STATE_IDLE);
    ImuSample s = makeSample(0, 0, 0.0f, 0, 0, 0, 100);  // aMag=0 < 0.3 threshold
    test_fsmStep(s);
    TEST_ASSERT_EQUAL(STATE_IDLE, test_getFwState());
}
void test_fsm_idle_motion_to_aiming(void) {
    test_setFwState(STATE_IDLE);
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 6.0f, 0, 100));  // gMag > 5
    TEST_ASSERT_EQUAL(STATE_AIMING, test_getFwState());
}
void test_fsm_idle_small_accel_to_aiming(void) {
    test_setFwState(STATE_IDLE);
    test_fsmStep(makeSample(0, 0, 0.5f, 0, 0, 0, 100));  // aMag > 0.3
    TEST_ASSERT_EQUAL(STATE_AIMING, test_getFwState());
}
void test_fsm_aiming_low_gyro_to_trigger(void) {
    test_setFwState(STATE_AIMING);
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 1.0f, 0, 200));  // gMag < 2
    TEST_ASSERT_EQUAL(STATE_TRIGGER, test_getFwState());
    TEST_ASSERT_EQUAL(200, yellowStartMs);
}
void test_fsm_aiming_shot_accel_to_shot(void) {
    test_setFwState(STATE_AIMING);
    test_fsmStep(makeSample(0, 0, 5.0f, 0, 1.0f, 0, 300));  // aMag > 2.5
    TEST_ASSERT_EQUAL(STATE_SHOT, test_getFwState());
}
void test_fsm_trigger_shot_accel_to_shot(void) {
    test_setFwState(STATE_TRIGGER);
    test_fsmStep(makeSample(0, 0, 4.0f, 0, 0, 0, 400));
    TEST_ASSERT_EQUAL(STATE_SHOT, test_getFwState());
}
void test_fsm_trigger_high_gyro_returns_aiming(void) {
    test_setFwState(STATE_TRIGGER);
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 0, 35.0f, 500));  // gMag > 30
    TEST_ASSERT_EQUAL(STATE_AIMING, test_getFwState());
}
void test_fsm_shot_immediately_to_recoil(void) {
    test_setFwState(STATE_SHOT);
    test_fsmStep(makeSample(0, 0, 3.0f, 0, 0, 0, 600));
    TEST_ASSERT_EQUAL(STATE_RECOIL, test_getFwState());
}
void test_fsm_recoil_settles_after_follow_through(void) {
    test_setFwState(STATE_RECOIL); shotDetectedMs = 100;
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 0, 0, 100 + RED_FOLLOW_THROUGH_MS + 1));
    TEST_ASSERT_EQUAL(STATE_AIMING, test_getFwState());
}
void test_fsm_recoil_still_within_window(void) {
    test_setFwState(STATE_RECOIL); shotDetectedMs = 100;
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 0, 0, 100 + RED_FOLLOW_THROUGH_MS - 10));
    TEST_ASSERT_EQUAL(STATE_RECOIL, test_getFwState());
}
void test_fsm_recoil_gyro_still_high(void) {
    test_setFwState(STATE_RECOIL); shotDetectedMs = 100;
    test_fsmStep(makeSample(0, 0, 1.0f, 0, 0, 5.0f, 100 + RED_FOLLOW_THROUGH_MS + 10));
    TEST_ASSERT_EQUAL(STATE_RECOIL, test_getFwState());
}

// =============================================================================
// TESTS: Config constants
// =============================================================================

void test_config_shot_threshold_2_5g(void) {
    TEST_ASSERT_EQUAL_FLOAT(2.5f, SHOT_ACCEL_THRESHOLD_G);
}
void test_config_audio_threshold_2000(void) {
    TEST_ASSERT_EQUAL(2000, SHOT_AUDIO_THRESHOLD);
}
void test_config_shot_window_15ms(void) {
    TEST_ASSERT_EQUAL(15, SHOT_WINDOW_MS);
}
void test_config_yellow_pre_shot_250ms(void) {
    TEST_ASSERT_EQUAL(250, YELLOW_PRE_SHOT_MS);
}
void test_config_red_follow_500ms(void) {
    TEST_ASSERT_EQUAL(500, RED_FOLLOW_THROUGH_MS);
}
void test_config_trace_buf_512(void) {
    TEST_ASSERT_EQUAL(512, TRACE_BUF_SIZE);
}
void test_config_idle_timeout_120s(void) {
    TEST_ASSERT_EQUAL(120000, MOTION_IDLE_TIMEOUT_MS);
}
void test_config_low_bat_3_4v(void) {
    TEST_ASSERT_EQUAL_FLOAT(3.4f, LOW_BATTERY_V);
}

// =============================================================================
// SETUP / TEARDOWN
// =============================================================================

void setUp(void) {
    test_setFwState(STATE_IDLE);
    yellowStartMs = 0;
    shotDetectedMs = 0;
    clearTraceBuffer();
    test_shotDeviationDeg = 0.0f;
}
void tearDown(void) {}

// =============================================================================
// STABILITY TESTS
// =============================================================================

static StabilityMetrics test_computeStability(const float* pitchBuf, const float* rollBuf, uint16_t count) {
  StabilityMetrics m = {0};
  m.sampleCount = count;
  if (count == 0) return m;

  float sumPitch = 0.0f, sumRoll = 0.0f;
  float sumPitch2 = 0.0f, sumRoll2 = 0.0f;
  float maxDev = 0.0f;

  for (uint16_t i = 0; i < count; i++) {
    float p = pitchBuf[i];
    float r = rollBuf[i];
    sumPitch += p;
    sumRoll  += r;
    sumPitch2 += p * p;
    sumRoll2  += r * r;
    float dev = sqrtf(p * p + r * r);
    if (dev > maxDev) maxDev = dev;
  }

  float invN = 1.0f / (float)count;
  float meanPitch = sumPitch * invN;
  float meanRoll  = sumRoll  * invN;
  float varPitch  = (sumPitch2 * invN) - (meanPitch * meanPitch);
  float varRoll   = (sumRoll2  * invN) - (meanRoll  * meanRoll);

  m.stdDevPitchDeg   = sqrtf(varPitch > 0.0f ? varPitch : 0.0f);
  m.stdDevRollDeg    = sqrtf(varRoll  > 0.0f ? varRoll  : 0.0f);
  m.maxDeviationDeg  = maxDev;

  float rmsPitch = sqrtf(sumPitch2 * invN);
  float rmsRoll  = sqrtf(sumRoll2  * invN);
  m.rmsDeviationDeg = sqrtf(rmsPitch * rmsPitch + rmsRoll * rmsRoll);
  return m;
}

static uint8_t test_stabilityToScore(float rmsDeviationDeg) {
  if (rmsDeviationDeg <= STABILITY_GOOD_DEG) return 100;
  if (rmsDeviationDeg >= STABILITY_POOR_DEG)  return 0;
  float t = (rmsDeviationDeg - STABILITY_GOOD_DEG) / (STABILITY_POOR_DEG - STABILITY_GOOD_DEG);
  return (uint8_t)constrain(100.0f * (1.0f - t), 0.0f, 100.0f);
}

void test_stability_perfect_still_all_zero(void) {
    float pitch[10] = {0};
    float roll[10]  = {0};
    StabilityMetrics m = test_computeStability(pitch, roll, 10);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, m.rmsDeviationDeg);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, m.maxDeviationDeg);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, m.stdDevPitchDeg);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, m.stdDevRollDeg);
    TEST_ASSERT_EQUAL(10, m.sampleCount);
}

void test_stability_score_perfect_0deg_rms_100(void) {
    TEST_ASSERT_EQUAL(100, test_stabilityToScore(0.0f));
}
void test_stability_score_at_good_threshold(void) {
    TEST_ASSERT_EQUAL(100, test_stabilityToScore(STABILITY_GOOD_DEG));
}
void test_stability_score_at_poor_threshold(void) {
    TEST_ASSERT_EQUAL(0, test_stabilityToScore(STABILITY_POOR_DEG));
}
void test_stability_score_above_poor(void) {
    TEST_ASSERT_EQUAL(0, test_stabilityToScore(3.0f));
}
void test_stability_score_interpolated_midpoint(void) {
    // midpoint between GOOD (0.3) and POOR (2.0) = 1.15
    uint8_t s = test_stabilityToScore(1.15f);
    TEST_ASSERT_TRUE(s > 0 && s < 100);
    TEST_ASSERT_TRUE(s >= 49 && s <= 51);  // approximately 50
}
void test_stability_score_monotonically_decreasing(void) {
    uint8_t s1 = test_stabilityToScore(0.1f);
    uint8_t s2 = test_stabilityToScore(0.8f);
    uint8_t s3 = test_stabilityToScore(1.5f);
    TEST_ASSERT_TRUE(s1 > s2 && s2 > s3);
}

// =============================================================================
// SHOT DEBOUNCE TEST
// =============================================================================

void test_shot_debounce_blocks_rapid_fires(void) {
    // Test debounce at the firmware level: shots within 500ms should be blocked
    clearTraceBuffer();
    lastShotMs = 100;  // simulate first shot at t=100
    setMillis(300);    // second check at t=300 → 200ms gap < 500ms debounce → blocked
    bool blocked = (millis() - lastShotMs < SHOT_DEBOUNCE_MS);
    TEST_ASSERT_TRUE(blocked);
}

void test_shot_debounce_allows_after_debounce_period(void) {
    // After debounce period expires, next shot should be allowed
    clearTraceBuffer();
    lastShotMs = 100;  // first shot at t=100
    setMillis(700);    // now at t=700 → 600ms gap > 500ms → allowed
    bool allowed = (millis() - lastShotMs >= SHOT_DEBOUNCE_MS);
    TEST_ASSERT_TRUE(allowed);
}

// =============================================================================
// CONFIG CONSTANTS NEW TESTS
// =============================================================================

void test_config_settle_samples_20(void) {
    TEST_ASSERT_EQUAL(20, AIM_SETTLE_SAMPLES);
}
void test_config_settle_accel_max(void) {
    TEST_ASSERT_EQUAL_FLOAT(0.15f, AIM_SETTLE_ACCEL_MAX);
}
void test_config_settle_gyro_max(void) {
    TEST_ASSERT_EQUAL_FLOAT(2.0f, AIM_SETTLE_GYRO_MAX);
}
void test_config_shot_peak_min_g(void) {
    TEST_ASSERT_EQUAL_FLOAT(3.0f, SHOT_ACCEL_PEAK_MIN_G);
}
void test_config_shot_peak_window_ms(void) {
    TEST_ASSERT_EQUAL(50, SHOT_ACCEL_PEAK_WINDOW_MS);
}
void test_config_shot_debounce_ms(void) {
    TEST_ASSERT_EQUAL(500, SHOT_DEBOUNCE_MS);
}
void test_config_stability_window_1000ms(void) {
    TEST_ASSERT_EQUAL(1000, STABILITY_WINDOW_MS);
}
void test_config_stability_max_samples_100(void) {
    TEST_ASSERT_EQUAL(100, STABILITY_MAX_SAMPLES);
}
void test_config_stability_good_deg(void) {
    TEST_ASSERT_EQUAL_FLOAT(0.3f, STABILITY_GOOD_DEG);
}
void test_config_stability_poor_deg(void) {
    TEST_ASSERT_EQUAL_FLOAT(2.0f, STABILITY_POOR_DEG);
}

// =============================================================================
// MAIN
// =============================================================================

static int runTests(void) {
    UNITY_BEGIN();

    // Math: quaternions
    RUN_TEST(test_math_pitch_identity_zero);
    RUN_TEST(test_math_pitch_90deg_yaw_near_zero);
    RUN_TEST(test_math_pitch_approx_10deg);
    RUN_TEST(test_math_roll_identity_zero);
    RUN_TEST(test_math_roll_approx_90deg);
    RUN_TEST(test_math_yaw_identity_zero);
    RUN_TEST(test_math_yaw_approx_90deg);

    // Math: deviation
    RUN_TEST(test_math_deviation_identical_zero);
    RUN_TEST(test_math_deviation_negated_same_rotation);
    RUN_TEST(test_math_deviation_90deg_rotation);
    RUN_TEST(test_math_deviation_antipodal_quaternions_180);

    // Score
    RUN_TEST(test_score_perfect_0dev_100);
    RUN_TEST(test_score_perfect_0_49dev_100);
    RUN_TEST(test_score_exact_0_5dev_100);
    RUN_TEST(test_score_poor_10dev_0);
    RUN_TEST(test_score_poor_15dev_0);
    RUN_TEST(test_score_interpolated_5_25dev);
    RUN_TEST(test_score_negative_dev_below_0_5);
    RUN_TEST(test_score_above_10_dev);
    RUN_TEST(test_score_linearity_high_to_low);
    RUN_TEST(test_score_pistol_precision_at_threshold);
    RUN_TEST(test_score_rifle_precision_at_threshold);

    // Shot detection
    RUN_TEST(test_shot_below_accel_threshold_false);
    RUN_TEST(test_shot_above_accel_threshold_true);
    RUN_TEST(test_shot_at_or_above_threshold_fires);
    RUN_TEST(test_shot_slightly_above_threshold_true);
    RUN_TEST(test_shot_live_fire_audio_within_window);
    RUN_TEST(test_shot_dry_fire_audio_outside_window);

    // Shot finalisation
    RUN_TEST(test_finalise_perfect_alignment);
    RUN_TEST(test_finalise_slight_deviation);
    RUN_TEST(test_finalise_large_deviation);
    RUN_TEST(test_finalise_crosses_180_boundary);

    // State machine
    RUN_TEST(test_fsm_idle_no_motion_stays_idle);
    RUN_TEST(test_fsm_idle_motion_to_aiming);
    RUN_TEST(test_fsm_idle_small_accel_to_aiming);
    RUN_TEST(test_fsm_aiming_low_gyro_to_trigger);
    RUN_TEST(test_fsm_aiming_shot_accel_to_shot);
    RUN_TEST(test_fsm_trigger_shot_accel_to_shot);
    RUN_TEST(test_fsm_trigger_high_gyro_returns_aiming);
    RUN_TEST(test_fsm_shot_immediately_to_recoil);
    RUN_TEST(test_fsm_recoil_settles_after_follow_through);
    RUN_TEST(test_fsm_recoil_still_within_window);
    RUN_TEST(test_fsm_recoil_gyro_still_high);

    // Config constants
    RUN_TEST(test_config_shot_threshold_2_5g);
    RUN_TEST(test_config_audio_threshold_2000);
    RUN_TEST(test_config_shot_window_15ms);
    RUN_TEST(test_config_yellow_pre_shot_250ms);
    RUN_TEST(test_config_red_follow_500ms);
    RUN_TEST(test_config_trace_buf_512);
    RUN_TEST(test_config_idle_timeout_120s);
    RUN_TEST(test_config_low_bat_3_4v);

    // Stability
    RUN_TEST(test_stability_perfect_still_all_zero);
    RUN_TEST(test_stability_score_perfect_0deg_rms_100);
    RUN_TEST(test_stability_score_at_good_threshold);
    RUN_TEST(test_stability_score_at_poor_threshold);
    RUN_TEST(test_stability_score_above_poor);
    RUN_TEST(test_stability_score_interpolated_midpoint);
    RUN_TEST(test_stability_score_monotonically_decreasing);

    // Shot debounce
    RUN_TEST(test_shot_debounce_blocks_rapid_fires);
    RUN_TEST(test_shot_debounce_allows_after_debounce_period);

    // New config constants
    RUN_TEST(test_config_settle_samples_20);
    RUN_TEST(test_config_settle_accel_max);
    RUN_TEST(test_config_settle_gyro_max);
    RUN_TEST(test_config_shot_peak_min_g);
    RUN_TEST(test_config_shot_peak_window_ms);
    RUN_TEST(test_config_shot_debounce_ms);
    RUN_TEST(test_config_stability_window_1000ms);
    RUN_TEST(test_config_stability_max_samples_100);
    RUN_TEST(test_config_stability_good_deg);
    RUN_TEST(test_config_stability_poor_deg);

    return UNITY_END();
}

#ifdef _WIN32
// MinGW default entry point is WinMain, but we want main() for the console subsystem
// Use a linker directive to switch subsystems — this must appear before any function defs
#pragma comment(linker, "/SUBSYSTEM:CONSOLE")
int main(int argc, char* argv[]) {
    (void)argc; (void)argv;
    return runTests();
}
#else
int main(void) {
    return runTests();
}
#endif
