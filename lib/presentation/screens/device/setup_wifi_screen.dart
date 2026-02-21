import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../config/ble_constants.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_constants.dart'; // [QUAN TRỌNG] Để lấy URL/Key

class SetupWifiScreen extends StatefulWidget {
  const SetupWifiScreen({super.key});

  @override
  State<SetupWifiScreen> createState() => _SetupWifiScreenState();
}

class _SetupWifiScreenState extends State<SetupWifiScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _statusMessage;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;

  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _checkPermissionsAndScan() async {
    if (Platform.isAndroid) {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    }
    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    if (mounted) setState(() { _isScanning = true; _scanResults.clear(); _statusMessage = "Đang quét thiết bị..."; });

    try {
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results.where((r) => r.device.platformName.isNotEmpty && r.rssi > -90).toList();
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      await Future.delayed(const Duration(seconds: 6));
      if (mounted) setState(() { _isScanning = false; _statusMessage = _scanResults.isEmpty ? "Không tìm thấy mạch nào." : null; });
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    setState(() { _isConnecting = true; _statusMessage = "Đang kết nối..."; });

    try {
      await FlutterBluePlus.stopScan();
      await device.connect(autoConnect: false).timeout(const Duration(seconds: 15));
      _connectedDevice = device;

      if (Platform.isAndroid) {
        setState(() => _statusMessage = "Tối ưu băng thông...");
        try { await device.requestMtu(512); await Future.delayed(const Duration(milliseconds: 300)); } catch (_) {}
      }

      setState(() => _statusMessage = "Đang tìm Service...");
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? foundChar;

      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains("9ab1")) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains("1632")) {
              foundChar = char;
              break;
            }
          }
        }
        if (foundChar != null) break;
      }

      if (foundChar != null) {
        setState(() => _writeChar = foundChar);
        if (mounted) { setState(() => _statusMessage = null); _showWifiDialog(); }
      } else {
        throw "Không tìm thấy Service phù hợp!";
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      await device.disconnect();
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _showWifiDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Cấu hình Thiết Bị"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Nhập WiFi để thiết bị kết nối.", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(controller: _ssidController, decoration: const InputDecoration(labelText: 'Tên Wifi (SSID)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: 'Mật khẩu', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _disconnectAndExit(); }, child: const Text("Hủy")),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _sendConfig(); }, child: const Text("Gửi Cấu Hình"))
        ],
      ),
    );
  }

  Future<void> _sendConfig() async {
    if (_writeChar == null) return;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));

    // [QUAN TRỌNG] Gửi cả WiFi + Supabase URL/Key
    Map<String, String> config = {
      "ssid": _ssidController.text.trim(),
      "password": _passController.text.trim(),
      "url": AppConstants.supabaseUrl,
      "key": AppConstants.supabaseAnonKey
    };
    
    String jsonString = jsonEncode(config);
    debugPrint("📤 Payload: $jsonString");

    try {
      await _writeChar!.write(utf8.encode(jsonString));
      _handleSuccess();
    } catch (e) {
      // Bắt lỗi ngắt kết nối giả
      String err = e.toString();
      if (err.contains("133") || err.contains("device disconnected") || err.contains("GATT_ERROR")) {
        _handleSuccess();
      } else {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      }
    }
  }

  void _handleSuccess() {
    if (mounted) Navigator.pop(context);
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("✅ Cấu hình hoàn tất!"),
          content: const Text("Mạch đã nhận thông tin WiFi và Server.\nThiết bị đang khởi động lại..."),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); _disconnectAndExit(); }, child: const Text("OK"))
          ],
        )
      );
    }
  }

  Future<void> _disconnectAndExit() async {
    await _connectedDevice?.disconnect();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Thêm Thiết Bị Mới")),
      body: Column(
        children: [
          if (_isScanning || _isConnecting) const LinearProgressIndicator(),
          if (_statusMessage != null) Padding(padding: const EdgeInsets.all(8.0), child: Text(_statusMessage!, style: const TextStyle(color: Colors.blue))),
          Expanded(
            child: _scanResults.isEmpty 
              ? Center(child: Text(_isScanning ? "Đang quét..." : "Không tìm thấy thiết bị.\nHãy nhấn nút Reset trên mạch.", textAlign: TextAlign.center)) 
              : ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (ctx, i) {
                    final r = _scanResults[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, size: 30, color: Colors.blue),
                        title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : "Unknown"),
                        subtitle: Text(r.device.remoteId.toString()),
                        trailing: ElevatedButton(onPressed: _isConnecting ? null : () => _connectToDevice(r.device), child: const Text("Kết nối")),
                      ),
                    );
                  },
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: (_isScanning || _isConnecting) ? null : _startScan, icon: const Icon(Icons.refresh), label: const Text("QUÉT LẠI"))),
          ),
        ],
      ),
    );
  }
}