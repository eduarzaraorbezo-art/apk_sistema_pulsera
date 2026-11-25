#pragma once
#include <stdbool.h>
void feedback_init(void);
void feedback_vibrate(int ms);
void feedback_sos_active(bool on);   // LED rojo parpadeando
void feedback_ble_led(bool on);      // LED verde = conectada
void feedback_set_silent(bool s);    // modo silencioso: sin vibración ni luz visible
bool feedback_is_silent(void);
