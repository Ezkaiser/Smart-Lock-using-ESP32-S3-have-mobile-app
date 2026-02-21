#ifndef CAMERA_INIT_H
#define CAMERA_INIT_H

#include "esp_err.h"
#include "esp_camera.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

esp_err_t init_camera(void);
void deinit_camera(void);
camera_fb_t* capture_image(void);

extern SemaphoreHandle_t xCameraMutex;

#endif 