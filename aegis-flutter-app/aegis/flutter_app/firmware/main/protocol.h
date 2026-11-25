// Protocolo BLE AEGIS v1. Debe coincidir con android/.../ble/BleProtocol.kt
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AEGIS_PROTO_VERSION 1
#define AEGIS_HEADER_SIZE 7       // ver, tipo, flags, seq(2 LE), len(2 LE)
#define AEGIS_MAX_PAYLOAD 200     // marco máx. 209 B < MTU 247 - 3

enum { AEGIS_T_SOS_START = 1, AEGIS_T_SOS_CANCEL = 2, AEGIS_T_ACK = 10, AEGIS_T_HEARTBEAT = 11,
       AEGIS_T_HEALTH = 12,      /* pulsera→app: hr,spo2,temp,pasos,batería (9 bytes) */
       AEGIS_T_BUTTON = 13,      /* pulsera→app: [gesto] */
       AEGIS_T_CONFIG = 14,      /* app→pulsera: [sos_hold_s, flags, arm_s] */
       AEGIS_T_COMMAND = 15,     /* app→pulsera: [cmd, arg, ...] */
       AEGIS_T_BAND_ALERT = 16,  /* pulsera→app: [código, valor] */
       AEGIS_T_MEDIA = 17,       /* pulsera→app: trozo de archivo (reservado) */
       AEGIS_T_SLEEP = 18        /* pulsera→app: [inicio u32, fin u32 (epoch), calidad u8] */ };
enum { AEGIS_G_SOS_DOUBLE = 1, AEGIS_G_SOS_TRIPLE, AEGIS_G_AUX_SHORT, AEGIS_G_AUX_DOUBLE, AEGIS_G_AUX_HOLD };
enum { AEGIS_CMD_FIND = 1, AEGIS_CMD_VIBRATE, AEGIS_CMD_TIME_SYNC, AEGIS_CMD_SPRAY_DISARM,
       AEGIS_CMD_REC_START, AEGIS_CMD_REC_STOP, AEGIS_CMD_SNAPSHOT /* arg REC_START: 1 audio, 2 foto, 3 video */ };
enum { AEGIS_A_FALL = 1, AEGIS_A_LOW_BATTERY, AEGIS_A_OFF_WRIST, AEGIS_A_TAMPER,
       AEGIS_A_SPRAY_ARMED, AEGIS_A_SPRAY_FIRED, AEGIS_A_SPRAY_DISARMED,
       AEGIS_A_REC_STARTED, AEGIS_A_REC_STOPPED, AEGIS_A_MEDIA_READY /* valor = nº de archivos listos */ };
enum { AEGIS_CFG_FALL = 1, AEGIS_CFG_SPRAY = 2, AEGIS_CFG_HAPTIC = 4 };

// Telemetría de salud (notify en la característica STATUS). Payload de 9 B:
// hr u8 | spo2 u8 | temp u16 LE (0.01 °C) | steps u32 LE | battery u8. 0 = sin lectura (battery 0xFF = desconocida).
#define AEGIS_HEALTH_LEN 9
typedef struct {
    uint8_t hr, spo2, battery;
    uint16_t temp_centi;
    uint32_t steps;
} aegis_health_t;
void aegis_pack_health(const aegis_health_t *h, uint8_t out[AEGIS_HEALTH_LEN]);
bool aegis_unpack_health(const uint8_t *in, size_t len, aegis_health_t *h);

typedef struct {
    uint8_t type;
    uint8_t flags;
    uint16_t seq;
    uint16_t len;
    uint8_t payload[AEGIS_MAX_PAYLOAD];
} aegis_frame_t;

uint16_t aegis_crc16(const uint8_t *data, size_t len);                     // CRC-16/CCITT-FALSE
size_t aegis_encode(const aegis_frame_t *f, uint8_t *out, size_t cap);     // 0 si error
bool aegis_decode(const uint8_t *buf, size_t len, aegis_frame_t *out);     // false si versión/longitud/CRC inválidos
