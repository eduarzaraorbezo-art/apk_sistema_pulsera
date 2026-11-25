#include "buttons.h"
#include "ble_gatt.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "feedback.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "sos.h"

static void ota_validate_task(void *arg) {
    // Si el firmware nuevo llegó hasta aquí y las tareas siguen vivas, se confirma; si no, el bootloader hace rollback.
    vTaskDelay(pdMS_TO_TICKS(15000));
    esp_ota_mark_app_valid_cancel_rollback();
    vTaskDelete(NULL);
}

void app_main(void) {
    esp_err_t r = nvs_flash_init();
    if (r == ESP_ERR_NVS_NO_FREE_PAGES || r == ESP_ERR_NVS_NEW_VERSION_FOUND) { nvs_flash_erase(); nvs_flash_init(); }
    feedback_init();
    sos_init();          // recupera un SOS pendiente tras reinicio
    buttons_init();      // los botones funcionan aunque falle BLE
    ble_gatt_init();
    xTaskCreate(ota_validate_task, "ota_ok", 2048, NULL, 1, NULL);
    ESP_LOGI("aegis", "firmware 0.1.0 listo");
}
