#include "http_server.h"
#include "camera_init.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_camera.h"
#include "face_detect.h"
#include "lock_ctrl.h"
#include "freertos/semphr.h"

extern "C" {
    #include "supabase_client.h" 
}

static const char *TAG = "HTTP";
static httpd_handle_t server = NULL;

// Biến Mutex toàn cục
extern SemaphoreHandle_t xCameraMutex;

static const char* INDEX_HTML = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>S3 Smart Lock</title>
<style>
body{background:#1a1a2e;color:#fff;font-family:sans-serif;text-align:center;margin:0;padding:20px}
img{max-width:100%;border:2px solid #e94560;border-radius:8px}
button{padding:15px 30px;margin:10px;border:none;border-radius:50px;cursor:pointer;color:#fff;font-size:16px;font-weight:bold;transition:0.3s}
.b1{background:#0f3460}.b1:hover{background:#16213e}
.b2{background:#e94560}.b2:hover{background:#c02739}
.b3{background:#00b894}.b3:hover{background:#008c72}
.ctrl{margin-top:20px;background:#16213e;padding:15px;border-radius:10px;display:inline-block}
input{margin:5px} label{font-weight:bold}
</style></head>
<body>
<h1>🔐 AI Smart Lock System</h1>
<img id="stream" src=""><br>
<div class="ctrl">
  <button class="b1" onclick="t()">📺 Stream ON/OFF</button>
  <button class="b2" onclick="e()">👤 Enroll New Face</button>
  <button class="b3" onclick="o()">🔓 Open Door</button>
</div><br>
<div class="ctrl">
  <label>Brightness (-2 to 2):</label> <input type="range" min="-2" max="2" value="0" onchange="c('brightness',this.value)"><br>
  <label>Quality (10-63):</label> <input type="range" min="10" max="63" value="12" onchange="c('quality',this.value)">
</div>
<script>
var s=false,u=location.origin+"/stream",i=document.getElementById("stream");
function t(){if(!s){i.src=u;s=true}else{i.src="";s=false}}
function e(){if(confirm("Enroll Mode: Look at camera!"))fetch("/enroll").then(r=>alert("Enroll Started..."))}
function o(){fetch("/open").then(r=>alert("Door command sent!"))}
function c(v,val){fetch("/control?var="+v+"&val="+val);} 
window.onload=t;
</script></body></html>
)rawliteral";

static esp_err_t cmd_handler(httpd_req_t *req) {
    char* buf;
    size_t buf_len;
    char variable[32] = {0,};
    char value[32] = {0,};

    buf_len = httpd_req_get_url_query_len(req) + 1;
    if (buf_len > 1) {
        buf = (char*)malloc(buf_len);
        if (!buf) {
            httpd_resp_send_500(req);
            return ESP_FAIL;
        }
        if (httpd_req_get_url_query_str(req, buf, buf_len) == ESP_OK) {
            if (httpd_query_key_value(buf, "var", variable, sizeof(variable)) == ESP_OK &&
                httpd_query_key_value(buf, "val", value, sizeof(value)) == ESP_OK) {
            } else {
                free(buf);
                httpd_resp_send_404(req);
                return ESP_FAIL;
            }
        }
        free(buf);
    } else {
        httpd_resp_send_404(req);
        return ESP_FAIL;
    }

    int val = atoi(value);
    sensor_t *s = esp_camera_sensor_get();
    int res = 0;

    if (!strcmp(variable, "framesize")) {
        if (s->pixformat == PIXFORMAT_JPEG) res = s->set_framesize(s, (framesize_t)val);
    }
    else if (!strcmp(variable, "quality")) res = s->set_quality(s, val);
    else if (!strcmp(variable, "contrast")) res = s->set_contrast(s, val);
    else if (!strcmp(variable, "brightness")) res = s->set_brightness(s, val);
    else if (!strcmp(variable, "saturation")) res = s->set_saturation(s, val);
    
    if (res) {
        return httpd_resp_send_500(req);
    }

    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    return httpd_resp_send(req, NULL, 0);
}

static esp_err_t index_handler(httpd_req_t *req) {
    httpd_resp_set_type(req, "text/html");
    return httpd_resp_send(req, INDEX_HTML, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t enroll_handler(httpd_req_t *req) {
    start_enrollment(); 
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_send(req, "OK", 2);
    return ESP_OK;
}

static esp_err_t open_handler(httpd_req_t *req) {
    lock_open_door(); 
    supabase_log_access(-1, 1.0f, NULL); 
    httpd_resp_send(req, "Door Opened", HTTPD_RESP_USE_STRLEN);
    return ESP_OK;
}

// STREAM HANDLER
#define PART_BOUNDARY "123456789000000000000987654321"
static const char* _STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char* _STREAM_BOUNDARY = "\r\n--" PART_BOUNDARY "\r\n";
static const char* _STREAM_PART = "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

static esp_err_t stream_handler(httpd_req_t *req) {
    camera_fb_t *fb = NULL;
    esp_err_t res = ESP_OK;
    char part_buf[64];

    res = httpd_resp_set_type(req, _STREAM_CONTENT_TYPE);
    if (res != ESP_OK) return res;

    while (true) {
        // Logic Mutex: Xin khóa trong 20ms
        if (xSemaphoreTake(xCameraMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
            
            fb = esp_camera_fb_get(); // Đã có khóa, lấy ảnh
            
            if (!fb) {
                ESP_LOGE(TAG, "Camera capture failed");
                xSemaphoreGive(xCameraMutex); // Trả khóa ngay
                res = ESP_FAIL;
            } else {
                // Gửi Boundary
                if (res == ESP_OK) res = httpd_resp_send_chunk(req, _STREAM_BOUNDARY, strlen(_STREAM_BOUNDARY));
                // Gửi Header
                if (res == ESP_OK) {
                    size_t hlen = snprintf(part_buf, 64, _STREAM_PART, fb->len);
                    res = httpd_resp_send_chunk(req, part_buf, hlen);
                }
                // Gửi Ảnh
                if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char *)fb->buf, fb->len);

                // Dùng xong trả ảnh & trả khóa
                esp_camera_fb_return(fb);
                xSemaphoreGive(xCameraMutex); 
            }
        } else {
            // Không lấy được khóa 
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (res != ESP_OK) break;
    }
    return res;
}

extern "C" esp_err_t start_http_server(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = 80;
    config.stack_size = 8192;

    if (httpd_start(&server, &config) == ESP_OK) {
        // Khai báo đầy đủ các trường
        httpd_uri_t index_uri = {
            .uri = "/", .method = HTTP_GET, .handler = index_handler, .user_ctx = NULL,
            .is_websocket = false, .handle_ws_control_frames = false, .supported_subprotocol = NULL
        };
        httpd_register_uri_handler(server, &index_uri);
        
        httpd_uri_t enroll_uri = {
            .uri = "/enroll", .method = HTTP_GET, .handler = enroll_handler, .user_ctx = NULL,
            .is_websocket = false, .handle_ws_control_frames = false, .supported_subprotocol = NULL
        };
        httpd_register_uri_handler(server, &enroll_uri);

        httpd_uri_t open_uri = {
            .uri = "/open", .method = HTTP_GET, .handler = open_handler, .user_ctx = NULL,
            .is_websocket = false, .handle_ws_control_frames = false, .supported_subprotocol = NULL
        };
        httpd_register_uri_handler(server, &open_uri);
        
        httpd_uri_t stream_uri = {
            .uri = "/stream", .method = HTTP_GET, .handler = stream_handler, .user_ctx = NULL,
            .is_websocket = false, .handle_ws_control_frames = false, .supported_subprotocol = NULL
        };
        httpd_register_uri_handler(server, &stream_uri);

        httpd_uri_t cmd_uri = {
            .uri = "/control", .method = HTTP_GET, .handler = cmd_handler, .user_ctx = NULL,
            .is_websocket = false, .handle_ws_control_frames = false, .supported_subprotocol = NULL
        };
        httpd_register_uri_handler(server, &cmd_uri);

        return ESP_OK;
    }
    return ESP_FAIL;
}

extern "C" void stop_http_server(void) { if (server) httpd_stop(server); }
extern "C" void ws_send_message(char *msg) { 
    ESP_LOGI(TAG, "WS Msg: %s", msg); 
}