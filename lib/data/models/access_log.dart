class AccessLog {
  final int id;
  final String deviceId;
  final String? imageUrl;
  final String description;
  final DateTime createdAt;

  AccessLog({
    required this.id,
    required this.deviceId,
    this.imageUrl,
    required this.description,
    required this.createdAt,
  });

  factory AccessLog.fromJson(Map<String, dynamic> json) {
    return AccessLog(
      id: json['id'],
      deviceId: json['device_id'],
      imageUrl: json['image_url'], 
      description: json['description'] ?? 'Hành động không xác định',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}