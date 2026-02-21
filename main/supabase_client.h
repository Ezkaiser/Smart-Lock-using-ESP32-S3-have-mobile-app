#ifndef SUPABASE_CLIENT_H
#define SUPABASE_CLIENT_H

#include "esp_err.h"
#include "esp_camera.h"

#ifdef __cplusplus
extern "C" {
#endif

// BIẾN CẤU HÌNH ĐỘNG (Dynamic Config) 
extern char SUPABASE_URL[128];
extern char SUPABASE_KEY[1024]; 

// Hàm khởi tạo (Sync giờ)
void supabase_init(void);

// Hàm quản lý cấu hình NVS
esp_err_t supabase_load_config(void);
esp_err_t supabase_save_config(const char *url, const char *key);

// Các hàm nghiệp vụ
esp_err_t supabase_log_access(int face_id, float score, const char *image_filename);
void supabase_sync_users(void);
esp_err_t supabase_upload_image(camera_fb_t *fb, char *filename_out);
void check_remote_command(void);

// Hàm này bị thiếu dẫn đến lỗi build
esp_err_t supabase_upload_face(int face_id, float *embedding, int len);

#ifdef __cplusplus
}
#endif

#endif