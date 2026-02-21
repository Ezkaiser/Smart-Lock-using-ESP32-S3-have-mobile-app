#include "supabase_client.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "cJSON.h"
#include "esp_sntp.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "lock_ctrl.h"
#include "esp_camera.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <string.h>
#include "global_state.h"

static const char *TAG = "SUPABASE";

char SUPABASE_URL[128] = {0};
char SUPABASE_KEY[1024] = {0}; 

extern SemaphoreHandle_t xCameraMutex;
extern void face_api_add_user_from_cloud(int face_id, float *embedding_buffer, int len);
extern bool app_extract_face_feature(camera_fb_t *fb, float *out_buf);

// 1. NVS CONFIG
esp_err_t supabase_load_config(void) {
    nvs_handle_t my_handle;
    if (nvs_open("nvs", NVS_READONLY, &my_handle) != ESP_OK) return ESP_FAIL;
    size_t url_len = sizeof(SUPABASE_URL); size_t key_len = sizeof(SUPABASE_KEY);
    if (nvs_get_str(my_handle, "sup_url", SUPABASE_URL, &url_len) != ESP_OK ||
        nvs_get_str(my_handle, "sup_key", SUPABASE_KEY, &key_len) != ESP_OK) { nvs_close(my_handle); return ESP_FAIL; }
    nvs_close(my_handle); ESP_LOGI(TAG, "Loaded Config: URL=%s", SUPABASE_URL); return ESP_OK;
}

esp_err_t supabase_save_config(const char *url, const char *key) {
    nvs_handle_t my_handle;
    if (nvs_open("nvs", NVS_READWRITE, &my_handle) != ESP_OK) return ESP_FAIL;
    nvs_set_str(my_handle, "sup_url", url); nvs_set_str(my_handle, "sup_key", key);
    esp_err_t err = nvs_commit(my_handle); nvs_close(my_handle); return err;
}

// 2. HTTP CLIENT
static esp_http_client_handle_t _init_client(const char *endpoint, esp_http_client_method_t method, int rx_buf, int tx_buf, bool keep_alive) {
    if (strlen(SUPABASE_URL) < 5) { ESP_LOGE(TAG, "Missing Supabase URL!"); return NULL; }
    char url[300]; snprintf(url, sizeof(url), "%s%s", SUPABASE_URL, endpoint);
    
    // Tăng buffer handle response header
    if (tx_buf < 8192) tx_buf = 8192; 
    if (rx_buf < 20480) rx_buf = 20480; 

    esp_http_client_config_t config = { .url = url, .method = method, .crt_bundle_attach = esp_crt_bundle_attach, .timeout_ms = 20000, .buffer_size = rx_buf, .buffer_size_tx = tx_buf, .keep_alive_enable = keep_alive, .user_data = NULL, .disable_auto_redirect = false, };
    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (!client) return NULL;
    esp_http_client_set_header(client, "apikey", SUPABASE_KEY);
    char auth_header[1200]; snprintf(auth_header, sizeof(auth_header), "Bearer %s", SUPABASE_KEY);
    esp_http_client_set_header(client, "Authorization", auth_header);
    if (method == HTTP_METHOD_POST || method == HTTP_METHOD_PATCH) esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_header(client, "Prefer", "return=representation"); 
    return client;
}

void supabase_init(void) {
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL); esp_sntp_setservername(0, "pool.ntp.org"); esp_sntp_init();
    setenv("TZ", "CET-7CEST,M3.5.0,M10.5.0/3", 1); tzset();
}

