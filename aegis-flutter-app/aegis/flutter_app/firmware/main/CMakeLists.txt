idf_component_register(
    SRCS "main.c" "protocol.c" "feedback.c" "buttons.c" "sos.c" "ble_gatt.c"
    INCLUDE_DIRS "."
    REQUIRES nvs_flash bt driver esp_timer app_update)
