#include "feedback.h"
#include "driver/gpio.h"
#include "esp_timer.h"
#include "pins.h"

static esp_timer_handle_t s_vib_off, s_blink;
static volatile bool s_silent;
static bool s_red_state;

static void vib_off_cb(void *arg) { gpio_set_level(PIN_MOTOR, 0); }
static void blink_cb(void *arg) {
    s_red_state = !s_red_state;
    gpio_set_level(PIN_LED_RED, s_silent ? 0 : s_red_state);
}

void feedback_init(void) {
    gpio_config_t out = {.pin_bit_mask = (1ULL << PIN_MOTOR) | (1ULL << PIN_LED_RED) | (1ULL << PIN_LED_GREEN),
                         .mode = GPIO_MODE_OUTPUT};
    gpio_config(&out);
    gpio_set_level(PIN_MOTOR, 0); gpio_set_level(PIN_LED_RED, 0); gpio_set_level(PIN_LED_GREEN, 0);
    esp_timer_create_args_t a1 = {.callback = vib_off_cb, .name = "vib_off"};
    esp_timer_create(&a1, &s_vib_off);
    esp_timer_create_args_t a2 = {.callback = blink_cb, .name = "blink"};
    esp_timer_create(&a2, &s_blink);
}

void feedback_vibrate(int ms) {
    if (s_silent) return;
    esp_timer_stop(s_vib_off);
    gpio_set_level(PIN_MOTOR, 1);
    esp_timer_start_once(s_vib_off, (uint64_t)ms * 1000);
}

void feedback_sos_active(bool on) {
    esp_timer_stop(s_blink);
    if (on) esp_timer_start_periodic(s_blink, 250 * 1000);
    else gpio_set_level(PIN_LED_RED, 0);
}

void feedback_ble_led(bool on) { gpio_set_level(PIN_LED_GREEN, on && !s_silent); }
void feedback_set_silent(bool s) { s_silent = s; if (s) { gpio_set_level(PIN_MOTOR, 0); gpio_set_level(PIN_LED_RED, 0); gpio_set_level(PIN_LED_GREEN, 0); } }
bool feedback_is_silent(void) { return s_silent; }
