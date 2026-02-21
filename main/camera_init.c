#include "camera_init.h"
#include "camera_config.h"
#include "esp_log.h"

static const char *TAG = "CAMERA";

// Khởi tạo Camera 
esp_err_t init_camera(void)
{
    ESP_LOGI(TAG, "Initializing camera...");

    // 1. TẠO RA BIẾN CẤU HÌNH CAMERA
    camera_config_t camera_config = {
        .pin_pwdn = CAM_PIN_PWDN,
        .pin_reset = CAM_PIN_RESET,
        .pin_xclk = CAM_PIN_XCLK,
        .pin_sccb_sda = CAM_PIN_SIOD,
        .pin_sccb_scl = CAM_PIN_SIOC,

        .pin_d7 = CAM_PIN_D7,
        .pin_d6 = CAM_PIN_D6,
        .pin_d5 = CAM_PIN_D5,
        .pin_d4 = CAM_PIN_D4,
        .pin_d3 = CAM_PIN_D3,
        .pin_d2 = CAM_PIN_D2,
        .pin_d1 = CAM_PIN_D1,
        .pin_d0 = CAM_PIN_D0,
        .pin_vsync = CAM_PIN_VSYNC,
        .pin_href = CAM_PIN_HREF,
        .pin_pclk = CAM_PIN_PCLK,

        // Cấu hình chung
        .xclk_freq_hz = 16500000,
        .ledc_timer = LEDC_TIMER_0,
        .ledc_channel = LEDC_CHANNEL_0,
        .pixel_format = PIXFORMAT_JPEG,
        .frame_size = FRAMESIZE_QVGA,
        .jpeg_quality = 12,
        .fb_count = 2,
        .grab_mode = CAMERA_GRAB_WHEN_EMPTY,
        .fb_location = CAMERA_FB_IN_PSRAM, // Bắt buộc dùng PSRAM
    };

    // 2. Khởi tạo camera với cấu hình vừa tạo
    esp_err_t err = esp_camera_init(&camera_config);
    if (err != ESP_OK)
    {
        ESP_LOGE(TAG, "Camera init failed with error 0x%x", err);
        return err;
    }

    // 3. Lấy sensor
    sensor_t *s = esp_camera_sensor_get();
    if (s == NULL)
    {
        ESP_LOGE(TAG, "Failed to get camera sensor");
        return ESP_FAIL;
    }

    // 4. In thông tin sensor
    ESP_LOGI(TAG, "Camera sensor detected: PID=0x%02x VER=0x%02x MIDH=0x%02x MIDL=0x%02x",
             s->id.PID, s->id.VER, s->id.MIDH, s->id.MIDL);

    // 5. Áp dụng TẤT CẢ các cài đặt tùy chỉnh
    s->set_vflip(s, 0);
    s->set_hmirror(s, 0);
    s->set_brightness(s, 1);
    s->set_contrast(s, 1);
    s->set_saturation(s, 0);
    s->set_special_effect(s, 0);
    s->set_whitebal(s, 1);
    s->set_awb_gain(s, 1);
    s->set_wb_mode(s, 0);
    s->set_exposure_ctrl(s, 1);
    s->set_aec2(s, 0);
    s->set_gain_ctrl(s, 1);
    s->set_agc_gain(s, 0);
    s->set_gainceiling(s, (gainceiling_t)0);
    s->set_bpc(s, 0);
    s->set_wpc(s, 1);
    s->set_raw_gma(s, 1);
    s->set_lenc(s, 1);
    s->set_dcw(s, 1);
    s->set_colorbar(s, 0);

    ESP_LOGI(TAG, "Camera initialized successfully");
    return ESP_OK;
}

// Hàm 2: Hủy khởi tạo Camera 
void deinit_camera(void)
{
    ESP_LOGI(TAG, "Deinitializing camera...");
    esp_camera_deinit();
}

// Hàm 3: Chụp ảnh 
camera_fb_t* capture_image(void)
{
    camera_fb_t *fb = esp_camera_fb_get();

    if(!fb)
    {
        ESP_LOGE(TAG, "Camera capture failed");
        return NULL;
    }
    
    // Hàm gọi sẽ chịu trách nhiệm return(fb)
    return fb;
}