#include "face_detect.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "img_converters.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <vector>
#include <list> 
#include <math.h>
#include <cstring> 

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_camera.h"

// Thư viện AI
#include "human_face_detect.hpp"       
#include "human_face_recognition.hpp"
#include "dl_image_define.hpp"

#include "global_state.h" // Để đọc biến cờ

extern "C" {
    #include "http_server.h" 
    #include "lock_ctrl.h" 
    #include "supabase_client.h"
}

static const char *TAG = "FACE_AI";
#define FACE_MATCH_THRESHOLD 0.35f 
#define MAX_FACES 10
#define LOG_COOLDOWN_MS 30000 

extern SemaphoreHandle_t xCameraMutex;

static HumanFaceDetect *detector = nullptr; 
static HumanFaceFeat *feat_extractor = nullptr;
static bool is_enrolling = false;
static bool ai_enabled = true;
static int64_t last_log_time = 0;

typedef struct {
    float embedding[512];
    int id;
    bool valid;
} face_record_t;

static face_record_t face_db[MAX_FACES];
static int next_id = 1;

// MATH UTILS 
static void normalize_vector(float *v, int len) {
    float sum = 0.0;
    for (int i = 0; i < len; i++) sum += v[i] * v[i];
    float magnitude = sqrt(sum);
    if (magnitude > 0) {
        for (int i = 0; i < len; i++) v[i] /= magnitude;
    }
}

static float dot_product(float *v1, float *v2, int len) {
    float dot = 0.0;
    for (int i = 0; i < len; i++) dot += v1[i] * v2[i];
    return dot; 
}

// DB UTILS 
void save_db() {
    nvs_handle_t handle;
    if (nvs_open("face_store", NVS_READWRITE, &handle) == ESP_OK) {
        nvs_set_blob(handle, "db_data", face_db, sizeof(face_db));
        nvs_set_i32(handle, "next_id", next_id);
        nvs_commit(handle);
        nvs_close(handle);
        ESP_LOGI(TAG, "DB Saved");
    }
}

void load_db() {
    nvs_handle_t handle;
    if (nvs_open("face_store", NVS_READONLY, &handle) == ESP_OK) {
        size_t size = sizeof(face_db);
        nvs_get_blob(handle, "db_data", face_db, &size);
        nvs_get_i32(handle, "next_id", (int32_t*)&next_id);
        nvs_close(handle);
        ESP_LOGI(TAG, "DB Loaded. Next ID: %d", next_id);
    } else {
        for(int i=0; i<MAX_FACES; i++) face_db[i].valid = false;
        next_id = 1;
    }
}

// Hàm đồng bộ từ Cloud về RAM
extern "C" void face_api_add_user_from_cloud(int face_id, float *embedding_buffer, int len) {
    if (len != 512) return;
    int slot = -1;
    for(int i=0; i<MAX_FACES; i++) { if (face_db[i].valid && face_db[i].id == face_id) { slot = i; break; } }
    if (slot == -1) { for(int i=0; i<MAX_FACES; i++) { if (!face_db[i].valid) { slot = i; break; } } }

    if (slot != -1) {
        normalize_vector(embedding_buffer, 512);
        memcpy(face_db[slot].embedding, embedding_buffer, 512 * sizeof(float));
        face_db[slot].id = face_id;
        face_db[slot].valid = true;
        if (face_id >= next_id) next_id = face_id + 1;
        ESP_LOGI(TAG, "Synced User ID: %d -> Slot: %d", face_id, slot);
    }
}

// BRIDGE FUNCTION
extern "C" bool app_extract_face_feature(camera_fb_t *fb, float *out_buf) {
    if (!detector || !feat_extractor || !fb) return false;

    // Convert JPG -> RGB888
    uint8_t *rgb_buf = (uint8_t *)heap_caps_malloc(fb->width * fb->height * 3, MALLOC_CAP_SPIRAM);
    if (!rgb_buf) {
        ESP_LOGE(TAG, "Bridge: Alloc RGB Failed");
        return false;
    }

    bool success = false;
    // Chuyển đổi định dạng ảnh
    if (fmt2rgb888(fb->buf, fb->len, fb->format, rgb_buf)) {
        dl::image::img_t img;
        img.data = rgb_buf;
        img.width = fb->width;
        img.height = fb->height;
        img.pix_type = dl::image::DL_IMAGE_PIX_TYPE_RGB888;

        // Chạy AI Detect
        std::list<dl::detect::result_t> faces = detector->run(img);
        if (faces.size() > 0) {
            // Lấy khuôn mặt đầu tiên (lớn nhất)
            auto &face = faces.front(); 
            // Chạy AI Recognition
            auto feat_tensor = feat_extractor->run(img, face.keypoint);
            if (feat_tensor) {
                // Copy kết quả ra buffer output
                memcpy(out_buf, feat_tensor->data, 512 * sizeof(float));
                normalize_vector(out_buf, 512);
                success = true;
            }
        }
    }
    free(rgb_buf);
    return success;
}

