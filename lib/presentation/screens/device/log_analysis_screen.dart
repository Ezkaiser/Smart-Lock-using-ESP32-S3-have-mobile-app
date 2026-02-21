import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../data/models/access_log.dart';
import '../../../data/services/device_service.dart';

class LogAnalysisScreen extends StatefulWidget {
  final String deviceId;
  const LogAnalysisScreen({super.key, required this.deviceId});

  @override
  State<LogAnalysisScreen> createState() => _LogAnalysisScreenState();
}

class _LogAnalysisScreenState extends State<LogAnalysisScreen> {
  final _deviceService = DeviceService();
  bool _isLoading = true;

  // Dữ liệu
  Map<String, int> _dailyData = {};
  Map<String, int> _methodData = {'Face': 0, 'App': 0};
  List<int> _hourlyData = List.filled(24, 0);

  double _maxY_Daily = 5;
  int _totalUnlocks = 0;

  @override
  void initState() {
    super.initState();
    _loadAndProcessData();
  }

  Future<void> _loadAndProcessData() async {
    // Lấy 200 log gần nhất
    final rawLogs = await _deviceService.getAccessLogs(widget.deviceId, 0, pageSize: 200);
    final logs = rawLogs.map((json) => AccessLog.fromJson(json)).toList();

    // 1. Dữ liệu tuần
    Map<String, int> tempDaily = {};
    for (int i = 6; i >= 0; i--) {
      DateTime d = DateTime.now().subtract(Duration(days: i));
      String key = DateFormat('dd/MM').format(d);
      tempDaily[key] = 0;
    }

    // 2. Reset counter
    int faceCount = 0;
    int appCount = 0;
    List<int> tempHourly = List.filled(24, 0);

    for (var log in logs) {
      DateTime time = log.createdAt.toLocal();
      
      // Ngày
      String dateKey = DateFormat('dd/MM').format(time);
      if (tempDaily.containsKey(dateKey)) {
        tempDaily[dateKey] = (tempDaily[dateKey] ?? 0) + 1;
      }

      // Phương thức
      if (log.description.toLowerCase().contains('face')) {
        faceCount++;
      } else {
        appCount++;
      }

      // Giờ
      tempHourly[time.hour]++;
    }

    // Tính Max Y cho Line Chart
    int maxVal = 0;
    tempDaily.forEach((k, v) { if(v > maxVal) maxVal = v; });
    
    // Logic làm tròn Max Y lên số chẵn đẹp (chia hết cho 5) để biểu đồ thoáng
    if (maxVal < 5) {
      _maxY_Daily = 5;
    } else {
      // Ví dụ max là 13 -> làm tròn lên 15. Max là 21 -> làm tròn lên 25
      _maxY_Daily = ((maxVal / 5).ceil() * 5).toDouble();
    }

    if (mounted) {
      setState(() {
        _dailyData = tempDaily;
        _methodData = {'Face': faceCount, 'App': appCount};
        _hourlyData = tempHourly;
        _totalUnlocks = logs.length;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text("Phân tích hoạt động")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 24),

                const Text("📅 Xu hướng tuần qua", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildCard(child: _buildLineChart()),
                
                const SizedBox(height: 24),

                const Text("⏰ Giờ cao điểm", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildCard(child: _buildBarChartHourly()), 
                
                const SizedBox(height: 24),

                const Text("🔐 Phương thức mở khóa", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildCard(child: _buildPieChart()),
                const SizedBox(height: 30),
              ],
            ),
          ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20), // Padding rộng hơn chút cho thoáng
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: child,
    );
  }

  Widget _buildSummaryCard() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.blue.shade500]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Tổng lượt mở", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 5),
                Text("$_totalUnlocks", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text("7 ngày qua", style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Phổ biến nhất", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 5),
                Text(
                  _methodData['Face']! >= _methodData['App']! ? "Khuôn mặt" : "App Mobile", 
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 20, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 5),
                Text(
                  _methodData['Face']! >= _methodData['App']! ? "Nhanh & Tiện lợi" : "Điều khiển từ xa",
                  style: const TextStyle(color: Colors.grey, fontSize: 11)
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- CẢI TIẾN LINE CHART ---
  Widget _buildLineChart() {
    // Tính khoảng chia (Interval) để trục Y không bị dày đặc
    // Ví dụ Max=20 -> Interval=5 (0, 5, 10, 15, 20)
    // Ví dụ Max=5 -> Interval=1 (0, 1, 2, 3, 4, 5)
    double interval = _maxY_Daily > 10 ? (_maxY_Daily / 5).ceilToDouble() : 1;

    return AspectRatio(
      aspectRatio: 1.5,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: _maxY_Daily,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            // Lưới ngang nét đứt, mờ
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade100, strokeWidth: 1, dashArray: [5, 5]),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            
            // Trục X (Ngày)
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 24, 
              interval: 1, // Hiển thị tất cả các ngày
              getTitlesWidget: (v, m) {
                int idx = v.toInt();
                if (idx >= 0 && idx < _dailyData.length) {
                  // Chỉ hiện ngày/tháng (ví dụ 13/12) với font nhỏ
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(_dailyData.keys.elementAt(idx), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                  );
                }
                return const SizedBox();
              }
            )),

            // Trục Y (Số lượng) - ĐÃ CẢI TIẾN
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 30, // Khoảng cách lề trái
              interval: interval, // [QUAN TRỌNG] Chia khoảng thông minh
              getTitlesWidget: (v, m) {
                if (v == 0) return const SizedBox(); // Ẩn số 0 cho thoáng
                return Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: Colors.grey));
              }
            )),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: _dailyData.entries.toList().asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value.toDouble())).toList(),
              isCurved: true,
              color: Colors.blue,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.15)), // Đổ bóng đậm hơn chút
            ),
          ],
        ),
      ),
    );
  }

  // --- CẢI TIẾN BAR CHART (GIỜ CAO ĐIỂM) ---
  Widget _buildBarChartHourly() {
    int maxHourVal = 0;
    for(var v in _hourlyData) if(v > maxHourVal) maxHourVal = v;
    double maxY = (maxHourVal < 5) ? 5 : (maxHourVal + 1).toDouble();

    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: List.generate(24, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: _hourlyData[index].toDouble(),
                  // Cột nào có dữ liệu thì màu cam, không thì màu xám nhạt
                  color: _hourlyData[index] > 0 ? Colors.orangeAccent : Colors.grey.shade100,
                  width: 6, // Cột mảnh lại cho đỡ chật
                  borderRadius: BorderRadius.circular(4),
                )
              ]
            );
          }),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Ẩn luôn trục trái cho thoáng
            
            // Trục X (Giờ) - ĐÃ CẢI TIẾN
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 24, 
              getTitlesWidget: (v, m) { 
                int hour = v.toInt();
                // [QUAN TRỌNG] Chỉ hiện các mốc giờ chính: 0h, 6h, 12h, 18h
                // Hoặc hiện những giờ có dữ liệu (tùy chọn), ở đây ta chọn mốc cố định cho đẹp
                if (hour == 0 || hour == 6 || hour == 12 || hour == 18 || hour == 23) {
                   return Padding(
                     padding: const EdgeInsets.only(top: 8.0),
                     child: Text("${hour}h", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                   );
                }
                return const SizedBox();
              }
            )),
          ),
          gridData: FlGridData(show: false), // Ẩn lưới
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  // Pie Chart giữ nguyên vì đã ổn
  Widget _buildPieChart() {
    final face = _methodData['Face']!;
    final app = _methodData['App']!;
    final total = face + app;
    
    if (total == 0) return const SizedBox(height: 100, child: Center(child: Text("Chưa có dữ liệu", style: TextStyle(color: Colors.grey))));

    return SizedBox(
      height: 150,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 4, // Khoảng cách giữa các miếng
                centerSpaceRadius: 30,
                sections: [
                  PieChartSectionData(value: face.toDouble(), color: Colors.purpleAccent, radius: 45, showTitle: false),
                  PieChartSectionData(value: app.toDouble(), color: Colors.blueAccent, radius: 45, showTitle: false),
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegend(Colors.purpleAccent, "Face ID", face, total),
              const SizedBox(height: 12),
              _buildLegend(Colors.blueAccent, "Remote App", app, total),
            ],
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text, int count, int total) {
    int percent = total == 0 ? 0 : ((count / total) * 100).round();
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text("$count lượt ($percent%)", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}