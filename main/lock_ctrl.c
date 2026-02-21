#include "lock_ctrl.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "LOCK_CTRL";

// CẤU HÌNH CHÂN PIN 
#define RELAY_PIN           14 
#define TOUCH_BUTTON_PIN    21 
#define DOOR_SENSOR_PIN     38  

// --- CẤU HÌNH LOGIC ---
// Relay (Low Trigger): 0 = Bật, 1 = Tắt 
#define LOCK_OPEN_LEVEL     0  
#define LOCK_CLOSE_LEVEL    1  

// Cảm biến MC-38: Chạm = 0, Tách = 1
#define DOOR_CLOSED_LEVEL   0
#define DOOR_OPEN_LEVEL     1

static TaskHandle_t xUnlockTaskHandle = NULL;

void lock_init(void)
{
    ESP_LOGI(TAG, "Khoi tao he thong FULL OPTION...");

    // 1. Relay
    gpio_reset_pin(RELAY_PIN);
    gpio_set_direction(RELAY_PIN, GPIO_MODE_OUTPUT);
    gpio_set_level(RELAY_PIN, LOCK_CLOSE_LEVEL);

    // 2. Cảm biến từ
    gpio_reset_pin(DOOR_SENSOR_PIN);
    gpio_set_direction(DOOR_SENSOR_PIN, GPIO_MODE_INPUT);
    gpio_set_pull_mode(DOOR_SENSOR_PIN, GPIO_PULLUP_ONLY); 

    // 3. Nút cảm ứng
    gpio_reset_pin(TOUCH_BUTTON_PIN);
    gpio_set_direction(TOUCH_BUTTON_PIN, GPIO_MODE_INPUT);
    gpio_set_pull_mode(TOUCH_BUTTON_PIN, GPIO_PULLDOWN_ONLY); 

    ESP_LOGI(TAG, "Hardware Ready: Relay(14), Btn(21), Sensor(38), Buzz(42)");
}

int lock_get_button_status(void)
{
    return gpio_get_level(TOUCH_BUTTON_PIN);
}

// Luồng hoạt động chuẩn
static void unlock_logic_task(void *pvParameters)
{
    ESP_LOGW(TAG, "RELAY ON: MO KHOA");
    
    // 1. Mở chốt
    gpio_set_level(RELAY_PIN, LOCK_OPEN_LEVEL);

    // 2. Giữ chốt mở trong 4 giây
    ESP_LOGI(TAG, "Giu mo 4 giay...");
    for(int i=0; i<4; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }

    // 3. Bắt đầu giám sát để đóng lại
    ESP_LOGI(TAG, "Doi cua dong...");
    while (1) {
        // Nếu cửa đóng (Hai nam châm chạm nhau)
        if (gpio_get_level(DOOR_SENSOR_PIN) == DOOR_CLOSED_LEVEL) {
            ESP_LOGI(TAG, "Cua dong -> KHOA LAI");
            
            // Delay 0.5s để cửa ổn định vị trí
            vTaskDelay(pdMS_TO_TICKS(500)); 
            
            // Đóng chốt
            gpio_set_level(RELAY_PIN, LOCK_CLOSE_LEVEL);
            
            break; // Kết thúc quy trình
        } 
        vTaskDelay(pdMS_TO_TICKS(200));
    }

    xUnlockTaskHandle = NULL;
    vTaskDelete(NULL);
}

void lock_open_door(void)
{
    // Chỉ mở nếu chưa có tiến trình nào đang chạy
    if (xUnlockTaskHandle == NULL) {
        xTaskCreate(unlock_logic_task, "unlock_logic", 4096, NULL, 5, &xUnlockTaskHandle);
    }
}