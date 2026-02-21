class UserProfile {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? avatarUrl;
  final String? recoveryEmail;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.avatarUrl,
    this.recoveryEmail,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      avatarUrl: json['avatar_url'],
      recoveryEmail: json['recovery_email'],
    );
  }
}