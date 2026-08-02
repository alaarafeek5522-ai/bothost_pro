class UserModel {
  final String id;
  final String email;
  final String password;
  final String deviceId;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.password,
    required this.deviceId,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      password: json['password'] ?? '',
      deviceId: json['deviceId'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'password': password,
      'deviceId': deviceId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
