#include <Arduino.h>
#include "BluetoothSerial.h"
#include <Wire.h>
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_task_wdt.h"
#include "esp_pm.h"
#include "esp_bt_device.h"
#include "mbedtls/sha256.h"
#include "sensor/i2c_bus_recovery.h"
#include "storage/storage.h"
#include "storage/crc.h"
#include "storage/status_led.h"
#include "storage/ota.h"
#include "sensor/quaternion.h"
#include "sensor/madgwick.h"
#include "sensor/calibration.h"

// ================= CONFIGURATION =================
#define BATTERY_PIN 39          // ADC1_CH3
#define PIEZO_PIN   35          // ADC1_CH7 (D35)
#define I2C_SDA 21
#define I2C_SCL 22
#define MPU_ADDR 0x68

// Factory reset button: GPIO 0 (boot button)
// Hold for 3 seconds during normal operation to trigger
#define FACTORY_RESET_PIN 0
#define FACTORY_RESET_HOLD_MS 3000

// --- BATTERY THRESHOLDS ---
#define BATTERY_MAX_VOLTAGE 4.2f
#define BATTERY_MIN_VOLTAGE 3.0f
#define BATTERY_LOW_VOLTAGE  3.5f  // ~20%
#define BATTERY_CRITICAL_VOLTAGE 3.3f // ~5%

// --- TIMING ---
#define SEND_RATE_MS 10
#define OVERSAMPLE_LOOPS 10
#define CPU_FREQ_MAX_MHZ 240
#define CPU_FREQ_MIN_MHZ 80

// --- AUTH ---
#define AUTH_TIMEOUT_MS  5000
#define AUTH_POLL_MS     10

// --- WATCHDOG ---
#define WDT_TIMEOUT_S    10

// --- POWER MANAGER ---
#define SAMPLE_RATE_NORMAL  100  // Hz
#define SAMPLE_RATE_LOW     20  // Hz when battery low
#define SESSION_TIMEOUT_MS  (5UL * 60UL * 1000UL)  // 5 minutes inactivity

// --- BATTERY THRESHOLDS (percentage-based) ---
#define BATTERY_LOW_PCT       20  // Reduce sample rate
#define BATTERY_CRITICAL_PCT  5   // Enter deep sleep

// --- AUTHENTICATION ---
static const char* SECRET_KEY = DEFAULT_SECRET_KEY;

// =================================================

static BluetoothSerial SerialBT;

// --- SHARED STATE ---
static volatile bool isAuthenticated = false;
static volatile bool sensorReady = false;
static volatile uint8_t batteryPercentage = 0;
static volatile uint8_t currentSampleRate = SAMPLE_RATE_NORMAL;
static volatile bool lowPowerMode = false;

// Battery state
static volatile bool batteryLow = false;
static volatile bool batteryCritical = false;

// Mutex for batteryPercentage
static SemaphoreHandle_t batteryMutex = NULL;

// Task handles
static TaskHandle_t sensorTaskHandle = NULL;
static TaskHandle_t batteryTaskHandle = NULL;
static TaskHandle_t resetButtonTaskHandle = NULL;

// Power manager handles
static esp_pm_lock_handle_t pmMaxLock = NULL;
static bool pmInitialized = false;

// --- AUTH STATE MACHINE ---
typedef enum {
    AUTH_STATE_IDLE,
    AUTH_STATE_WAITING,
    AUTH_STATE_DONE
} AuthState_t;

static AuthState_t authState = AUTH_STATE_IDLE;
static uint32_t authStartTime = 0;
static uint32_t lastAuthenticatedTick = 0;

// --- DEVICE STATE ---
static DeviceConfig g_config;
static DeviceStats  g_stats;

// --- IMU CALIBRATION STATE ---
static MadgwickFilter g_ahrs;
static float g_gyroRuntimeBias[3] = {0.0f, 0.0f, 0.0f};
static bool g_ahrsReady = false;

// --- BINARY PACKET STRUCTURE ---
struct __attribute__((packed)) DataPacket {
    uint8_t  header[2];  // 0xAA, 0xBB
    float    ax;
    float    ay;
    float    az;
    float    gx;
    float    gy;
    float    gz;
    uint16_t piezo;
    uint8_t  battery;
    uint16_t crc16;      // CRC-16 CCITT over header+data
};

