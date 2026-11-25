#pragma once
#include <stdint.h>
void ble_gatt_init(void);
// Envía SOS_START/SOS_CANCEL por indication. No hace nada si no hay conexión suscrita (el reintento lo repetirá).
void ble_gatt_send_frame_sos(uint8_t type, uint16_t seq, uint8_t source);
