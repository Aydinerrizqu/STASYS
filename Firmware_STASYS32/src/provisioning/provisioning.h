#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Load the provisioned 32-byte device key from NVS.
 * Returns 0 and sets the key outputs on success; -1 when absent/invalid. */
int staysys_provisioned_key(const uint8_t **key, size_t *key_len);

/* Handle one newline-terminated provisioning line from USB serial.
 * Returns true if the line was a provisioning command (handled). */
bool provisioning_handle_line(const char *line);

/* Human-readable provisioning status for serial output (never the key). */
void provisioning_print_status(void);

#ifdef __cplusplus
}
#endif
