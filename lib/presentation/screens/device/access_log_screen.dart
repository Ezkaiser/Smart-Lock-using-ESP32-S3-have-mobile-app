import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/models/access_log.dart';
import '../../../data/services/device_service.dart';
import 'log_analysis_screen.dart'; 

class AccessLogScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  const AccessLogScreen({super.key, required this.deviceId, required this.deviceName});

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  final _deviceService = DeviceService();
  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFmt = DateFormat('HH:mm');
  final DateFormat _dateFmt = DateFormat('dd/MM');

  // FIX: Thêm 'final' vì danh sách không bị gán lại, chỉ thay đổi nội dung bên trong
  final List<AccessLog> _logs = [];
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadLogs(isRefresh: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        _loadLogs(isRefresh: false);
      }
    });
  }

  Future<void> _loadLogs({bool isRefresh = false}) async {
    if (_isLoadingMore || (!_hasMoreData && !isRefresh)) {
      return;
    }
    
    if (isRefresh) {
      setState(() { 
        _isLoadingInitial = true; 
        _currentPage = 0; 
        _hasMoreData = true; 
        _logs.clear(); 
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final rawLogs = await _deviceService.getAccessLogs(widget.deviceId, _currentPage, pageSize: _pageSize);
      final newLogs = rawLogs.map((json) => AccessLog.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          _logs.addAll(newLogs);
          _currentPage++;
          if (newLogs.length < _pageSize) {
            _hasMoreData = false;
          }
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { 
          _isLoadingInitial = false; 
          _isLoadingMore = false; 
        });
      }
    }
  }

  // FIX: Đổi FutureBuilder sang <String?> để khớp với DeviceService
  void _showFullImage(String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<String?>(
        future: _deviceService.createSignedImageUrl(imagePath),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Dialog(
              child: SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
            );
          }

          if (snap.hasData && snap.data != null && snap.data!.isNotEmpty) {
            return Dialog(
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: snap.data!,
                placeholder: (_, __) => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                errorWidget: (_, __, ___) => const SizedBox(height: 100, child: Center(child: Icon(Icons.broken_image, size: 50))),
              ),
            );
          }

          return const Dialog(
            child: SizedBox(height: 100, child: Center(child: Text("Không thể tải ảnh"))),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lịch sử: ${widget.deviceName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Thống kê",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LogAnalysisScreen(deviceId: widget.deviceId)),
              );
            },
          ),
        ],
      ),
      body: _isLoadingInitial
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadLogs(isRefresh: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _logs.length + 1,
                itemBuilder: (context, index) {
                  if (index == _logs.length) {
                    return _isLoadingMore 
                        ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())) 
                        : const SizedBox(height: 50);
                  }
                  
                  final log = _logs[index];
                  final hasImage = log.imageUrl != null;

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        SizedBox(
                          width: 50, 
                          child: Column(children: [
                            Text(_timeFmt.format(log.createdAt.toLocal()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(_dateFmt.format(log.createdAt.toLocal()), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ]),
                        ),
                        Column(children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4), 
                            width: 12, 
                            height: 12, 
                            decoration: BoxDecoration(
                              shape: BoxShape.circle, 
                              color: hasImage ? Colors.purple : Colors.blue, 
                              border: Border.all(color: Colors.white, width: 2), 
                              // FIX: Sử dụng withValues theo chuẩn Flutter mới
                              boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.3), blurRadius: 4)]
                            ),
                          ),
                          Expanded(child: Container(width: 2, color: Colors.grey.shade200)),
                        ]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white, 
                              borderRadius: BorderRadius.circular(12), 
                              border: Border.all(color: Colors.grey.shade100), 
                              boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 5)]
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, 
                              children: [
                                Text(log.description, style: const TextStyle(fontSize: 15)),
                                if (hasImage) ...[
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () => _showFullImage(log.imageUrl!),
                                    child: Container(
                                      padding: const EdgeInsets.all(8), 
                                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), 
                                      child: const Row(children: [Icon(Icons.image, size: 16), SizedBox(width: 5), Text("Xem ảnh chụp")]),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}