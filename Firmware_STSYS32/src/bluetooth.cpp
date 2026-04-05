// ============================================================
// bluetooth.cpp — Bluetooth SPP, Command Dispatch, Packet TX/RX
// ============================================================
#include "bluetooth.h"
#include "sensor.h"
#include "protocol.h"
#include "security.h"
#include "session.h"
#include "battery.h"
#include <Arduino.h>
#include <BluetoothSerial.h>
#include <esp32-hal-bt.h>
#include <esp_bt.h>
#include <esp_bt_main.h>
#include <esp_bt_device.h>
#include <esp_timer.h>

// ================= GLOBALS =================
QueueHandle_t txQueue = NULL;
bool g_btConnected = false;

uint8_t s_rxBuffer[1024];
uint16_t s_rxLen = 0;
uint32_t s_rxOverflowCount = 0;

BluetoothSerial SerialBT;
static TXItem s_txItem;
static char s_deviceName[32];

// ================= PAIRING FAILURE TRACKING =================
static uint8_t s_pairingFailures = 0;
#define MAX_PAIRING_FAILURES 3

// ================= INIT =================
void initBluetooth(const char* deviceName) {
    // Initialize TX queue
    txQueue = xQueueCreate(64, sizeof(TXItem));
    if (txQueue == NULL) {
        Serial.println("[BT] ERROR: Failed to create TX queue");
    }

    strncpy(s_deviceName, deviceName, sizeof(s_deviceName) - 1);
    s_deviceName[sizeof(s_deviceName) - 1] = '\0';
    Serial.printf("[BT] Configured: name=%s (no PIN — Just Works)\n", s_deviceName);

    if (btStarted()) {
        Serial.println("[BT] Stopping existing BT controller...");
        btStop();
        delay(100);
    }

    // Set security mode to Just Works (no PIN required)
    // Note: esp_bt_gap_set_security_param requires esp_bt_gap.h (ESP-IDF header)
    // For production, add the ESP-IDF bt/host include path to platformio.ini build_flags
    // For now, BluetoothSerial.begin() handles security internally

    // Set BT TX power (+3dBm)
    esp_bredr_tx_power_set(ESP_PWR_LVL_P3, ESP_PWR_LVL_P3);
    Serial.println("[BT] TX power set to +3dBm (ESP_PWR_LVL_P3)");

    // Begin SPP (isMaster=false → ESP32 is peripheral)
    bool spp_started = SerialBT.begin(s_deviceName, false);
    Serial.printf("[BT] SPP begin: %s\n", spp_started ? "OK" : "FAILED");

    if (!spp_started) {
        Serial.println("[BT] FATAL: BluetoothSerial.begin() failed");
        return;
    }

    delay(50);

    const uint8_t* bd_addr = esp_bt_dev_get_address();
    Serial.printf("[BT] Device started: %s (MAC: %02X:%02X:%02X:%02X:%02X:%02X)\n",
                  s_deviceName,
                  bd_addr[0], bd_addr[1], bd_addr[2],
                  bd_addr[3], bd_addr[4], bd_addr[5]);

    // Initialize protocol decoder
    initDecoder();
    initSecurity();
}

bool isConnected() {
    return SerialBT.connected();
}

// ================= SEND FUNCTIONS =================
void sendPacket(uint8_t type, const void* payload, uint16_t len) {
    TXItem item;
    item.length = encodePacket(type, payload, len, item.data);
    if (item.length > 0 && txQueue != NULL) {
        xQueueSend(txQueue, &item, 0);  // Non-blocking
    }
}

void sendAck(uint8_t commandId, uint8_t status) {
    PktAck ack;
    ack.command_id = commandId;
    ack.status = status;
    sendPacket(PKT_TYPE_RSP_ACK, &ack, sizeof(ack));
}

void sendError(uint8_t code, const char* msg) {
    PktError err;
    err.error_code = code;
    strncpy(err.message, msg, sizeof(err.message) - 1);
    err.message[sizeof(err.message) - 1] = '\0';
    sendPacket(PKT_TYPE_RSP_ERROR, &err, sizeof(err));
}

void sendSensorHealthPacket() {
    SensorHealth health;
    checkSensorHealth(&health);

    uint8_t pkt[8];
    pkt[0] = health.mpu_present ? 1 : 0;
    pkt[1] = health.i2c_error_count;
    pkt[2] = health.samples_total & 0xFF;
    pkt[3] = (health.samples_total >> 8) & 0xFF;
    pkt[4] = health.samples_invalid & 0xFF;
    pkt[5] = (health.samples_invalid >> 8) & 0xFF;
    pkt[6] = health.i2c_recovery_count;
    pkt[7] = 0;

    sendPacket(PKT_TYPE_EVT_SENSOR_HEALTH, pkt, sizeof(pkt));
}
