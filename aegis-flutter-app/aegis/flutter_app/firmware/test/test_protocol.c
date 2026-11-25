// Prueba en PC:  gcc -Wall -Imain test/test_protocol.c main/protocol.c -o /tmp/tp && /tmp/tp
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "protocol.h"

int main(void) {
    assert(aegis_crc16((const uint8_t *)"123456789", 9) == 0x29B1);
    aegis_frame_t f = {.type = AEGIS_T_SOS_START, .flags = 0, .seq = 513, .len = 3, .payload = {1, 2, 3}}, g;
    uint8_t buf[256];
    size_t n = aegis_encode(&f, buf, sizeof buf);
    assert(n == AEGIS_HEADER_SIZE + 3 + 2);
    assert(aegis_decode(buf, n, &g) && g.seq == 513 && g.len == 3 && g.payload[2] == 3);
    buf[7] ^= 0xFF;                                   // CRC corrupto
    assert(!aegis_decode(buf, n, &g));
    buf[7] ^= 0xFF; buf[0] = 2;                       // versión desconocida
    assert(!aegis_decode(buf, n, &g));
    assert(aegis_encode(&f, buf, 5) == 0);            // buffer corto
    aegis_health_t h = {.hr = 78, .spo2 = 97, .battery = 64, .temp_centi = 3660, .steps = 123456}, h2;
    uint8_t hp[AEGIS_HEALTH_LEN];
    aegis_pack_health(&h, hp);
    assert(hp[0] == 78 && hp[2] == (3660 & 0xFF) && hp[3] == (3660 >> 8) && hp[4] == (123456 & 0xFF));
    assert(aegis_unpack_health(hp, sizeof hp, &h2) && h2.steps == 123456 && h2.temp_centi == 3660 && h2.battery == 64);
    assert(!aegis_unpack_health(hp, 3, &h2));
    puts("protocol OK");
    return 0;
}
