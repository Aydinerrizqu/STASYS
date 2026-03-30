// ============================================================
// STASYS Firmware v2.0 - Oversampling Edition
// Platform: ESP32
// Sensor: MPU6050 (I2C) + Piezo (ADC)
// Protocol: Binary 30-byte packets @ 100Hz
// Features:
//   - 1kHz sensor reads with peak detection
//   - 100Hz data transmission
//   - Piezo trigger detection
//   - Battery monitoring
//   - SHA-256 challenge-response authentication
// ============================================================

#include <Arduino.h>
#include "BluetoothSerial.h"
#include <Wire.h>
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "mbedtls/sha256.h"

// ================= CONFIGURATION =================
#define BATTERY_PIN   39          // ADC1_CH3
#define PIEZO_PIN     35          // ADC1_CH7 (Safe with Bluetooth)
#define I2C_SDA       21
#define I2C_SCL       22
#define MPU_ADDR      0x68

#define VOLTAGE_DIVIDER_RATIO 2.0
#define BATTERY_MAX_VOLTAGE   4.2
#define BATTERY_MIN_VOLTAGE   3.0

// --- TIMING CONFIGURATION ---
// Sensor reads at 1kHz (1ms), sends at 100Hz (10ms)
#define SEND_RATE_MS       10
#define OVERSAMPLE_LOOPS  10   // 1kHz = 1000Hz / 100Hz
#define CPU_FREQ_MHZ       240  // Max speed for high sample rate

// --- FIRMWARE VERSION ---
#define FIRMWARE_VERSION "2.0-OVERSAMPLE"

const char* SECRET_KEY = "12ebaf10h12fa9123z21sti";

// =================================================

BluetoothSerial SerialBT;

volatile bool isAuthenticated = false;
volatile int batteryPercentage = 0;

// --- BINARY PACKET STRUCTURE (30 bytes total) ---
// __attribute__((packed)) ensures no extra padding bytes
struct __attribute__((packed)) DataPacket {
  uint8_t  header[2];  // 0xAA, 0xBB (sync bytes)
  float    ax;         // Accelerometer X (m/s²)
  float    ay;         // Accelerometer Y (m/s²)
  float    az;         // Accelerometer Z (m/s²)
  float    gx;         // Gyroscope X (rad/s)
  float    gy;         // Gyroscope Y (rad/s)
  float    gz;         // Gyroscope Z (rad/s)
  uint16_t piezo;      // Peak piezo ADC value in window
  uint8_t  battery;   // Battery percentage (0-100)
  uint8_t  checksum;   // XOR of bytes 2-28
};
// Packet size: 2 + 24 + 2 + 1 + 1 = 30 bytes
// Format string: '<ffffffHB' (little-endian, 6 floats + uint16 + 2 uint8)

// --- Helper Functions ---

