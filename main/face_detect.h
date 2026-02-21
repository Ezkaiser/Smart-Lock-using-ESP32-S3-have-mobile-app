#pragma once
#include "esp_err.h"
#include "esp_camera.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Khởi tạo AI và load dữ liệu khuôn mặt từ Flash (NVS)
void init_face_detection(void);

// Hàm này cho Web Stream dùng (Chỉ trả về NULL để stream nhẹ hơn)
uint8_t* run_face_detect_and_draw(camera_fb_t *fb, size_t *out_len);

// Bắt đầu chế độ học khuôn mặt mới
void start_enrollment(void);

// Hàm khởi động Task AI chạy ngầm 24/7
void start_face_recognition_task(void);

// Bật/Tắt AI 
void set_ai_enable(bool enable);

#ifdef __cplusplus
}
#endif