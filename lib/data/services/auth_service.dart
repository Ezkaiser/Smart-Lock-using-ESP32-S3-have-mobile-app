import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import check mạng
import '../models/user_profile.dart'; // Import đúng model

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. Đăng nhập
  Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // 2. Đăng ký
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone_number': phone,
      },
    );
  }

  // 3. Đăng xuất
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // 4. Lấy User hiện tại
  User? get currentUser => _supabase.auth.currentUser;

  // 5. Đổi password (có hash SHA-256 lịch sử)
  Future<void> updatePassword(String newPassword) async {
    final userId = currentUser?.id;
    if (userId == null) throw const AuthException('Chưa đăng nhập');

    final bytes = utf8.encode(newPassword);
    final digest = sha256.convert(bytes);
    final newPassHash = digest.toString();

    // Check trùng mật khẩu cũ
    final history = await _supabase
        .from('password_history')
        .select()
        .eq('user_id', userId)
        .eq('password_hash', newPassHash);

    if (history.isNotEmpty) {
      throw const AuthException('Mật khẩu này trùng với mật khẩu cũ. Vui lòng đổi lại!');
    }

    await _supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    await _supabase.from('password_history').insert({
      'user_id': userId,
      'password_hash': newPassHash,
    });
  }

  // 6. Validate mật khẩu
  String? validatePassword(String password) {
    if (password.length < 8) return 'Mật khẩu phải có ít nhất 8 ký tự';
    if (!password.contains(RegExp(r'[A-Z]'))) return 'Phải có ít nhất 1 chữ hoa';
    if (!password.contains(RegExp(r'[a-z]'))) return 'Phải có ít nhất 1 chữ thường';
    if (!password.contains(RegExp(r'[0-9]'))) return 'Phải có ít nhất 1 số';
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return 'Phải có ít nhất 1 ký tự đặc biệt';
    return null;
  }

  // 7. Lấy Profile
  Future<UserProfile?> getUserProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return UserProfile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  // 8. Update Profile
  Future<void> updateProfile({
    required String fullName,
    required String phone,
    String? recoveryEmail,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw const AuthException('Chưa đăng nhập');

    final updates = {
      'full_name': fullName,
      'phone_number': phone,
      'updated_at': DateTime.now().toIso8601String(),
      'recovery_email': recoveryEmail,
    };

    await _supabase.from('profiles').update(updates).eq('id', userId);
  }

  // 9. Reset Password Email
  Future<void> sendPasswordResetEmail(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // 10. Verify Old Password
  Future<bool> verifyOldPassword(String email, String oldPassword) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: oldPassword);
      return true;
    } catch (e) {
      return false;
    }
  }

  // 11. Khôi phục Session
  Future<bool> recoverSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null || session.isExpired) return false;
    return true;
  }

  // 12. [NÂNG CẤP] Kiểm tra mạng thực tế
  Future<bool> hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    return true;
  }
}