esp_err_t supabase_upload_image(camera_fb_t *fb, char *filename_out) {
    if (strlen(filename_out) == 0) snprintf(filename_out, 64, "log_%lu.jpg", (unsigned long)xTaskGetTickCount());
    char endpoint[128]; snprintf(endpoint, sizeof(endpoint), "/storage/v1/object/access_faces/%s", filename_out);
    esp_http_client_handle_t client = _init_client(endpoint, HTTP_METHOD_POST, 4096, fb->len + 4096, false);
    if (!client) return ESP_FAIL;
    esp_http_client_set_header(client, "Content-Type", "image/jpeg");
    esp_http_client_set_post_field(client, (const char *)fb->buf, fb->len);
    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) ESP_LOGI(TAG, "📸 Image Uploaded: %s", filename_out);
    else ESP_LOGE(TAG, "Upload Failed: %s", esp_err_to_name(err));
    esp_http_client_cleanup(client);
    return err;
}

// ---> ĐÃ SỬA: Chuyển sang POST và truyền face_id vào Database
esp_err_t supabase_upload_face(int face_id, float *embedding, int len) {
    ESP_LOGI(TAG, "Uploading New Face to Cloud. Face ID: %d", face_id);
    char endpoint[64] = "/rest/v1/users"; // URL gốc của bảng users
    
    // Dùng HTTP_METHOD_POST để tạo dòng mới
    esp_http_client_handle_t client = _init_client(endpoint, HTTP_METHOD_POST, 4096, 8192, false);
    if (!client) return ESP_FAIL;

    cJSON *root = cJSON_CreateObject();
    
    // Gắn Face ID vào Database
    cJSON_AddNumberToObject(root, "face_id", face_id);

    cJSON *emb_array = cJSON_CreateArray();
    for (int i = 0; i < len; i++) cJSON_AddItemToArray(emb_array, cJSON_CreateNumber(embedding[i]));
    cJSON_AddItemToObject(root, "embedding", emb_array);

    char *json_str = cJSON_PrintUnformatted(root);
    esp_http_client_set_post_field(client, json_str, strlen(json_str));
    esp_err_t err = esp_http_client_perform(client);

    if (err == ESP_OK) {
        int status = esp_http_client_get_status_code(client);
        // Status 201 là Created (Tạo thành công)
        if (status == 201 || status == 200 || status == 204) ESP_LOGI(TAG, "New Face Inserted to Cloud!");
        else { ESP_LOGE(TAG, "Insert Face Error: %d", status); err = ESP_FAIL; }
    } else ESP_LOGE(TAG, "Insert Face Failed: %s", esp_err_to_name(err));

    cJSON_Delete(root); free(json_str); esp_http_client_cleanup(client);
    return err;
}

esp_err_t supabase_log_access(int face_id, float score, const char *image_filename) {
    esp_http_client_handle_t client = _init_client("/rest/v1/access_logs", HTTP_METHOD_POST, 0, 0, false);
    if (!client) return ESP_FAIL;
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "device_id", "S3_LOCK_01");
    if(face_id >= 0) {
        cJSON_AddNumberToObject(root, "face_id", face_id); 
        char desc[64]; snprintf(desc, sizeof(desc), "Face ID Match (%.2f)", score);
        cJSON_AddStringToObject(root, "description", desc);
        cJSON_AddNumberToObject(root, "score", score);
    } else cJSON_AddStringToObject(root, "description", "Remote Unlock via App");
    if (image_filename && strlen(image_filename) > 0) cJSON_AddStringToObject(root, "image_url", image_filename);
    char *json_str = cJSON_PrintUnformatted(root);
    esp_http_client_set_post_field(client, json_str, strlen(json_str));
    esp_http_client_perform(client);
    cJSON_Delete(root); free(json_str); esp_http_client_cleanup(client);
    return ESP_OK;
}