// =================================================
// HELPER FUNCTIONS
// =================================================

static void writeMPURegister(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

static bool checkMPU6050(void) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x75);
    if (Wire.endTransmission(false) != 0) return false;
    Wire.requestFrom((int)MPU_ADDR, (int)1, (int)1);
    if (Wire.available() < 1) return false;
    uint8_t whoAmI = Wire.read();
    Serial.printf("[MPU] WHO_AM_I: 0x%02X\n", whoAmI);
    return (whoAmI == 0x68);
}

static void initMPU6050(void) {
    writeMPURegister(0x6B, 0x00); // Wake
    delay(50);
    writeMPURegister(0x1C, 0x08); // Accel: 4G
    writeMPURegister(0x1B, 0x08); // Gyro: 500dps
    writeMPURegister(0x1A, 0x00);  // DLPF: 260Hz
}

static void initPowerManager(void) {
    esp_pm_config_esp32_t pm_config = {
        .max_freq_mhz = CPU_FREQ_MAX_MHZ,
        .min_freq_mhz = CPU_FREQ_MIN_MHZ,
        .light_sleep_enable = false
    };

    if (esp_pm_configure(&pm_config) == ESP_OK) {
        pmInitialized = true;
        Serial.println("[PM] Dynamic frequency scaling enabled");

        if (esp_pm_lock_create(ESP_PM_CPU_FREQ_MAX, 0, "max_freq", &pmMaxLock) == ESP_OK) {
            Serial.println("[PM] Max freq lock available");
        } else {
            Serial.println("[PM] WARNING: Failed to create max freq lock");
        }
    } else {
        Serial.println("[PM] WARNING: PM configuration failed");
    }
}

static void pmRequestMaxFreq(void) {
    if (!pmInitialized || !pmMaxLock) return;
    esp_pm_lock_acquire(pmMaxLock);
}

static void pmReleaseMaxFreq(void) {
    if (!pmInitialized || !pmMaxLock) return;
    esp_pm_lock_release(pmMaxLock);
}

static float readBatteryVoltage(void) {
    long sum = 0;
    for (int i = 0; i < 16; i++) sum += analogRead(BATTERY_PIN);
    return ((sum / 16.0f) / 4095.0f) * 3.3f * VOLTAGE_DIVIDER_RATIO;
}

static int calculateBatteryPercentage(float voltage) {
    if (voltage >= BATTERY_MAX_VOLTAGE) return 100;
    if (voltage <= BATTERY_MIN_VOLTAGE) return 0;
    float pct = ((voltage - BATTERY_MIN_VOLTAGE) / (BATTERY_MAX_VOLTAGE - BATTERY_MIN_VOLTAGE)) * 100.0f;
    return constrain((int)pct, 0, 100);
}

static uint16_t computeCRC16(const DataPacket* pkt) {
    return crc16_ccitt((const uint8_t*)pkt + 2, sizeof(DataPacket) - 2);
}

// --- AUTHENTICATION ---
static bool updateAuthentication(void) {
    switch (authState) {
        case AUTH_STATE_IDLE: {
            SerialBT.println("READY");
            authState = AUTH_STATE_WAITING;
            authStartTime = millis();
            ledSetPattern(LED_CONNECTING);
            break;
        }

        case AUTH_STATE_WAITING: {
            if (millis() - authStartTime > AUTH_TIMEOUT_MS) {
                SerialBT.disconnect();
                authState = AUTH_STATE_IDLE;
                ledSetPattern(LED_IDLE);
                break;
            }

            if (SerialBT.available()) {
                String challenge = SerialBT.readStringUntil('\n');
                challenge.trim();

                if (challenge.length() > 0 && challenge.length() < 128) {
                    String toHash = challenge + String(SECRET_KEY);
                    byte hashResult[32];
                    mbedtls_sha256_context ctx;
                    mbedtls_sha256_init(&ctx);
                    mbedtls_sha256_starts(&ctx, 0);
                    mbedtls_sha256_update(&ctx, (const unsigned char*)toHash.c_str(), toHash.length());
                    mbedtls_sha256_finish(&ctx, hashResult);
                    mbedtls_sha256_free(&ctx);

                    char hexHash[65];
                    for (int i = 0; i < 32; i++) sprintf(hexHash + (i * 2), "%02x", hashResult[i]);
                    SerialBT.println(hexHash);

                    authState = AUTH_STATE_DONE;
                    isAuthenticated = true;
                    lastAuthenticatedTick = xTaskGetTickCount();
                    ledSetPattern(LED_STREAMING);
                    return true;
                }
            }
            vTaskDelay(pdMS_TO_TICKS(AUTH_POLL_MS));
            break;
        }

        case AUTH_STATE_DONE:
            return true;
    }
    return false;
}