void writeMPURegister(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

float readBatteryVoltage() {
  long sum = 0;
  for(int i = 0; i < 16; i++) sum += analogRead(BATTERY_PIN);
  return ((sum / 16.0) / 4095.0) * 3.3 * VOLTAGE_DIVIDER_RATIO;
}

int calculateBatteryPercentage(float voltage) {
  if (voltage >= BATTERY_MAX_VOLTAGE) return 100;
  if (voltage <= BATTERY_MIN_VOLTAGE) return 0;
  float percentage = ((voltage - BATTERY_MIN_VOLTAGE) / (BATTERY_MAX_VOLTAGE - BATTERY_MIN_VOLTAGE)) * 100.0;
  return constrain((int)percentage, 0, 100);
}

void handleAuthentication() {
  isAuthenticated = false;
  delay(500);
  // Send READY signal so Python/Flutter knows firmware is up
  SerialBT.println("READY");
  SerialBT.println(FIRMWARE_VERSION);

  String challenge = "";
  unsigned long startTime = millis();
  SerialBT.setTimeout(500);

  while (millis() - startTime < 5000) {
    if (SerialBT.available()) {
      challenge = SerialBT.readStringUntil('\n');
      challenge.trim();
      if (challenge.length() > 0) break;
    }
    delay(10);
  }

  if (challenge.length() == 0) {
    SerialBT.disconnect();
    return;
  }

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
  delay(200);
  isAuthenticated = true;
}

// --- SENSOR TASK (OVERSAMPLING) ---
// Runs pinned to Core 1 for timing stability
void sensorTask(void *parameter) {
  int16_t rax, ray, raz, rgx, rgy, rgz;
  float peak_ax, peak_ay, peak_az;
  float avg_gx, avg_gy, avg_gz;
  uint16_t max_piezo;
  float prev_ax_val = 0, prev_ay_val = 0, prev_az_val = 0;

  for (;;) {
    if (SerialBT.connected()) {
      if (!isAuthenticated) handleAuthentication();

      if (isAuthenticated) {
        float max_shock_energy = -1.0;
        long gyro_sum_x = 0, gyro_sum_y = 0, gyro_sum_z = 0;
        max_piezo = 0;

        // --- OVERSAMPLING LOOP (1kHz) ---
        // Read sensor 10x, pick highest jerk as "peak" for trigger detect
        // Average gyro for smooth trace
        for(int i = 0; i < OVERSAMPLE_LOOPS; i++) {
          // 1. Fast I2C Read (Raw Registers)
          Wire.beginTransmission(MPU_ADDR);
          Wire.write(0x3B);
          Wire.endTransmission(false);
          Wire.requestFrom(MPU_ADDR, 14, true);

          if (Wire.available() >= 14) {
            rax = Wire.read() << 8 | Wire.read();
            ray = Wire.read() << 8 | Wire.read();
            raz = Wire.read() << 8 | Wire.read();
            Wire.read(); Wire.read(); // Temperature (skip)
            rgx = Wire.read() << 8 | Wire.read();
            rgy = Wire.read() << 8 | Wire.read();
            rgz = Wire.read() << 8 | Wire.read();
          }

          // 2. Read Piezo (inside fast loop to catch spike)
          uint16_t current_piezo = analogRead(PIEZO_PIN);
          if (current_piezo > max_piezo) {
            max_piezo = current_piezo;
          }

          // 3. Convert Accel (4G Range = 8192 LSB)
          float c_ax = (rax / 8192.0) * 9.81;
          float c_ay = (ray / 8192.0) * 9.81;
          float c_az = (raz / 8192.0) * 9.81;

          // 4. Calculate "Shock Energy" (Jerk = rate of accel change)
          // Detects super-short clicks that might be missed at 100Hz
          float jerk = abs(c_ax - prev_ax_val) + abs(c_ay - prev_ay_val) + abs(c_az - prev_az_val);

          // Save this reading if it has highest shock
          if (jerk > max_shock_energy) {
            max_shock_energy = jerk;
            peak_ax = c_ax;
            peak_ay = c_ay;
            peak_az = c_az;
          }

          // Accumulate gyro for averaging (trace needs smoothness)
          gyro_sum_x += rgx;
          gyro_sum_y += rgy;
          gyro_sum_z += rgz;

          // Update history
          prev_ax_val = c_ax;
          prev_ay_val = c_ay;
          prev_az_val = c_az;

          // Wait ~1ms to approximate 1kHz
          // I2C ~0.4ms + analogRead ~0.1ms + overhead
          delayMicroseconds(400);
        }

        // --- PREPARE PACKET ---
        // Use PEAK accel (for trigger detection)
        // Use PEAK piezo (for shock detection)
        // Use AVERAGE gyro (for clean trace)

        DataPacket pkt;
        pkt.header[0] = 0xAA;
        pkt.header[1] = 0xBB;
        pkt.ax = peak_ax;
        pkt.ay = peak_ay;
        pkt.az = peak_az;

        // Convert Gyro: 500dps (65.5 LSB/deg/s) → rad/s (* 0.0174533)
        pkt.gx = ((gyro_sum_x / OVERSAMPLE_LOOPS) / 65.5) * 0.0174533;
        pkt.gy = ((gyro_sum_y / OVERSAMPLE_LOOPS) / 65.5) * 0.0174533;
        pkt.gz = ((gyro_sum_z / OVERSAMPLE_LOOPS) / 65.5) * 0.0174533;

        pkt.piezo = max_piezo;
        pkt.battery = (uint8_t)batteryPercentage;

        // XOR Checksum (bytes 2 through 28)
        uint8_t* ptr = (uint8_t*)&pkt;
        pkt.checksum = 0;
        for(int i = 2; i < sizeof(DataPacket) - 1; i++) {
          pkt.checksum ^= ptr[i];
        }

        SerialBT.write((const uint8_t*)&pkt, sizeof(DataPacket));

      } else {
        delay(1000);
      }
    } else {
      isAuthenticated = false;
      delay(500);
    }
  }
}

void batteryMonitorTask(void *parameter) {
  int lastReportedVal = -1;
  for (;;) {
    float batteryVoltage = readBatteryVoltage();
    int newPercentage = calculateBatteryPercentage(batteryVoltage);
    if (lastReportedVal == -1 || abs(newPercentage - lastReportedVal) >= 2) {
      batteryPercentage = newPercentage;
      lastReportedVal = newPercentage;
    }
    vTaskDelay(2000 / portTICK_PERIOD_MS);
  }
}

void setup() {
  setCpuFrequencyMhz(CPU_FREQ_MHZ);
  Serial.begin(115200);

  // Unique device name from ESP32 chip MAC
  uint64_t chipid = ESP.getEfuseMac();
  char uniqueName[30];
  sprintf(uniqueName, "STASYS-V2-%04X", (uint16_t)(chipid >> 32));

  SerialBT.begin(uniqueName);
  Serial.printf("Device: %s | Firmware: %s\n", uniqueName, FIRMWARE_VERSION);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(PIEZO_PIN, INPUT);

  esp_bredr_tx_power_set(ESP_PWR_LVL_N0, ESP_PWR_LVL_P3);

  // --- I2C & MPU6050 SETUP ---
  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(400000); // 400kHz Fast I2C
  delay(100);

  // Wake up MPU6050
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00); // Clear sleep bit
  Wire.endTransmission();
  delay(50);

  // --- MANUAL MPU6050 REGISTER CONFIG ---
  // Accel: 4G Range (0x08) — good for dry fire trigger detection
  writeMPURegister(0x1C, 0x08);

  // Gyro: 500dps Range (0x08) — covers pistol/rifle recoil
  writeMPURegister(0x1B, 0x08);

  // DLPF: 260Hz Bandwidth (0x00) — NO hardware smoothing for click detection
  // We do smoothing in software via oversampling averaging
  writeMPURegister(0x1A, 0x00);

  Serial.printf("Sensor: 4G / 500dps / 260Hz / 1kHz Polling\n");
  Serial.printf("Piezo: ADC Pin %d Active\n", PIEZO_PIN);

  // FreeRTOS tasks
  // sensorTask pinned to Core 1 (Bluetooth Core) for timing stability
  // batteryMonitorTask pinned to Core 0
  xTaskCreatePinnedToCore(sensorTask, "SensorTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(batteryMonitorTask, "BatMonitor", 2048, NULL, 1, NULL, 0);
}

void loop() {
  vTaskDelay(1000 / portTICK_PERIOD_MS);
}
