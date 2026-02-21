#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_defs.h"
#include "esp_bt_main.h"
#include "esp_gatt_common_api.h"
#include "cJSON.h" 
#include "wifi_manager.h" 
#include "supabase_client.h"

#define TAG "BLE_PROV"
#define DEVICE_NAME "S3_SMART_LOCK_SETUP"

// UUID Config 
#define GATTS_SERVICE_UUID_TEST   0x9AB1 
#define GATTS_CHAR_UUID_TEST      0x1632

static uint8_t service_uuid128[16] = {
    0xc9, 0x2c, 0x98, 0x10, 0x76, 0x16, 0x46, 0xbf,
    0x8b, 0x36, 0xe9, 0x35, 0x55, 0x4f, 0xb1, 0x9a
};

static void gatts_profile_a_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param);

#define GATTS_NUM_HANDLE_TEST     4
#define PROFILE_NUM 1
#define PROFILE_A_APP_ID 0

struct gatts_profile_inst {
    esp_gatts_cb_t gatts_cb;
    uint16_t gatts_if;
    uint16_t app_id;
    uint16_t conn_id;
    uint16_t service_handle;
    esp_gatt_srvc_id_t service_id;
    uint16_t char_handle;
    esp_bt_uuid_t char_uuid;
    esp_gatt_perm_t perm;
    esp_gatt_char_prop_t property;
    uint16_t descr_handle;
    esp_bt_uuid_t descr_uuid;
};

static struct gatts_profile_inst gl_profile_tab[PROFILE_NUM] = {
    [PROFILE_A_APP_ID] = {
        .gatts_cb = gatts_profile_a_event_handler,
        .gatts_if = ESP_GATT_IF_NONE,
    },
};

static esp_ble_adv_data_t adv_data = {
    .set_scan_rsp = false,
    .include_name = true,
    .include_txpower = false,
    .min_interval = 0x0006,
    .max_interval = 0x0010,
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data =  NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = sizeof(service_uuid128),
    .p_service_uuid = service_uuid128,
    .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
};

static esp_ble_adv_params_t adv_params = {
    .adv_int_min        = 0x20,
    .adv_int_max        = 0x40,
    .adv_type           = ADV_TYPE_IND,
    .own_addr_type      = BLE_ADDR_TYPE_PUBLIC,
    .channel_map        = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

// HÀM XỬ LÝ NHẬN DATA TỪ APP 
void handle_write_event(esp_ble_gatts_cb_param_t *param) {
    if (param->write.len > 0) {
        char *data_str = (char *)malloc(param->write.len + 1);
        if (!data_str) return;
        
        memcpy(data_str, param->write.value, param->write.len);
        data_str[param->write.len] = '\0';
        
        ESP_LOGI(TAG, "Received Payload (%d bytes)", param->write.len);

        cJSON *root = cJSON_Parse(data_str);
        if (root == NULL) {
            ESP_LOGE(TAG, "Invalid JSON");
            free(data_str);
            return;
        }

        // Lấy thông tin từ JSON
        cJSON *ssid = cJSON_GetObjectItem(root, "ssid");
        cJSON *pass = cJSON_GetObjectItem(root, "password");
        cJSON *url  = cJSON_GetObjectItem(root, "url"); 
        cJSON *key  = cJSON_GetObjectItem(root, "key"); 

        if (cJSON_IsString(ssid)) {
            ESP_LOGW(TAG, "WiFi Config Received: %s", ssid->valuestring);
            // 1. Save WiFi
            const char *pass_str = (cJSON_IsString(pass)) ? pass->valuestring : "";
            wifi_save_config(ssid->valuestring, pass_str);

            // 2. Save Database
            if (cJSON_IsString(url) && cJSON_IsString(key)) {
                ESP_LOGW(TAG, "Supabase Config Received!");
                supabase_save_config(url->valuestring, key->valuestring);
            }

            ESP_LOGW(TAG, "All Config Saved! Restarting in 2s...");
            
            cJSON_Delete(root);
            free(data_str);
            vTaskDelay(pdMS_TO_TICKS(2000));
            esp_restart();
        }

        cJSON_Delete(root);
        free(data_str);
    }
}

static void gatts_profile_a_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param) {
    switch (event) {
    case ESP_GATTS_REG_EVT:
        esp_ble_gap_set_device_name(DEVICE_NAME);
        esp_ble_gap_config_adv_data(&adv_data);
        gl_profile_tab[PROFILE_A_APP_ID].service_id.is_primary = true;
        gl_profile_tab[PROFILE_A_APP_ID].service_id.id.inst_id = 0x00;
        gl_profile_tab[PROFILE_A_APP_ID].service_id.id.uuid.len = ESP_UUID_LEN_128;
        memcpy(gl_profile_tab[PROFILE_A_APP_ID].service_id.id.uuid.uuid.uuid128, service_uuid128, 16);
        esp_ble_gatts_create_service(gatts_if, &gl_profile_tab[PROFILE_A_APP_ID].service_id, GATTS_NUM_HANDLE_TEST);
        break;
    case ESP_GATTS_CREATE_EVT:
        gl_profile_tab[PROFILE_A_APP_ID].service_handle = param->create.service_handle;
        gl_profile_tab[PROFILE_A_APP_ID].char_uuid.len = ESP_UUID_LEN_16;
        gl_profile_tab[PROFILE_A_APP_ID].char_uuid.uuid.uuid16 = GATTS_CHAR_UUID_TEST;
        esp_ble_gatts_add_char(gl_profile_tab[PROFILE_A_APP_ID].service_handle, &gl_profile_tab[PROFILE_A_APP_ID].char_uuid,
                               ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
                               ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_WRITE, NULL, NULL);
        break;
    case ESP_GATTS_ADD_CHAR_EVT:
        gl_profile_tab[PROFILE_A_APP_ID].char_handle = param->add_char.attr_handle;
        esp_ble_gatts_start_service(gl_profile_tab[PROFILE_A_APP_ID].service_handle);
        break;
    case ESP_GATTS_CONNECT_EVT:
        ESP_LOGI(TAG, "CONNECTED");
        gl_profile_tab[PROFILE_A_APP_ID].conn_id = param->connect.conn_id;
        break;
    case ESP_GATTS_WRITE_EVT:
        handle_write_event(param);
        break;
    case ESP_GATTS_DISCONNECT_EVT:
        ESP_LOGI(TAG, "DISCONNECTED");
        esp_ble_gap_start_advertising(&adv_params);
        break;
    default:
        break;
    }
}

static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param) {
    if (event == ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT) {
        esp_ble_gap_start_advertising(&adv_params);
    }
}

static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param) {
    if (event == ESP_GATTS_REG_EVT) {
        if (param->reg.status == ESP_GATT_OK) gl_profile_tab[param->reg.app_id].gatts_if = gatts_if;
    }
    if (gatts_if == ESP_GATT_IF_NONE || gatts_if == gl_profile_tab[0].gatts_if) {
        if (gl_profile_tab[0].gatts_cb) gl_profile_tab[0].gatts_cb(event, gatts_if, param);
    }
}

void init_ble_server(void) {
    ESP_LOGI(TAG, "Initializing BLE Provisioning Server...");
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&bt_cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BLE));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());
    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(gatts_event_handler));
    ESP_ERROR_CHECK(esp_ble_gap_register_callback(gap_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(PROFILE_A_APP_ID));
    ESP_LOGI(TAG, "BLE Ready! Waiting for App...");
}