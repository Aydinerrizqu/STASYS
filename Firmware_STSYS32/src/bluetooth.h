// ============================================================
// bluetooth.h — Bluetooth SPP, Command Dispatch, Packet TX/RX
// ============================================================
#ifndef BLUETOOTH_H
#define BLUETOOTH_H

#include <stdint.h>
#include <stdbool.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include "protocol.h"
#include <BluetoothSerial.h>

// ================= QUEUES =================
extern QueueHandle_t txQueue;

// ================= EXTERNALS =================
extern bool g_btConnected;
extern class BluetoothSerial SerialBT;
extern uint8_t  s_rxBuffer[1024];
extern uint16_t s_rxLen;
extern uint32_t s_rxOverflowCount;
extern void dispatchCommand(const DecodedPacket* cmd);

// ================= FUNCTIONS =================
void  initBluetooth(const char* deviceName);
bool  isConnected();
void  sendPacket(uint8_t type, const void* payload, uint16_t len);
void  sendAck(uint8_t commandId, uint8_t status);
void  sendError(uint8_t code, const char* msg);
void  sendSensorHealthPacket();  // Heartbeat: sent every 5s during active session

#endif  // BLUETOOTH_H
