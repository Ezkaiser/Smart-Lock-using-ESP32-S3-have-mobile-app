import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  // --- 1. LẤY DANH SÁCH TỪ BẢNG 'users' ---
  Stream<List<Map<String, dynamic>>> _getUsersStream() {
    return _supabase
        .from('users') // [KHỚP SCHEMA]
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  // --- 2. THÊM NGƯỜI DÙNG & GỬI LỆNH ---
  Future<void> _addNewUser(String name) async {
    if (name.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // B1: Tạo user mới. Schema của bạn yêu cầu face_id nhưng ta đã bỏ NOT NULL ở bước SQL.
      // Ta chỉ cần insert 'name', DB tự sinh 'id'.
      final data = await _supabase
          .from('users')
          .insert({
            'name': name,
            // 'face_id': 0 // Không cần điền nữa
          })
          .select()
          .single();

      final int newUserId = data['id']; // Lấy ID tự sinh (bigint)

      // B2: Cập nhật lại face_id cho khớp với id (để DB đẹp hơn - tùy chọn)
      await _supabase.from('users').update({'face_id': newUserId}).eq('id', newUserId);

      // B3: Gửi lệnh ENROLL xuống bảng 'device_commands'
      await _supabase.from('device_commands').insert({
        'device_id': 'S3_LOCK_01', // [QUAN TRỌNG] Phải khớp với ID trong bảng devices
        'command': 'ENROLL',
        'status': 'pending',
        'payload': {'user_id': newUserId}, 
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("📸 Đang chờ đăng ký..."),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  "ID Cấp Phát: $newUserId\nHãy nhìn thẳng vào Camera trên khóa!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Đóng"))
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 3. XÓA NGƯỜI DÙNG ---
  Future<void> _deleteUser(int id) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa?"),
        content: const Text("Dữ liệu khuôn mặt của người này sẽ bị xóa."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xóa", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Xóa trong bảng users. Do bạn có constraint fk_user trong access_logs,
      // nếu user này đã có log ra vào, lệnh này có thể lỗi nếu không set Cascade.
      // Tạm thời ta xóa user, Supabase sẽ báo lỗi nếu dính khóa ngoại.
      await _supabase.from('users').delete().eq('id', id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa thành công!')),
        );
      }
    } catch (e) {
      // Xử lý lỗi khóa ngoại (nếu có log rồi thì không xóa được user)
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xóa: $e (Có thể do user này đã có lịch sử ra vào)')),
        );
      }
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Thêm Người Mới"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Tên hiển thị", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addNewUser(nameController.text.trim());
            },
            child: const Text("Đăng Ký"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quản Lý Khuôn Mặt")),
      body: Stack(
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getUsersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Lỗi tải data: ${snapshot.error}"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final users = snapshot.data!;

              if (users.isEmpty) {
                return const Center(child: Text("Danh sách trống.\nBấm + để thêm."));
              }

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, i) {
                  final user = users[i];
                  // Parse ngày tháng an toàn
                  String dateStr = "N/A";
                  if (user['created_at'] != null) {
                    dateStr = DateFormat('dd/MM HH:mm').format(DateTime.parse(user['created_at']).toLocal());
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(user['name'] != null && user['name'].isNotEmpty ? user['name'][0].toUpperCase() : "?"),
                      ),
                      title: Text(user['name'] ?? "Không tên", style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("ID: ${user['id']} • Tạo: $dateStr"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteUser(user['id']),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}