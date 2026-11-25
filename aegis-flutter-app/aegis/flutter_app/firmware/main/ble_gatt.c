// GATT con NimBLE (ESP-IDF 5.x). UUID de 128 bits = los de BleProtocol.kt (en orden little-endian).
#include "ble_gatt.h"
#include <string.h>
#include "esp_log.h"
#include "feedback.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "nvs_flash.h"
#include "protocol.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "sos.h"

void ble_store_config_init(void);
static const char *TAG = "ble";

static ble_uuid128_t UUID_SVC = BLE_UUID128_INIT(0x6c, 0xf0, 0xdb, 0x00, 0x09, 0xd3, 0xa0, 0xac, 0xdd, 0x40, 0xce, 0xd6, 0x99, 0xd5, 0xb5, 0xaa);
static ble_uuid128_t UUID_SOS = BLE_UUID128_INIT(0x1c, 0xe2, 0x71, 0x4c, 0xf2, 0x3f, 0x16, 0x96, 0x2b, 0x43, 0xfb, 0x41, 0xd3, 0xe2, 0xd6, 0x63);
static ble_uuid128_t UUID_CMD = BLE_UUID128_INIT(0x6c, 0x2c, 0x89, 0x32, 0xda, 0xbe, 0x49, 0xab, 0x3c, 0x4e, 0x0b, 0xdb, 0x2d, 0xee, 0x8e, 0xc8);
static ble_uuid128_t UUID_RESP = BLE_UUID128_INIT(0x63, 0xa5, 0x4b, 0x5f, 0x4b, 0x4c, 0x9b, 0x88, 0xbc, 0x4e, 0x31, 0xe7, 0x76, 0x3c, 0xe4, 0x37);
static ble_uuid128_t UUID_STATUS = BLE_UUID128_INIT(0x83, 0x89, 0xc7, 0x78, 0x14, 0xb8, 0x04, 0xbd, 0x72, 0x4e, 0x22, 0x8d, 0xe5, 0xaa, 0xd6, 0x6f);

static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint16_t h_sos, h_resp, h_status;
static volatile bool s_sos_sub;
static uint8_t s_own_addr_type;
static uint8_t s_status_val[2] = {AEGIS_PROTO_VERSION, 0};

static int chr_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg) {
    if (ble_uuid_cmp(ctxt->chr->uuid, &UUID_CMD.u) == 0 && ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint8_t buf[AEGIS_HEADER_SIZE + AEGIS_MAX_PAYLOAD + 2];
        uint16_t n = OS_MBUF_PKTLEN(ctxt->om);
        if (n > sizeof buf) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        os_mbuf_copydata(ctxt->om, 0, n, buf);
        aegis_frame_t f;
        if (!aegis_decode(buf, n, &f)) return BLE_ATT_ERR_UNLIKELY;     // CRC/versión inválidos
        if (f.type == AEGIS_T_ACK) sos_on_ack(f.seq);
        return 0;
    }
    if (ble_uuid_cmp(ctxt->chr->uuid, &UUID_STATUS.u) == 0 && ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR)
        return os_mbuf_append(ctxt->om, s_status_val, sizeof s_status_val) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    return BLE_ATT_ERR_UNLIKELY;
}

static const struct ble_gatt_svc_def GATT_SVCS[] = {
    {.type = BLE_GATT_SVC_TYPE_PRIMARY,
     .uuid = &UUID_SVC.u,
     .characteristics = (struct ble_gatt_chr_def[]){
         {.uuid = &UUID_SOS.u, .access_cb = chr_access, .val_handle = &h_sos, .flags = BLE_GATT_CHR_F_INDICATE},
         // Escritura cifrada: Android inicia el emparejamiento al primer intento. PENDIENTE: autenticación HMAC por app.
         {.uuid = &UUID_CMD.u, .access_cb = chr_access, .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC},
         {.uuid = &UUID_RESP.u, .access_cb = chr_access, .val_handle = &h_resp, .flags = BLE_GATT_CHR_F_INDICATE},
         {.uuid = &UUID_STATUS.u, .access_cb = chr_access, .val_handle = &h_status, .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY},
         {0}}},
    {0}};

static void advertise(void);

static int gap_event(struct ble_gap_event *ev, void *arg) {
    switch (ev->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (ev->connect.status == 0) { s_conn = ev->connect.conn_handle; feedback_ble_led(true); ESP_LOGI(TAG, "conectada"); }
        else advertise();
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        s_conn = BLE_HS_CONN_HANDLE_NONE; s_sos_sub = false; feedback_ble_led(false);
        advertise();                                    // reconexión automática desde la APK
        break;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (ev->subscribe.attr_handle == h_sos) s_sos_sub = ev->subscribe.cur_indicate;
        break;
    case BLE_GAP_EVENT_ENC_CHANGE:
        break;
    case BLE_GAP_EVENT_REPEAT_PAIRING: {                // reemplaza bond viejo (PENDIENTE: política de seguridad)
        struct ble_gap_conn_desc d;
        ble_gap_conn_find(ev->repeat_pairing.conn_handle, &d);
        ble_store_util_delete_peer(&d.peer_id_addr);
        return BLE_GAP_REPEAT_PAIRING_RETRY;
    }
    default: break;
    }
    return 0;
}

static void advertise(void) {
    struct ble_hs_adv_fields f = {0};
    f.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    f.uuids128 = &UUID_SVC; f.num_uuids128 = 1; f.uuids128_is_complete = 1;
    ble_gap_adv_set_fields(&f);
    struct ble_hs_adv_fields rsp = {0};
    rsp.name = (uint8_t *)"AEGIS"; rsp.name_len = 5; rsp.name_is_complete = 1;
    ble_gap_adv_rsp_set_fields(&rsp);
    struct ble_gap_adv_params p = {0};
    p.conn_mode = BLE_GAP_CONN_MODE_UND; p.disc_mode = BLE_GAP_DISC_MODE_GEN;
    int rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &p, gap_event, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) ESP_LOGE(TAG, "adv_start rc=%d", rc);
}

static void on_sync(void) {
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own_addr_type);
    advertise();
}

void ble_gatt_send_frame_sos(uint8_t type, uint16_t seq, uint8_t source) {
    if (s_conn == BLE_HS_CONN_HANDLE_NONE || !s_sos_sub) return;
    aegis_frame_t f = {.type = type, .flags = 0, .seq = seq, .len = 2};
    f.payload[0] = source; f.payload[1] = 255;            // 255 = batería desconocida (PENDIENTE: MAX17048)
    uint8_t buf[AEGIS_HEADER_SIZE + 2 + 2];
    size_t n = aegis_encode(&f, buf, sizeof buf);
    struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, n);
    if (om == NULL) return;
    int rc = ble_gatts_indicate_custom(s_conn, h_sos, om);
    if (rc != 0) ESP_LOGW(TAG, "indicate rc=%d (se reintentará)", rc);
}

static void host_task(void *p) { nimble_port_run(); nimble_port_freertos_deinit(); }

void ble_gatt_init(void) {
    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_mitm = 0;                                // sin pantalla: Just Works (PENDIENTE: HMAC de aplicación)
    ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ESP_ERROR_CHECK(ble_gatts_count_cfg(GATT_SVCS));
    ESP_ERROR_CHECK(ble_gatts_add_svcs(GATT_SVCS));
    ble_svc_gap_device_name_set("AEGIS");
    ble_store_config_init();
    nimble_port_freertos_init(host_task);
}
