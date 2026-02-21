import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceService {
  final _supabase = Supabase.instance.client;

  // 1. Gửi lệnh mở khóa qua WiFi (Đã tối ưu logic)
  Future<void> sendUnlockCommand(String deviceId) async {
    try {
      // Xóa các lệnh 'pending' cũ để dọn đường cho lệnh mới
      await _supabase.from('device_commands')
          .delete()
          .eq('device_id', deviceId)
          .eq('status', 'pending');

      // Chèn lệnh mới
      await _supabase.from('device_commands').insert({
        'device_id': deviceId,
        'command': 'OPEN',
        'status': 'pending',
        'payload': {
          'requested_by': _supabase.auth.currentUser?.id ?? 'unknown_user',
          'platform': 'app_flutter',
          'timestamp': DateTime.now().toIso8601String()
        }
      });
      print("✅ WiFi: Đã ghi lệnh OPEN vào Database.");
    } catch (e) {
      throw "Lỗi gửi lệnh WiFi: $e";
    }
  }

  // 2. Tạo URL xem ảnh (FIX LỖI: No host specified in URI)
  Future<String?> createSignedImageUrl(String? imagePath) async {
    // Nếu imagePath null hoặc rỗng, trả về null ngay lập tức thay vì chuỗi rỗng ""
    if (imagePath == null || imagePath.isEmpty) return null;
    
    try {
      final signedUrl = await _supabase.storage
          .from('access_faces') 
          .createSignedUrl(imagePath, 3600);
      return signedUrl;
    } catch (e) {
      print("❌ Lỗi lấy URL ảnh: $e");
      return null; // Trả về null khi có lỗi để UI xử lý hiển thị icon lỗi
    }
  }

  // [MỚI] 3. Theo dõi trạng thái lệnh mở khóa theo thời gian thực
  Stream<List<Map<String, dynamic>>> watchCommandStatus(String deviceId) {
    return _supabase
        .from('device_commands')
        .stream(primaryKey: ['id'])
        .eq('device_id', deviceId)
        .order('id', ascending: false)
        .limit(1);
  }

  // 4. Claim thiết bị mới
  Future<void> claimDevice(String deviceId, String rawClaimCode, String nickname) async {
    final bytes = utf8.encode(rawClaimCode);
    final digest = sha256.convert(bytes);
    final hashedCode = digest.toString();

    final response = await _supabase
        .from('devices')
        .select()
        .eq('id', deviceId)
        .eq('claim_code', hashedCode);

    if (response.isEmpty) throw "Mã xác nhận hoặc ID thiết bị không đúng!";

    final userId = _supabase.auth.currentUser!.id;
    await _supabase.from('user_devices').insert({
      'user_id': userId,
      'device_id': deviceId,
      'nickname': nickname,
      'role': 'owner'
    });
  }

  // 5. Lấy lịch sử truy cập
  Future<List<Map<String, dynamic>>> getAccessLogs(String deviceId, int page, {int pageSize = 20}) async {
    final start = page * pageSize;
    final end = start + pageSize - 1;

    final data = await _supabase
        .from('access_logs')
        .select()
        .eq('device_id', deviceId)
        .order('created_at', ascending: false)
        .range(start, end);

    return List<Map<String, dynamic>>.from(data);
  }

  // 6. Xóa thiết bị
  Future<void> removeDevice(String deviceId) async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase
        .from('user_devices')
        .delete()
        .eq('user_id', userId)
        .eq('device_id', deviceId);
  }

  // 7. Đổi tên gợi nhớ
  Future<void> updateDeviceNickname(String deviceId, String newNickname) async {
    final userId = _supabase.auth.currentUser!.id;
    await _supabase
        .from('user_devices')
        .update({'nickname': newNickname})
        .eq('user_id', userId)
        .eq('device_id', deviceId);
  }

  // 8. Đóng/Mở khóa trực tiếp
  Future<void> toggleLock(String deviceId, bool currentLockStatus) async {
    await _supabase.from('devices').update({
      'is_locked': !currentLockStatus,
    }).eq('id', deviceId);
  }
}