// LOGIC NHẬN DIỆN 
void handle_enrollment(float *feature) {
    int slot = -1;
    for(int i=0; i<MAX_FACES; i++) if(!face_db[i].valid) { slot=i; break; }
    
    if (slot != -1) {
        normalize_vector(feature, 512); 
        memcpy(face_db[slot].embedding, feature, 512 * sizeof(float));
        face_db[slot].id = next_id;
        face_db[slot].valid = true;
        ESP_LOGW(TAG, "ENROLL SUCCESS! Saved ID: %d", next_id);
        
        char msg[64];
        snprintf(msg, sizeof(msg), "{\"type\":\"alert\",\"msg\":\"Success ID %d\"}", next_id);

        supabase_upload_face(next_id, feature, 512);
        next_id++;
        save_db();
        is_enrolling = false; 
    } else {
        ESP_LOGE(TAG, "Database Full!");
        is_enrolling = false;
    }
}

void handle_recognition(float *feature, camera_fb_t *fb) {
    float max_score = 0.0f;
    int matched_id = -1;
    
    normalize_vector(feature, 512);

    for (int i = 0; i < MAX_FACES; i++) {
        if (face_db[i].valid) {
            float score = dot_product(feature, face_db[i].embedding, 512);
            if (score > max_score) { 
                max_score = score; 
                matched_id = face_db[i].id; 
            }
        }
    }

    if (max_score > FACE_MATCH_THRESHOLD) {
        ESP_LOGW(TAG, "MATCH ID: %d (Score: %.2f) -> OPEN DOOR!", matched_id, max_score);
        lock_open_door(); 

        int64_t now = esp_timer_get_time() / 1000;
        if (now - last_log_time > LOG_COOLDOWN_MS) {
            ESP_LOGI(TAG, "Sending Log...");
            char img_name[64] = {0};
            if (fb) {
                supabase_upload_image(fb, img_name);
            }
            supabase_log_access(matched_id, max_score, img_name);
            last_log_time = now;
        }
        vTaskDelay(pdMS_TO_TICKS(3000)); 
    }
}

// TASK CHÍNH
void face_recognition_task(void *pvParameters) {
    ESP_LOGI(TAG, "AI Task Started");
    size_t rgb_buf_len = 320 * 240 * 3; 
    uint8_t *rgb_buf = (uint8_t *)heap_caps_malloc(rgb_buf_len, MALLOC_CAP_SPIRAM);

    if (!rgb_buf) { ESP_LOGE(TAG, "Alloc RGB Fail"); vTaskDelete(NULL); }
    
    while (1) {
        // KIỂM TRA CỜ "G_IS_ENROLLING"
        if (g_is_enrolling) {
            // Nếu Supabase đang Enroll, task này sẽ ngủ 100ms liên tục để nhả Camera
            vTaskDelay(pdMS_TO_TICKS(100)); 
            continue; // Bỏ qua vòng lặp này
        }

        if (!ai_enabled) { vTaskDelay(pdMS_TO_TICKS(1000)); continue; }

        if (xSemaphoreTake(xCameraMutex, pdMS_TO_TICKS(500)) == pdTRUE) {
            camera_fb_t *fb = esp_camera_fb_get();
            
            if (fb) {
                // ---> ĐÃ THÊM: Lọc ảnh lỗi (< 2KB) để tránh crash JPEG decoder
                if (fb->len < 2048) {
                    ESP_LOGW(TAG, "Frame corrupted (%d bytes), skipping...", fb->len);
                    esp_camera_fb_return(fb);
                    xSemaphoreGive(xCameraMutex);
                    vTaskDelay(pdMS_TO_TICKS(50));
                    continue;
                }

                if (fb->width * fb->height * 3 > rgb_buf_len) {
                     esp_camera_fb_return(fb);
                     xSemaphoreGive(xCameraMutex);
                     continue;
                }

                if (fmt2rgb888(fb->buf, fb->len, fb->format, rgb_buf)) {
                    dl::image::img_t img;
                    img.data = rgb_buf;
                    img.width = fb->width; img.height = fb->height;
                    img.pix_type = dl::image::DL_IMAGE_PIX_TYPE_RGB888;

                    std::list<dl::detect::result_t> faces = detector->run(img);

                    if (faces.size() > 0) {
                        for (auto &face : faces) {
                            auto feat_tensor = feat_extractor->run(img, face.keypoint);
                            if (feat_tensor) {
                                if (is_enrolling) {
                                    handle_enrollment((float*)feat_tensor->data);
                                } else {
                                    handle_recognition((float*)feat_tensor->data, fb);
                                }
                            }
                        }
                    }
                }
                esp_camera_fb_return(fb); 
            }
            xSemaphoreGive(xCameraMutex); 
        }
        vTaskDelay(pdMS_TO_TICKS(200)); 
    }
    free(rgb_buf);
}

extern "C" void init_face_detection(void) {
    detector = new HumanFaceDetect(); 
    feat_extractor = new HumanFaceFeat();
    if (detector && feat_extractor) {
        ESP_LOGI(TAG, "AI Initialized");
        load_db();
    } else {
        ESP_LOGE(TAG, "AI Init Failed");
    }
}

extern "C" void start_face_recognition_task(void) {
    xTaskCreatePinnedToCore(face_recognition_task, "face_ai_task", 10240, NULL, 5, NULL, 1);
}

extern "C" void start_enrollment(void) { is_enrolling = true; ESP_LOGW(TAG, ">>> START ENROLLING MODE <<<"); }
extern "C" void set_ai_enable(bool enable) { ai_enabled = enable; }
extern "C" uint8_t* run_face_detect_and_draw(camera_fb_t *fb, size_t *out_len) { return nullptr; }