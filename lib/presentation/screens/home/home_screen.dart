import 'dart:async'; // Cần thiết cho StreamSubscription
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../data/models/device_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/services/bluetooth_service.dart';
import '../auth/login_screen.dart';
import '../settings/profile_screen.dart';
import 'add_device_screen.dart';
import '../device/access_log_screen.dart';
import 'user_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _deviceService = DeviceService();
  final _bluetoothService = BluetoothService();
  List<Map<String, dynamic>> _devicesList = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        throw 'OFFLINE_MODE';
      }

      // Lấy danh sách thiết bị của User
      final data = await Supabase.instance.client
          .from('user_devices')
          .select('*, device:devices(*)')
          .order('created_at');

      if (mounted) {
        setState(() {
          _devicesList = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // FIX: Logic mở khóa đợi xác nhận từ ESP32 thực tế
  void _onUnlockPressed(Device device) async {
    // 1. Hiển thị thông báo đang xử lý (không tự đóng nhanh)
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
            SizedBox(width: 15),
            Text('Đang kết nối tới khóa...'),
          ],
        ),
        duration: Duration(seconds: 15), // Chờ tối đa 15s
      ),
    );

    StreamSubscription? statusSubscription;
    bool isConfirmed = false;

    try {
      // 2. Gửi lệnh OPEN vào database
      await _deviceService.sendUnlockCommand(device.id);

      // 3. Lắng nghe trạng thái Realtime của dòng lệnh vừa gửi
      statusSubscription = _deviceService.watchCommandStatus(device.id).listen((data) {
        if (data.isNotEmpty) {
          final lastCommand = data.first;
          final status = lastCommand['status'];

          // Nếu ESP32 đã nhận lệnh và đổi status thành 'executed'
          if (status == 'executed' && !isConfirmed) {
            isConfirmed = true;
            statusSubscription?.cancel(); // Dừng lắng nghe

            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Khóa đã mở thành công!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      });

      // 4. Cơ chế Timeout phòng trường hợp khóa mất điện/mất WiFi
      Future.delayed(const Duration(seconds: 15), () {
        if (!isConfirmed) {
          statusSubscription?.cancel();
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Khóa không phản hồi. Vui lòng kiểm tra WiFi của khóa.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });

    } catch (e) {
      statusSubscription?.cancel();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showRenameDialog(BuildContext context, Device device, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đổi tên thiết bị"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Tên mới", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              String newName = controller.text.trim();
              if (newName.isEmpty) return;

              setState(() {
                final index = _devicesList.indexWhere((element) => element['device']['id'] == device.id);
                if (index != -1) {
                  _devicesList[index]['nickname'] = newName;
                }
              });

              try {
                await _deviceService.updateDeviceNickname(device.id, newName);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Đã đổi tên!")));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi lưu tên: $e"), backgroundColor: Colors.red));
                _fetchData(); 
              }
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Device device, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xóa thiết bị?"),
        content: Text("Bạn có chắc muốn xóa '$name' không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _devicesList.removeWhere((element) => element['device']['id'] == device.id);
              });

              try {
                await _deviceService.removeDevice(device.id);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🗑️ Đã xóa thiết bị.")));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi xóa: $e"), backgroundColor: Colors.red));
                _fetchData();
              }
            },
            child: const Text("XÓA", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeviceOptions(Device device, String nickname) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Đổi tên thiết bị'),
              onTap: () { Navigator.pop(ctx); _showRenameDialog(context, device, nickname); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Xóa thiết bị', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(ctx); _confirmDelete(context, device, nickname); },
            ),
          ],
        ),
      ),
    );
  }

  void _startScan() async {
    bool hasPerm = await _bluetoothService.checkPermissions();
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần cấp quyền Bluetooth!')));
      return;
    }
    try { await _bluetoothService.startScan(); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi quét: $e"))); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhà của tôi'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async { await AuthService().signOut(); if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
        ],
      ),
      floatingActionButton: _errorMessage == null 
          ? FloatingActionButton(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen())); _fetchData(); }, backgroundColor: Theme.of(context).primaryColor, child: const Icon(Icons.add, color: Colors.white))
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      if (_errorMessage == 'OFFLINE_MODE' || _errorMessage!.contains('SocketException')) {
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
            const Text('Mất kết nối Internet', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: _startScan, icon: const Icon(Icons.bluetooth_searching), label: const Text('QUÉT BLUETOOTH')),
            TextButton(onPressed: _fetchData, child: const Text('Thử lại')),
          ]),
        );
      }
      return Center(child: Text('Lỗi: $_errorMessage'));
    }

    if (_devicesList.isEmpty) return const Center(child: Text('Bạn chưa có thiết bị nào.'));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _devicesList.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final userDevice = _devicesList[index];
        final device = Device.fromJson(userDevice['device']);
        final nickname = userDevice['nickname'] ?? device.name;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: () => _showDeviceOptions(device, nickname),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.lock, color: Colors.blue, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text("ID: ${device.id}", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history, color: Colors.grey), 
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccessLogScreen(deviceId: device.id, deviceName: nickname)))
                    ),
                  ]),
                  
                  const SizedBox(height: 20),
                  
                  // [NÚT 1] MỞ KHÓA TỪ XA
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: () => _onUnlockPressed(device),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text("MỞ KHÓA TỪ XA"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // [NÚT 2] QUẢN LÝ KHUÔN MẶT
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                      },
                      icon: const Icon(Icons.people_alt_rounded),
                      label: const Text("QUẢN LÝ KHUÔN MẶT"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}