// --- BATTERY MONITOR TASK ---
static void batteryMonitorTask(void* parameter) {
    (void)parameter;
    int lastReportedVal = -1;
    uint32_t lastSaveTime = 0;
    esp_task_wdt_add(NULL);

    for (;;) {
        esp_task_wdt_reset();

        float voltage = readBatteryVoltage();
        int newPct = calculateBatteryPercentage(voltage);

        if (batteryMutex && xSemaphoreTake(batteryMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
            batteryPercentage = (uint8_t)newPct;
            xSemaphoreGive(batteryMutex);
        }

        bool wasLow = batteryLow;
        bool wasCritical = batteryCritical;

        if (newPct <= BATTERY_CRITICAL_PCT) {
            batteryCritical = true;
            batteryLow = true;
            ledSetPattern(LED_CRITICAL_BAT);
        } else if (newPct <= BATTERY_LOW_PCT) {
            batteryLow = true;
            batteryCritical = false;
            ledSetPattern(LED_LOW_BATTERY);
        } else {
            batteryLow = false;
            batteryCritical = false;
        }

        if (lastReportedVal == -1 || abs(newPct - lastReportedVal) >= 2) {
            lastReportedVal = newPct;
        }

        if (millis() - lastSaveTime > 30000) {
            g_stats.lastBatteryPct = newPct;
            storageSaveStats(&g_stats);
            lastSaveTime = millis();
        }

        if (batteryCritical && !wasCritical) {
            Serial.println("[Battery] Critical level reached. Entering deep sleep...");
            ledSetPattern(LED_OFF);
            storageIncrementDeepSleepCount();
            storageSaveStats(&g_stats);

            esp_sleep_enable_gpio_wakeup();
            esp_deep_sleep_start();
        }

        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

// --- FACTORY RESET HANDLER TASK ---
static void factoryResetButtonTask(void* parameter) {
    (void)parameter;
    gpio_pad_select_gpio(FACTORY_RESET_PIN);
    gpio_set_direction((gpio_num_t)FACTORY_RESET_PIN, GPIO_MODE_INPUT);
    gpio_pullup_en((gpio_num_t)FACTORY_RESET_PIN);

    for (;;) {
        if (gpio_get_level((gpio_num_t)FACTORY_RESET_PIN) == 0) {
            uint32_t pressStart = millis();
            while (gpio_get_level((gpio_num_t)FACTORY_RESET_PIN) == 0) {
                vTaskDelay(pdMS_TO_TICKS(100));
                if (millis() - pressStart > FACTORY_RESET_HOLD_MS) {
                    Serial.println("[RESET] Factory reset triggered!");
                    ledSetPattern(LED_SENSOR_ERROR);

                    storageFactoryReset();
                    vTaskDelay(pdMS_TO_TICKS(500));
                    esp_restart();
                    break;
                }
            }
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

// --- SENSOR TASK ---
static void sensorTask(void* parameter) {
    (void)parameter;

    int16_t rax, ray, raz, rgx, rgy, rgz;
    float peak_ax, peak_ay, peak_az;
    int64_t gyro_sum_x = 0, gyro_sum_y = 0, gyro_sum_z = 0;
    uint16_t max_piezo = 0;
    float prev_ax_val = 0, prev_ay_val = 0, prev_az_val = 0;

    DataPacket pkt;
    TickType_t lastWakeTime = xTaskGetTickCount();

    esp_task_wdt_add(NULL);
    TickType_t sendPeriod = pdMS_TO_TICKS(1000 / currentSampleRate);

    for (;;) {
        esp_task_wdt_reset();

        if (isAuthenticated) {
            uint32_t idleMs = (xTaskGetTickCount() - lastAuthenticatedTick) * portTICK_PERIOD_MS;
            if (idleMs > SESSION_TIMEOUT_MS) {
                isAuthenticated = false;
                authState = AUTH_STATE_IDLE;
                ledSetPattern(LED_IDLE);
                Serial.println("[Auth] Session timed out");
            }
        }

        if (batteryLow && currentSampleRate != SAMPLE_RATE_LOW) {
            currentSampleRate = SAMPLE_RATE_LOW;
            sendPeriod = pdMS_TO_TICKS(1000 / currentSampleRate);
            Serial.printf("[Power] Battery low — reduced to %d Hz\n", currentSampleRate);
        } else if (!batteryLow && currentSampleRate != SAMPLE_RATE_NORMAL) {
            currentSampleRate = SAMPLE_RATE_NORMAL;
            sendPeriod = pdMS_TO_TICKS(1000 / currentSampleRate);
        }

        if (SerialBT.connected()) {
            if (!isAuthenticated) {
                updateAuthentication();
            }

            if (isAuthenticated) {
                pmRequestMaxFreq();

                lastAuthenticatedTick = xTaskGetTickCount();

                float max_shock_energy = -1.0f;
                gyro_sum_x = gyro_sum_y = gyro_sum_z = 0;
                max_piezo = 0;

                for (int i = 0; i < OVERSAMPLE_LOOPS; i++) {
                    Wire.beginTransmission(MPU_ADDR);
                    Wire.write(0x3B);
                    uint8_t err = Wire.endTransmission(false);
                    if (err != 0) {
                        recoverI2CBus(I2C_SDA, I2C_SCL);
                        Wire.begin(I2C_SDA, I2C_SCL);
                        Wire.setClock(400000);
                        sensorReady = false;
                    }

                    Wire.requestFrom((int)MPU_ADDR, (int)14, (int)1);

                    if (Wire.available() >= 14) {
                        rax = Wire.read() << 8 | Wire.read();
                        ray = Wire.read() << 8 | Wire.read();
                        raz = Wire.read() << 8 | Wire.read();
                        Wire.read(); Wire.read();
                        rgx = Wire.read() << 8 | Wire.read();
                        rgy = Wire.read() << 8 | Wire.read();
                        rgz = Wire.read() << 8 | Wire.read();
                        sensorReady = true;
                    }

                    uint16_t current_piezo = analogRead(PIEZO_PIN);
                    if (current_piezo > max_piezo) max_piezo = current_piezo;

                    float c_ax = (rax / 8192.0f) * 9.81f - g_config.accelOffset[0];
                    float c_ay = (ray / 8192.0f) * 9.81f - g_config.accelOffset[1];
                    float c_az = (raz / 8192.0f) * 9.81f - g_config.accelOffset[2];

                    float ax_nograv = c_ax;
                    float ay_nograv = c_ay;
                    float az_nograv = c_az - 9.81f;
                    float jerk = fabsf(ax_nograv - (prev_ax_val))
                               + fabsf(ay_nograv - (prev_ay_val))
                               + fabsf(az_nograv - (prev_az_val - 9.81f));

                    if (jerk > max_shock_energy) {
                        max_shock_energy = jerk;
                        peak_ax = c_ax;
                        peak_ay = c_ay;
                        peak_az = c_az;
                    }

                    if (g_ahrsReady) {
                        float accel_corrected[3] = {
                            c_ax - g_config.accelOffset[0],
                            c_ay - g_config.accelOffset[1],
                            c_az - g_config.accelOffset[2]
                        };
                        if (zuptUpdate(accel_corrected)) {
                            float gyroRaw[3] = {
                                (float)rgx / 65.5f * 0.0174533f - g_config.gyroOffset[0],
                                (float)rgy / 65.5f * 0.0174533f - g_config.gyroOffset[1],
                                (float)rgz / 65.5f * 0.0174533f - g_config.gyroOffset[2]
                            };
                            zuptUpdateBias(gyroRaw);
                            for (int b = 0; b < 3; b++) g_gyroRuntimeBias[b] = zuptGetGyroBias()[b];
                        }
                    }

                    gyro_sum_x += rgx - (int16_t)(g_config.gyroOffset[0] * 65.5f) - (int16_t)(g_gyroRuntimeBias[0] * 65.5f);
                    gyro_sum_y += rgy - (int16_t)(g_config.gyroOffset[1] * 65.5f) - (int16_t)(g_gyroRuntimeBias[1] * 65.5f);
                    gyro_sum_z += rgz - (int16_t)(g_config.gyroOffset[2] * 65.5f) - (int16_t)(g_gyroRuntimeBias[2] * 65.5f);

                    prev_ax_val = ax_nograv;
                    prev_ay_val = ay_nograv;
                    prev_az_val = az_nograv;

                    delayMicroseconds(400);
                }

                float avg_gyro[3] = {
                    ((gyro_sum_x / OVERSAMPLE_LOOPS) / 65.5f) * 0.0174533f,
                    ((gyro_sum_y / OVERSAMPLE_LOOPS) / 65.5f) * 0.0174533f,
                    ((gyro_sum_z / OVERSAMPLE_LOOPS) / 65.5f) * 0.0174533f
                };
                if (g_ahrsReady) {
                    float avg_accel[3] = {
                        peak_ax - g_config.accelOffset[0],
                        peak_ay - g_config.accelOffset[1],
                        peak_az - g_config.accelOffset[2]
                    };
                    float dt = (sendPeriod * portTICK_PERIOD_MS) / 1000.0f;
                    madgwickUpdate(&g_ahrs, avg_gyro, avg_accel, dt);
                }

                pkt.header[0] = 0xAA;
                pkt.header[1] = 0xBB;
                pkt.ax = peak_ax;
                pkt.ay = peak_ay;
                pkt.az = peak_az;
                pkt.gx = avg_gyro[0];
                pkt.gy = avg_gyro[1];
                pkt.gz = avg_gyro[2];
                pkt.piezo = max_piezo;

                if (batteryMutex && xSemaphoreTake(batteryMutex, pdMS_TO_TICKS(1)) == pdTRUE) {
                    pkt.battery = batteryPercentage;
                    xSemaphoreGive(batteryMutex);
                } else {
                    pkt.battery = 0;
                }

                pkt.crc16 = computeCRC16(&pkt);
                SerialBT.write((const uint8_t*)&pkt, sizeof(DataPacket));

                pmReleaseMaxFreq();
            } else {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
        } else {
            isAuthenticated = false;
            authState = AUTH_STATE_IDLE;
            sensorReady = false;
            ledSetPattern(LED_IDLE);
            vTaskDelay(pdMS_TO_TICKS(500));
        }

        vTaskDelayUntil(&lastWakeTime, sendPeriod);
    }
}

// --- MPU6050 CALIBRATION ---
static void calibrateMPU6050(void) {
    Serial.println("[Calib] Starting factory calibration (500 samples)...");
    calibrationStart(500);
    uint32_t startMs = millis();

    while (!calibrationIsDone()) {
        if (millis() - startMs > 30000) {
            Serial.println("[Calib] Timeout — using uncalibrated defaults");
            break;
        }
        Wire.beginTransmission(MPU_ADDR);
        Wire.write(0x3B);
        Wire.endTransmission(false);
        Wire.requestFrom((int)MPU_ADDR, (int)14, (int)1);

        if (Wire.available() >= 14) {
            int16_t rax = Wire.read() << 8 | Wire.read();
            int16_t ray = Wire.read() << 8 | Wire.read();
            int16_t raz = Wire.read() << 8 | Wire.read();
            Wire.read(); Wire.read();
            int16_t rgx = Wire.read() << 8 | Wire.read();
            int16_t rgy = Wire.read() << 8 | Wire.read();
            int16_t rgz = Wire.read() << 8 | Wire.read();

            float aRaw[3] = {
                (float)rax / 8192.0f * 9.81f,
                (float)ray / 8192.0f * 9.81f,
                (float)raz / 8192.0f * 9.81f
            };
            float gRaw[3] = {
                (float)rgx / 65.5f * 0.0174533f,
                (float)rgy / 65.5f * 0.0174533f,
                (float)rgz / 65.5f * 0.0174533f
            };
            calibrationCollectSample(gRaw, aRaw);
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }

    if (calibrationFinish(500)) {
        ImuCalibration* res = calibrationGetResult();
        for (int i = 0; i < 3; i++) {
            g_config.accelOffset[i] = res->accel[i].bias;
            g_config.gyroOffset[i]  = res->gyro[i].bias;
        }
        storageSaveConfig(&g_config);
    }

    Serial.printf("[Calib] Accel offsets: %.3f, %.3f, %.3f m/s²\n",
        g_config.accelOffset[0], g_config.accelOffset[1], g_config.accelOffset[2]);
    Serial.printf("[Calib] Gyro offsets: %.3f, %.3f, %.3f rad/s\n",
        g_config.gyroOffset[0], g_config.gyroOffset[1], g_config.gyroOffset[2]);
}

// =================================================

void setup() {
    setCpuFrequencyMhz(CPU_FREQ_MAX_MHZ);
    Serial.begin(115200);

    esp_reset_reason_t resetReason = esp_reset_reason();
    Serial.printf("[Boot] Reset reason: %d\n", resetReason);
    storageLogReset(resetReason);

    if (!storageInit()) {
        Serial.println("[FATAL] NVS init failed");
    }

    storageLoadConfig(&g_config);
    storageLoadStats(&g_stats);

    if (resetReason == ESP_RST_PANIC || resetReason == ESP_RST_WDT) {
        Serial.println("[Boot] Crash/panic reset detected — running self-test...");
    }

    batteryMutex = xSemaphoreCreateMutex();
    if (!batteryMutex) {
        Serial.println("[FATAL] Battery mutex failed");
        while (1) delay(100);
    }

    recoverI2CBus(I2C_SDA, I2C_SCL);
    Wire.begin(I2C_SDA, I2C_SCL);
    Wire.setClock(400000);
    delay(100);

    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);
    pinMode(PIEZO_PIN, INPUT);

    ledInit();

    initMPU6050();

    if (!checkMPU6050()) {
        Serial.println("[ERROR] MPU6050 not responding!");
        recoverI2CBus(I2C_SDA, I2C_SCL);
        delay(100);
        Wire.begin(I2C_SDA, I2C_SCL);
        Wire.setClock(400000);

        if (!checkMPU6050()) {
            Serial.println("[FATAL] MPU6050 self-test FAILED");
            ledSetPattern(LED_SENSOR_ERROR);
        }
    } else {
        Serial.println("[MPU] OK: 4G / 500dps / 260Hz DLPF");

        if (!storageIsInitialized()) {
            calibrateMPU6050();
            storageSetInitialized();
        }
    }

    madgwickInit(&g_ahrs, 0.1f);
    zuptInit();
    if (storageIsInitialized()) {
        calibrationSetOffsets(g_config.gyroOffset, g_config.accelOffset);
        float accelInit[3] = {
            g_config.accelOffset[0],
            g_config.accelOffset[1],
            g_config.accelOffset[2] + 9.81f
        };
        g_ahrs.orientation = quatFromAccel(accelInit, 9.81f);
        g_ahrsReady = true;
        Serial.println("[AHRS] Orientation initialized from gravity");
    }

    initPowerManager();

    uint64_t chipid = ESP.getEfuseMac();
    char uniqueName[30];
    const char* baseName = g_config.deviceName[0] != '\0' ? g_config.deviceName : "STASYS";
    snprintf(uniqueName, sizeof(uniqueName), "%s-%04X",
        baseName,
        (uint16_t)(chipid >> 32));

    SerialBT.begin(uniqueName);
    Serial.printf("[BT] Device name: %s\n", uniqueName);
    esp_bredr_tx_power_set(ESP_PWR_LVL_N0, ESP_PWR_LVL_P3);

    esp_task_wdt_init(WDT_TIMEOUT_S, true);

    xTaskCreatePinnedToCore(sensorTask, "SensorTask", 8192, NULL, 2, &sensorTaskHandle, 1);
    xTaskCreatePinnedToCore(batteryMonitorTask, "BatMonitor", 4096, NULL, 1, &batteryTaskHandle, 0);
    xTaskCreatePinnedToCore(factoryResetButtonTask, "ResetBtn", 2048, NULL, 3, &resetButtonTaskHandle, 0);

    otaInit();

    Serial.printf("[Boot] STASYS_ONE v%s ready\n", FIRMWARE_VERSION);
    ledSetPattern(LED_IDLE);
}

void loop() {
    static uint32_t lastOpTimeLog = 0;
    if (millis() - lastOpTimeLog > 60000) {
        storageAddOperatingTime(60);
        lastOpTimeLog = millis();
    }

    vTaskDelay(pdMS_TO_TICKS(1000));
}