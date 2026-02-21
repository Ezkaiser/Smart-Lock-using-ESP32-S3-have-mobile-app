import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/models/user_profile.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile currentProfile;
  const EditProfileScreen({super.key, required this.currentProfile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _recoveryEmailController;
  String _completePhoneNumber = ''; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentProfile.fullName);
    _recoveryEmailController = TextEditingController(text: widget.currentProfile.recoveryEmail ?? '');
    _completePhoneNumber = widget.currentProfile.phoneNumber;
  }

  Future<void> _handleSave() async {
    // Nếu validator trả về lỗi thì dừng lại, không lưu
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.updateProfile(
        fullName: _nameController.text.trim(),
        phone: _completePhoneNumber,
        recoveryEmail: _recoveryEmailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật thành công!'), backgroundColor: Colors.green));
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _recoveryEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh Sửa Hồ Sơ')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form( 
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Họ và Tên', prefixIcon: Icon(Icons.badge)),
                  validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập tên' : null,
                ),
                const SizedBox(height: 20),
                
                // --- [ĐOẠN ĐÃ SỬA] ---
                IntlPhoneField(
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    border: OutlineInputBorder(),
                    counterText: "", // Ẩn bộ đếm
                  ),
                  initialCountryCode: 'VN',
                  initialValue: _completePhoneNumber.isNotEmpty && !_completePhoneNumber.startsWith('+') 
                      ? _completePhoneNumber : null,
                  
                  // 1. Tắt check độ dài mặc định (Để không báo lỗi khi nhập số 0)
                  disableLengthCheck: true, 
                  
                  // 2. Tự viết hàm kiểm tra đơn giản (9-11 số là OK)
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (phone) {
                    if (phone == null || phone.number.isEmpty) return 'Vui lòng nhập số điện thoại';
                    // Kiểm tra chỉ chứa số
                    if (!RegExp(r'^[0-9]+$').hasMatch(phone.number)) return 'Chỉ được nhập số';
                    // Kiểm tra độ dài an toàn (bao gồm cả trường hợp có số 0 hoặc không)
                    if (phone.number.length < 9 || phone.number.length > 11) return 'SĐT phải từ 9-11 số';
                    return null; // Hợp lệ
                  },

                  onChanged: (phone) => _completePhoneNumber = phone.completeNumber,
                  languageCode: 'vi',
                ),
                // ---------------------

                const SizedBox(height: 10),

                TextFormField(
                  controller: _recoveryEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Khôi phục',
                    helperText: 'Dùng để lấy lại mật khẩu',
                    prefixIcon: Icon(Icons.mark_email_unread),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THAY ĐỔI'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}