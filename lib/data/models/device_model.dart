class Device {
  final String id;
  final String name;
  final String status; // 'online' or 'offline'
  final bool isLocked; // true = Close, false = Open
  final DateTime createdAt;
  final String? claimCode;

  Device({
    required this.id,
    required this.name,
    required this.status,
    required this.isLocked,
    required this.createdAt,
    this.claimCode,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Device',
      status: json['status'] ?? 'offline',
      isLocked: json['is_locked'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      claimCode: json['claim_code'],
    );
  }
}