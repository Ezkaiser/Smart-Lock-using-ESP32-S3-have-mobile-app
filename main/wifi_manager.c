#include "wifi_manager.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"

static const char *TAG = "WIFI_MGR";

// Sự kiện để chờ kết nối
static EventGroupHandle_t s_wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT      BIT1

static int s_retry_num = 0;
#define MAXIMUM_RETRY 5

// XỬ LÝ NVS (LƯU TRỮ)

esp_err_t wifi_load_config(char *ssid, char *password) {
    nvs_handle_t my_handle;
    esp_err_t err = nvs_open("nvs", NVS_READONLY, &my_handle);
    if (err != ESP_OK) return err;

    size_t ssid_len = 32; // Độ dài tối đa của SSID
    size_t pass_len = 64; // Độ dài tối đa của Pass

    // Đọc dữ liệu từ key "wifi_ssid" và "wifi_pass"
    if (nvs_get_str(my_handle, "wifi_ssid", ssid, &ssid_len) != ESP_OK ||
        nvs_get_str(my_handle, "wifi_pass", password, &pass_len) != ESP_OK) {
        nvs_close(my_handle);
        return ESP_FAIL; // Chưa có cấu hình
    }

    nvs_close(my_handle);
    return ESP_OK;
}

esp_err_t wifi_save_config(const char *ssid, const char *password) {
    nvs_handle_t my_handle;
    esp_err_t err = nvs_open("nvs", NVS_READWRITE, &my_handle);
    if (err != ESP_OK) return err;

    // Ghi dữ liệu
    err |= nvs_set_str(my_handle, "wifi_ssid", ssid);
    err |= nvs_set_str(my_handle, "wifi_pass", password);
    err |= nvs_commit(my_handle); // Bắt buộc commit 

    nvs_close(my_handle);
    return err;
}

// LOGIC WIFI STATION 

static void wifi_event_handler(void* arg, esp_event_base_t event_base,
                                int32_t event_id, void* event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } 
    else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        if (s_retry_num < MAXIMUM_RETRY) {
            esp_wifi_connect();
            s_retry_num++;
            ESP_LOGW(TAG, "Retrying to connect to the AP (%d/%d)", s_retry_num, MAXIMUM_RETRY);
        } else {
            xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
        }
    } 
    else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
        s_retry_num = 0;
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

esp_err_t wifi_init_sta(void) {
    // 1. Load Config từ NVS trước
    char ssid[33] = {0};
    char password[65] = {0};

    if (wifi_load_config(ssid, password) != ESP_OK) {
        ESP_LOGE(TAG, "No WiFi config found in NVS. Please provision via BLE.");
        return ESP_FAIL; 
    }

    ESP_LOGI(TAG, "Loaded WiFi Config: SSID=%s", ssid);

    // 2. Khởi tạo WiFi Stack
    s_wifi_event_group = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_t instance_got_ip;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, &instance_any_id));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, &instance_got_ip));

    // 3. Set Config
    wifi_config_t wifi_config = {0};
    strncpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    strncpy((char *)wifi_config.sta.password, password, sizeof(wifi_config.sta.password));
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    // 4. Chờ kết quả
    ESP_LOGI(TAG, "Connecting to WiFi...");
    EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group,
            WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
            pdFALSE, pdFALSE, pdMS_TO_TICKS(10000)); // Timeout 10s

    if (bits & WIFI_CONNECTED_BIT) {
        return ESP_OK;
    } else {
        ESP_LOGE(TAG, "Failed to connect to WiFi.");
        return ESP_FAIL;
    }
}

bool wifi_is_connected(void) {
    if (s_wifi_event_group == NULL) return false;
    EventBits_t bits = xEventGroupGetBits(s_wifi_event_group);
    return (bits & WIFI_CONNECTED_BIT);
}