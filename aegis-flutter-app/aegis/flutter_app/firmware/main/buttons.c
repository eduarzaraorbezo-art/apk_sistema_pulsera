// Los botones funcionan sin teléfono ni Internet. Sondeo cada 10 ms (PENDIENTE: interrupción + light sleep).
#include "buttons.h"
#include "driver/gpio.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "feedback.h"
#include "pins.h"
#include "sos.h"

typedef struct {
    int pin;
    int hold_ms;
    bool down;           // estado estable (ya filtrado)
    int stable_ms;       // tiempo que el nivel crudo lleva igual
    bool raw_prev;
    int64_t t_down;
    bool long_fired, tick_fired;
} btn_t;

static btn_t s_sos = {.pin = PIN_BTN_SOS, .hold_ms = SOS_HOLD_MS};
static btn_t s_aux = {.pin = PIN_BTN_AUX, .hold_ms = CANCEL_HOLD_MS};

typedef enum { EV_NONE, EV_SHORT, EV_TICK, EV_LONG } ev_t;

static ev_t step(btn_t *b, int64_t now_ms) {
    bool raw = gpio_get_level(b->pin) == 0;
    if (raw == b->raw_prev) b->stable_ms += 10; else { b->raw_prev = raw; b->stable_ms = 0; }
    if (b->stable_ms < DEBOUNCE_MS) return EV_NONE;
    if (raw && !b->down) { b->down = true; b->t_down = now_ms; b->long_fired = b->tick_fired = false; return EV_NONE; }
    if (raw && b->down) {
        int64_t held = now_ms - b->t_down;
        if (!b->long_fired && held >= b->hold_ms) { b->long_fired = true; return EV_LONG; }
        if (!b->tick_fired && held >= b->hold_ms / 2) { b->tick_fired = true; return EV_TICK; } // aviso háptico a mitad
        return EV_NONE;
    }
    if (!raw && b->down) { b->down = false; return b->long_fired ? EV_NONE : EV_SHORT; }
    return EV_NONE;
}

static void button_task(void *arg) {
    for (;;) {
        int64_t now = esp_timer_get_time() / 1000;
        switch (step(&s_sos, now)) {
            case EV_TICK: feedback_vibrate(60); break;
            case EV_LONG: sos_trigger(1 /* botón SOS */); break;
            default: break;
        }
        switch (step(&s_aux, now)) {
            case EV_SHORT: feedback_set_silent(!feedback_is_silent()); break;   // alterna modo silencioso
            case EV_TICK: feedback_vibrate(60); break;
            case EV_LONG: sos_cancel(); break;
            default: break;
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

void buttons_init(void) {
    gpio_config_t in = {.pin_bit_mask = (1ULL << PIN_BTN_SOS) | (1ULL << PIN_BTN_AUX),
                        .mode = GPIO_MODE_INPUT, .pull_up_en = GPIO_PULLUP_ENABLE};
    gpio_config(&in);
    xTaskCreate(button_task, "buttons", 3072, NULL, 10, NULL);   // prioridad alta: el SOS manda
}
