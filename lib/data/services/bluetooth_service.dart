import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble_lib;
import 'package:permission_handler/permission_handler.dart';
import '../../config/ble_constants.dart'; 

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  ble_lib.BluetoothDevice? _connectedDevice;
  ble_lib.BluetoothCharacteristic? _controlChar;

  Stream<List<ble_lib.ScanResult>> get scanResults => ble_lib.FlutterBluePlus.scanResults;
  Stream<ble_lib.BluetoothAdapterState> get adapterState => ble_lib.FlutterBluePlus.adapterState;

  // 1. Quét thiết bị (Cần thiết cho HomeScreen)
  Future<void> startScan() async {
    if (await ble_lib.FlutterBluePlus.isScanningNow) return;
    await ble_lib.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  Future<void> stopScan() async {
    await ble_lib.FlutterBluePlus.stopScan();
  }

  // 2. Kết nối an toàn (Fix lỗi 133)
  Future<void> connectToDevice(ble_lib.BluetoothDevice device) async {
    await stopScan();
    
    try {
      // Cleanup: Luôn ngắt kết nối cũ nếu có để tránh lỗi stack Bluetooth Android
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect().catchError((_){});
      }
      await Future.delayed(const Duration(milliseconds: 500)); 

      await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      _connectedDevice = device;

      if (Platform.isAndroid) {
        await device.requestMtu(512).catchError((e) => print("MTU Error: $e"));
      }

      List<ble_lib.BluetoothService> services = await device.discoverServices();
      bool found = false;

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == BleConstants.serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == BleConstants.characteristicUuid.toLowerCase()) {
              _controlChar = characteristic;
              found = true;
              break; 
            }
          }
        }
        if (found) break;
      }

      if (!found) {
        await device.disconnect();
        throw "Không tìm thấy Service/Characteristic điều khiển!";
      }
    } catch (e) {
      throw "Lỗi kết nối Bluetooth: $e";
    }
  }

  // 3. Gửi lệnh mở khóa qua Bluetooth
  Future<void> sendUnlockCommand() async {
    if (_controlChar == null) throw "Chưa kết nối thiết bị Bluetooth!";
    try {
      await _controlChar!.write(utf8.encode("OPEN"), withoutResponse: false);
      print("✅ BLE: Đã gửi lệnh OPEN.");
    } catch (e) {
      throw "Gửi lệnh BLE thất bại: $e";
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _controlChar = null;
    }
  }

  Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location, 
      ].request();
      return statuses[Permission.bluetoothScan]!.isGranted && statuses[Permission.bluetoothConnect]!.isGranted;
    }
    return true;
  }
}