// ---> ĐÃ SỬA: Thêm &limit=100 và select=face_id
void supabase_sync_users(void) {
    ESP_LOGI(TAG, "Syncing Users from Table 'users'...");
    esp_http_client_handle_t client = _init_client("/rest/v1/users?select=face_id,embedding&limit=100", HTTP_METHOD_GET, 20480, 0, false);
    if (!client) return;

    // Mở kết nối thủ công
    esp_err_t err = esp_http_client_open(client, 0);
    if (err == ESP_OK) {
        // Lấy Content-Length
        int content_len = esp_http_client_fetch_headers(client);
        
        // Nếu length <= 0 (Chunked Encoding), ta giả định buffer thật lớn (128KB)
        int total_to_read = content_len;
        if (total_to_read <= 0) {
            ESP_LOGW(TAG, "Content length unknown (Chunked). Using 128KB Buffer from PSRAM.");
            total_to_read = 128 * 1024; 
        }

        // Cấp phát bộ nhớ trong SPIRAM
        char *buf = (char *)heap_caps_malloc(total_to_read + 1, MALLOC_CAP_SPIRAM);
        if (buf) {
            int total_read = 0;
            while (1) {
                int r = esp_http_client_read_response(client, buf + total_read, total_to_read - total_read);
                if (r < 0) {
                    ESP_LOGE(TAG, "Read Error");
                    break;
                }
                if (r == 0) {
                    break;
                }
                total_read += r;
                // Tránh tràn buffer
                if (total_read >= total_to_read) break; 
            }
            buf[total_read] = 0; // Kết thúc chuỗi

            if (total_read > 0) {
                ESP_LOGI(TAG, "Downloaded %d bytes. Parsing JSON...", total_read);
                cJSON *root = cJSON_Parse(buf);
                if (root) {
                    if (cJSON_IsArray(root)) {
                        int count = cJSON_GetArraySize(root);
                        ESP_LOGI(TAG, "FOUND %d USERS in Database!", count);
                        
                        for (int i = 0; i < count; i++) {
                            cJSON *item = cJSON_GetArrayItem(root, i);
                            // SỬA: Parse trường "face_id"
                            cJSON *id_json = cJSON_GetObjectItem(item, "face_id");
                            cJSON *emb_json = cJSON_GetObjectItem(item, "embedding");
                            
                            if (id_json && emb_json && !cJSON_IsNull(emb_json)) {
                                int uid = id_json->valueint;
                                // Embedding có thể là String hoặc JSON Array
                                cJSON *emb_array = cJSON_IsString(emb_json) ? cJSON_Parse(emb_json->valuestring) : emb_json;
                                
                                if (cJSON_IsArray(emb_array)) {
                                    int dims = cJSON_GetArraySize(emb_array);
                                    if (dims == 512) {
                                        float *emb_buf = (float *)malloc(512 * sizeof(float));
                                        for(int j=0; j<512; j++) {
                                            emb_buf[j] = (float)cJSON_GetArrayItem(emb_array, j)->valuedouble;
                                        }
                                        face_api_add_user_from_cloud(uid, emb_buf, 512);
                                        free(emb_buf);
                                    }
                                    if (cJSON_IsString(emb_json)) cJSON_Delete(emb_array);
                                }
                            }
                        }
                    } else {
                        ESP_LOGE(TAG, "JSON is not an array");
                    }
                    cJSON_Delete(root);
                } else {
                    ESP_LOGE(TAG, "cJSON Parse Failed (JSON Broken or Empty)");
                }
            } else {
                ESP_LOGW(TAG, "Response Empty (0 bytes)");
            }
            free(buf);
        } else {
            ESP_LOGE(TAG, "Malloc Failed (Out of PSRAM?)");
        }
    } else {
        ESP_LOGE(TAG, "HTTP Open Failed: %s", esp_err_to_name(err));
    }
    esp_http_client_cleanup(client);
}

static void mark_command_executed(int cmd_id) {
    char endpoint[64]; snprintf(endpoint, sizeof(endpoint), "/rest/v1/device_commands?id=eq.%d", cmd_id);
    esp_http_client_handle_t client = _init_client(endpoint, HTTP_METHOD_PATCH, 0, 0, false);
    if (client) {
        const char *json = "{\"status\":\"executed\"}";
        esp_http_client_set_post_field(client, json, strlen(json));
        esp_http_client_perform(client);
        esp_http_client_cleanup(client);
    }
}

