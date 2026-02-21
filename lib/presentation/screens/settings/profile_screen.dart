import 'package:flutter/material.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/models/user_profile.dart';
import '../auth/login_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
// [MỚI] Import màn hình Setup WiFi
import '../device/setup_wifi_screen.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  bool _isLoading = false;
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getUserProfile();
    if (mounted) {
      setState(() {
        _userProfile = profile;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ Sơ Cá Nhân'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // --- AVATAR ---
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        _userProfile?.fullName.isNotEmpty == true 
                            ? _userProfile!.fullName[0].toUpperCase() 
                            : "U",
                        style: TextStyle(fontSize: 40, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // --- THÔNG TIN CÁ NHÂN ---
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildInfoRow(Icons.badge, "Họ và Tên", _userProfile?.fullName),
                          const Divider(),
                          _buildInfoRow(Icons.phone, "Số điện thoại", _userProfile?.phoneNumber),
                          const Divider(),
                          _buildInfoRow(Icons.email, "Email", _authService.currentUser?.email),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- CÁC NÚT CHỨC NĂNG ---

                  // 1. Nút Chỉnh sửa thông tin
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (_userProfile == null) return;
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EditProfileScreen(currentProfile: _userProfile!)),
                        );
                        if (result == true) _loadProfile();
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('CHỈNH SỬA THÔNG TIN'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. [MỚI] Nút Cài đặt WiFi (Provisioning)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Chuyển sang màn hình quét & setup WiFi
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SetupWifiScreen()),
                        );
                      },
                      icon: const Icon(Icons.wifi_find),
                      label: const Text('CÀI ĐẶT WIFI CHO KHÓA MỚI'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.blue), // Viền xanh cho nổi bật
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 3. Nút Đổi mật khẩu
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Đổi mật khẩu'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value ?? "---", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}