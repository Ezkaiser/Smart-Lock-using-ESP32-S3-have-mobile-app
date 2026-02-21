import 'package:flutter/material.dart';
import 'dart:math';
import '../../../data/services/device_service.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _deviceService = DeviceService();
  final _idController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLoading = false;
  int _failedAttempts = 0;
  DateTime? _lockoutTime;

  Future<void> _handleClaim() async {
    if (_lockoutTime != null && DateTime.now().isBefore(_lockoutTime!)) {
      final waitSeconds = _lockoutTime!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vui lòng chờ ${waitSeconds}s'), backgroundColor: Colors.orange));
      return;
    }

    if (_idController.text.isEmpty || _codeController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _deviceService.claimDevice(
        _idController.text.trim(),
        _codeController.text.trim(),
        _nameController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 Thêm thành công!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      _failedAttempts++;
      int waitSeconds = pow(2, _failedAttempts).toInt();
      if (waitSeconds > 30) waitSeconds = 30; 
      _lockoutTime = DateTime.now().add(Duration(seconds: waitSeconds));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e. Tạm khóa ${waitSeconds}s.'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _idController.dispose(); _codeController.dispose(); _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm Thiết Bị Mới')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Thông tin thiết bị", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
            const Text('Nhập thông tin trên tem sản phẩm.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            
            TextField(
              controller: _idController,
              decoration: const InputDecoration(labelText: 'Mã ID (VD: S3_LOCK_01)', prefixIcon: Icon(Icons.qr_code)),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _codeController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mã Xác Nhận (Claim Code)', prefixIcon: Icon(Icons.vpn_key)),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Tên gợi nhớ (VD: Cửa Chính)', prefixIcon: Icon(Icons.edit)),
            ),
            
            if (_lockoutTime != null && DateTime.now().isBefore(_lockoutTime!))
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text("⛔ Đang bị tạm khóa. Vui lòng chờ...", style: TextStyle(color: Colors.red[700], fontStyle: FontStyle.italic)),
              ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleClaim,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('XÁC NHẬN THÊM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}