static void perform_enrollment(int user_id) {
    ESP_LOGW(TAG, "START ENROLLMENT ID: %d", user_id);
    g_is_enrolling = true; 
    vTaskDelay(pdMS_TO_TICKS(1500)); 

    if (xSemaphoreTake(xCameraMutex, pdMS_TO_TICKS(5000))) { 
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb) {
            ESP_LOGI(TAG, "Captured. Extracting Features...");
            char filename[64];
            snprintf(filename, sizeof(filename), "face_%d_%lu.jpg", user_id, (unsigned long)xTaskGetTickCount());
            supabase_upload_image(fb, filename);

            float *new_embedding = (float *)malloc(512 * sizeof(float));
            if (new_embedding) {
                if (app_extract_face_feature(fb, new_embedding)) {
                    ESP_LOGI(TAG, "Face Detected. Updating User on Cloud...");
                    supabase_upload_face(user_id, new_embedding, 512);
                    face_api_add_user_from_cloud(user_id, new_embedding, 512);
                } else {
                    ESP_LOGE(TAG, "No Face Detected");
                }
                free(new_embedding);
            }
            esp_camera_fb_return(fb);
        } else ESP_LOGE(TAG, "Capture Failed");
        xSemaphoreGive(xCameraMutex); 
    } else ESP_LOGE(TAG, "Camera Busy");

    g_is_enrolling = false;
    ESP_LOGI(TAG, "Enrollment Finished");
}

void check_remote_command(void) {
    // Tăng buffer rx_buf lên để chứa đủ JSON payload từ Flutter
    esp_http_client_handle_t client = _init_client("/rest/v1/device_commands?select=id,command,payload&status=eq.pending&device_id=eq.S3_LOCK_01", HTTP_METHOD_GET, 8192, 0, false);
    if (!client) return;

    esp_err_t err = esp_http_client_open(client, 0);
    if (err == ESP_OK) {
        esp_http_client_fetch_headers(client);
        
        // Không dùng get_content_length vì dễ bị lỗi với Chunked Encoding
        char *buf = (char *)heap_caps_malloc(8192, MALLOC_CAP_SPIRAM); // Dùng PSRAM cho an toàn
        if (buf) {
            int read_len = esp_http_client_read_response(client, buf, 8191);
            if (read_len > 0) {
                buf[read_len] = 0;
                cJSON *root = cJSON_Parse(buf);
                if (cJSON_IsArray(root) && cJSON_GetArraySize(root) > 0) {
                    cJSON *item = cJSON_GetArrayItem(root, 0);
                    
                    cJSON *id_obj = cJSON_GetObjectItem(item, "id");
                    cJSON *cmd_obj = cJSON_GetObjectItem(item, "command");

                    if (id_obj && cmd_obj) {
                        int id = id_obj->valueint;
                        char *cmd = cmd_obj->valuestring;
                        ESP_LOGW(TAG, "🔥 NHẬN LỆNH MỚI: %s (ID: %d)", cmd, id);

                        if (strcmp(cmd, "OPEN") == 0) {
                            lock_open_door(); // Gọi hàm điều khiển Relay
                            
                            // Log và upload ảnh (giữ nguyên logic của bạn)
                            char img[64] = {0};
                            if (xSemaphoreTake(xCameraMutex, pdMS_TO_TICKS(1000))) {
                                camera_fb_t *fb = esp_camera_fb_get();
                                if (fb) { 
                                    supabase_upload_image(fb, img); 
                                    esp_camera_fb_return(fb); 
                                }
                                xSemaphoreGive(xCameraMutex);
                            }
                            supabase_log_access(-1, 1.0, img);
                            mark_command_executed(id); // Quan trọng: Đổi pending -> executed
                        }
                        // Xử lý các lệnh khác (ENROLL...)
                    }
                }
                cJSON_Delete(root);
            }
            free(buf);
        }
    } else {
        ESP_LOGE(TAG, "Lỗi kết nối Polling: %s", esp_err_to_name(err));
    }
    esp_http_client_cleanup(client);
}