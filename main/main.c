#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h" 
#include "nvs_flash.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_spiffs.h"
#include "mdns.h" 

#include "wifi_manager.h"
#include "camera_init.h"
#include "http_server.h"
#include "face_detect.h"     
#include "lock_ctrl.h"       
#include "supabase_client.h" 
#include "global_state.h" 

static const char *TAG = "MAIN";
SemaphoreHandle_t xCameraMutex = NULL;
extern void init_ble_server(void);

// Khởi tạo biến cờ toàn cục
volatile bool g_is_enrolling = false;

static void init_spiffs(void) {
    esp_vfs_spiffs_conf_t conf = { .base_path = "/spiffs", .partition_label = "spiffs", .max_files = 5, .format_if_mount_failed = true };
    if (esp_vfs_spiffs_register(&conf) != ESP_OK) ESP_LOGE(TAG, "Failed to mount SPIFFS");
}

// --- [BẮT ĐẦU] ĐOẠN CODE MDNS MỚI THÊM VÀO ---
void start_mdns_service()
{
    // 1. Khởi tạo mDNS
    esp_err_t err = mdns_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "MDNS Init failed: %d", err);
        return;
    }

    // 2. http://khoathongminh.local
    mdns_hostname_set("khoathongminh");

    // 3. Đặt tên mô tả (Instance Name)
    mdns_instance_name_set("Smart Lock Web Server");

    // 4. Đăng ký dịch vụ HTTP để máy tính/điện thoại dễ tìm thấy (ZeroConf)
    mdns_service_add(NULL, "_http", "_tcp", 80, NULL, 0);

    ESP_LOGI(TAG, "mDNS da khoi dong! Truy cap tai: http://khoathongminh.local");
}
// --- [KẾT THÚC] ĐOẠN CODE MDNS MỚI THÊM VÀO ---

void app_main(void)
{
    // 1. Khởi tạo NVS (Bộ nhớ lưu cấu hình)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
      ESP_ERROR_CHECK(nvs_flash_erase());
      ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // 2. Khởi tạo các thành phần phần cứng cơ bản
    init_spiffs();
    
    // Khởi tạo hệ thống khóa (Relay, Sensor, Nút bấm)
    lock_init(); 

    if(init_camera() == ESP_OK) {
        xCameraMutex = xSemaphoreCreateMutex();
        init_face_detection();
    }

    // 3. Load cấu hình WiFi & Database
    char dummy[10];
    bool has_wifi = (wifi_load_config(dummy, dummy) == ESP_OK);
    bool has_sup  = (supabase_load_config() == ESP_OK);

    // 4. Logic kết nối mạng
    if (has_wifi && has_sup) {
        ESP_LOGI(TAG, "Found Config. Connecting to WiFi...");
        
        if (wifi_init_sta() == ESP_OK) {
            ESP_LOGI(TAG, "WiFi Connected! Starting Services...");
            
            // --- [BẮT ĐẦU] GỌI HÀM MDNS TẠI ĐÂY ---
            start_mdns_service(); 
            // --- [KẾT THÚC] ---

            esp_netif_ip_info_t ip_info;
            esp_netif_t* netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
            if (netif) {
                esp_netif_get_ip_info(netif, &ip_info);
                printf("Web Interface: http://" IPSTR "\n", IP2STR(&ip_info.ip));
            }

            supabase_init();
            supabase_sync_users();
            start_http_server();
            start_face_recognition_task();

            // Biến đếm để quản lý thời gian check lệnh remote
            int cmd_check_tick = 0; 

            // VÒNG LẶP CHÍNH (ONLINE MODE) 
            while (1) {
                // A. LOGIC NÚT BẤM CẢM ỨNG
                if (lock_get_button_status() == 1) {
                    ESP_LOGI(TAG, "Phat hien nut bam EXIT -> Mo khoa!");
                    lock_open_door(); // Gọi hàm mở khóa (đã có logic tự đóng)
                    
                    // Chống rung: Chờ nhả tay ra mới chạy tiếp
                    while (lock_get_button_status() == 1) {
                        vTaskDelay(pdMS_TO_TICKS(100));
                    }
                }

                // B. LOGIC REMOTE COMMAND (Chạy mỗi 3 giây)
                if (cmd_check_tick >= 30) { 
                    check_remote_command(); 
                    cmd_check_tick = 0;
                }
                cmd_check_tick++;

                vTaskDelay(pdMS_TO_TICKS(100)); 
            }
        } else {
            ESP_LOGE(TAG, "WiFi Connection Failed. Switching to BLE...");
            init_ble_server();
        }
    } else {
        ESP_LOGW(TAG, "Missing Configuration (WiFi: %d, Supabase: %d)", has_wifi, has_sup);
        ESP_LOGW(TAG, "Starting BLE Provisioning Mode...");
        init_ble_server();
    }

    // --- VÒNG LẶP DỰ PHÒNG (OFFLINE / BLE MODE) ---
    while(1) {
        if (lock_get_button_status() == 1) {
            ESP_LOGI(TAG, "(Offline Mode) Phat hien nut bam EXIT -> Mo khoa!");
            lock_open_door();
            while (lock_get_button_status() == 1) {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}