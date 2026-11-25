// Pinout preliminar (XIAO ESP32S3 Sense). CONFIRMAR con el esquemático de Seeed antes de cablear.
#pragma once
#define PIN_BTN_SOS   1   // D0, a GND, pull-up interno
#define PIN_BTN_AUX   2   // D1
#define PIN_MOTOR     4   // D3, gate del MOSFET
#define PIN_LED_RED   43  // D6 (la consola va por USB-CDC, no UART0)
#define PIN_LED_GREEN 44  // D7

#define SOS_HOLD_MS     2000  // mantener SOS 2 s: evita pulsaciones accidentales sin ser complejo
#define CANCEL_HOLD_MS  2000  // mantener AUX 2 s: cancelar
#define DEBOUNCE_MS     30
