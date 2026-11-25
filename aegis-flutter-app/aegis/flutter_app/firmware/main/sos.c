// Estado SOS. Se guarda en NVS ANTES de intentar enviar: sobrevive a reinicios y desconexiones.
// No depende de Internet, del teléfono ni de IA.
#include "sos.h"
#include "ble_gatt.h"
#include "feedback.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "protocol.h"
#include "esp_log.h"

static const char *TAG = "sos";
static nvs_handle_t s_nvs;
static volatile uint8_t s_pending;      // 1 = SOS sin ACK
static volatile uint16_t s_seq;
static volatile uint8_t s_cancel_pending;
static volatile uint16_t s_cancel_seq;

static void persist(void) {
    nvs_set_u16(s_nvs, "seq", s_seq);
    nvs_set_u8(s_nvs, "pending", s_pending);
    nvs_commit(s_nvs);
}

void sos_trigger(uint8_t source) {
    if (s_pending) { feedback_vibrate(300); return; }   // ya activo: solo confirma
    s_seq++;
    s_pending = 1;
    s_cancel_pending = 0;
    persist();                                           // 1) registrar primero
    feedback_vibrate(500);                               // 2) confirmación háptica
    feedback_sos_active(true);                           // 3) indicador
    ESP_LOGW(TAG, "SOS seq=%u source=%u", s_seq, source);
    ble_gatt_send_frame_sos(AEGIS_T_SOS_START, s_seq, source);  // 4) primer intento inmediato (si hay enlace)
}

void sos_cancel(void) {
    if (!s_pending) return;
    s_pending = 0;
    s_cancel_pending = 1;
    s_cancel_seq = ++s_seq;
    persist();
    feedback_sos_active(false);
    feedback_vibrate(150);
    ble_gatt_send_frame_sos(AEGIS_T_SOS_CANCEL, s_cancel_seq, 0);
}

void sos_on_ack(uint16_t seq) {
    if (s_pending && seq == s_seq) {
        s_pending = 0;               // la APK ya lo registró; el LED rojo sigue hasta cancelar o fin manual
        persist();
        feedback_vibrate(120);
    }
    if (s_cancel_pending && seq == s_cancel_seq) s_cancel_pending = 0;
}

// Reintenta cada 3 s mientras no haya ACK; al reconectar el teléfono, el siguiente ciclo lo reenvía.
static void retry_task(void *arg) {
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(3000));
        if (s_pending) ble_gatt_send_frame_sos(AEGIS_T_SOS_START, s_seq, 1);
        else if (s_cancel_pending) ble_gatt_send_frame_sos(AEGIS_T_SOS_CANCEL, s_cancel_seq, 0);
    }
}

void sos_init(void) {
    nvs_open("sos", NVS_READWRITE, &s_nvs);
    uint16_t seq = 0; uint8_t pend = 0;
    nvs_get_u16(s_nvs, "seq", &seq);
    nvs_get_u8(s_nvs, "pending", &pend);
    s_seq = seq; s_pending = pend;
    if (s_pending) feedback_sos_active(true);   // reinicio con SOS pendiente: continúa
    xTaskCreate(retry_task, "sos_retry", 3072, NULL, 9, NULL);
}
