import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _authService = AuthService();
  final _oldPassController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  
  // Trạng thái ẩn/hiện cho 3 ô
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorText; 

  Future<void> _handleChangePassword() async {
    final oldPass = _oldPassController.text.trim();
    final newPass = _passController.text;
    final confirmPass = _confirmPassController.text;

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
       setState(() => _errorText = "Vui lòng nhập đầy đủ các trường");
       return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorText = "Mật khẩu mới không khớp");
      return;
    }
    final weakReason = _authService.validatePassword(newPass);
    if (weakReason != null) {
      setState(() => _errorText = weakReason);
      return;
    }

    setState(() { _isLoading = true; _errorText = null; });

    try {
      final email = _authService.currentUser?.email;
      if (email != null) {
        final isOldCorrect = await _authService.verifyOldPassword(email, oldPass);
        if (!isOldCorrect) throw const AuthException("Mật khẩu hiện tại không đúng");
      }
      await _authService.updatePassword(newPass);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Colors.green));
        Navigator.pop(context); 
      }
    } on AuthException catch (e) {
      setState(() => _errorText = e.message); 
    } catch (e) {
      setState(() => _errorText = "Lỗi: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi Mật Khẩu')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _oldPassController,
              obscureText: _obscureOld,
              decoration: InputDecoration(
                labelText: 'Mật khẩu hiện tại',
                prefixIcon: const Icon(Icons.vpn_key),
                suffixIcon: IconButton(
                  icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureOld = !_obscureOld),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            const Text(
              "Mật khẩu mới cần: 8 ký tự, Hoa, Thường, Số, Ký tự đặc biệt.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            
            TextField(
              controller: _passController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'Mật khẩu mới',
                errorText: _errorText,
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _confirmPassController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Nhập lại mật khẩu mới',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleChangePassword,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THAY ĐỔI'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}