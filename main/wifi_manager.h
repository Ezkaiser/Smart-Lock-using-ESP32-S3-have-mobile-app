#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "esp_err.h"
#include "esp_netif.h"
#include <stdbool.h>

// Hàm khởi tạo WiFi Station 
esp_err_t wifi_init_sta(void);

// Kiểm tra nhanh trạng thái kết nối
bool wifi_is_connected(void);

// Hàm lưu SSID và Password vào NVS (Flash)
esp_err_t wifi_save_config(const char *ssid, const char *password);

// Hàm đọc cấu hình từ NVS
esp_err_t wifi_load_config(char *ssid, char *password);

#endif