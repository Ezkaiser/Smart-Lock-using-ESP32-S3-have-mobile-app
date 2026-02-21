#ifndef LOCK_CTRL_H
#define LOCK_CTRL_H

#ifdef __cplusplus
extern "C" {
#endif

// Hàm khởi tạo toàn bộ hệ thống khóa
void lock_init(void);

// Hàm kích hoạt quy trình mở khóa (Chạy Task giám sát)
void lock_open_door(void);

// Hàm kiểm tra trạng thái nút bấm cảm ứng (Trả về 1 nếu đang chạm)
int lock_get_button_status(void);

#ifdef __cplusplus
}
#endif

#endif // LOCK_CTRL_H