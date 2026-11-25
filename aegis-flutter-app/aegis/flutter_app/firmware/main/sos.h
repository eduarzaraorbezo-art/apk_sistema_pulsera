#pragma once
#include <stdint.h>
void sos_init(void);
void sos_trigger(uint8_t source);    // 1 = botón
void sos_cancel(void);
void sos_on_ack(uint16_t seq);       // llamado por BLE al recibir ACK de la APK
