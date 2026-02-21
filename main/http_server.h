#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t start_http_server(void);
void stop_http_server(void);
void ws_send_message(char *msg);

#ifdef __cplusplus
}
#endif

#endif