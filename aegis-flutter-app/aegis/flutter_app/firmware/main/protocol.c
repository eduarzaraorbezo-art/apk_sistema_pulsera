#include "protocol.h"
#include <string.h>

uint16_t aegis_crc16(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
    return crc;
}

size_t aegis_encode(const aegis_frame_t *f, uint8_t *out, size_t cap) {
    if (f->len > AEGIS_MAX_PAYLOAD) return 0;
    size_t total = AEGIS_HEADER_SIZE + f->len + 2;
    if (cap < total) return 0;
    out[0] = AEGIS_PROTO_VERSION; out[1] = f->type; out[2] = f->flags;
    out[3] = f->seq & 0xFF; out[4] = f->seq >> 8;
    out[5] = f->len & 0xFF; out[6] = f->len >> 8;
    memcpy(out + AEGIS_HEADER_SIZE, f->payload, f->len);
    uint16_t crc = aegis_crc16(out, AEGIS_HEADER_SIZE + f->len);
    out[total - 2] = crc & 0xFF; out[total - 1] = crc >> 8;
    return total;
}

bool aegis_decode(const uint8_t *b, size_t n, aegis_frame_t *f) {
    if (n < AEGIS_HEADER_SIZE + 2 || b[0] != AEGIS_PROTO_VERSION) return false;
    uint16_t len = (uint16_t)(b[5] | (b[6] << 8));
    if (len > AEGIS_MAX_PAYLOAD || n != (size_t)AEGIS_HEADER_SIZE + len + 2) return false;
    uint16_t crc = (uint16_t)(b[n - 2] | (b[n - 1] << 8));
    if (crc != aegis_crc16(b, AEGIS_HEADER_SIZE + len)) return false;
    f->type = b[1]; f->flags = b[2]; f->seq = (uint16_t)(b[3] | (b[4] << 8)); f->len = len;
    memcpy(f->payload, b + AEGIS_HEADER_SIZE, len);
    return true;
}

void aegis_pack_health(const aegis_health_t *h, uint8_t out[AEGIS_HEALTH_LEN]) {
    out[0] = h->hr;
    out[1] = h->spo2;
    out[2] = h->temp_centi & 0xFF;
    out[3] = h->temp_centi >> 8;
    out[4] = h->steps & 0xFF;
    out[5] = (h->steps >> 8) & 0xFF;
    out[6] = (h->steps >> 16) & 0xFF;
    out[7] = (h->steps >> 24) & 0xFF;
    out[8] = h->battery;
}

bool aegis_unpack_health(const uint8_t *in, size_t len, aegis_health_t *h) {
    if (len != AEGIS_HEALTH_LEN) return false;
    h->hr = in[0];
    h->spo2 = in[1];
    h->temp_centi = (uint16_t)(in[2] | (in[3] << 8));
    h->steps = (uint32_t)in[4] | ((uint32_t)in[5] << 8) | ((uint32_t)in[6] << 16) | ((uint32_t)in[7] << 24);
    h->battery = in[8];
    return true;
}
