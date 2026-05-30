#ifndef BT_OTA_H
#define BT_OTA_H

#include "bt_ota_commands.h"
#include <stdbool.h>

void btOtaInit(void);
void btOtaReset(void);
void btOtaTask(void* parameter);
BtOtaState_t btOtaGetState(void);
void btOtaHandleTextCommand(const char* line);

// Check if OTA is active (sensor task should pause transmission)
bool btOtaIsActive(void);

#endif  // BT_OTA_H
