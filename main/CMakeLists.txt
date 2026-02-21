idf_component_register(
    SRCS
        "main.c"
        "camera_init.c"
        "wifi_manager.c"
        "http_server.cpp"
        "face_detect.cpp"
        "lock_ctrl.c"
        "supabase_client.c"
        "ble_server.c"

    INCLUDE_DIRS 
        "."

    REQUIRES
        nvs_flash
        esp_wifi
        esp_http_server
        esp_http_client
        esp-tls
        esp_timer
        esp_netif
        esp_event
        esp_system
        spiffs
        bt
        mdns
        
        # AI & Driver 
        espressif__esp32-camera
        espressif__esp-dl
        espressif__human_face_detect
        espressif__human_face_recognition
        espressif__cjson
)