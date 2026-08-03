class UserModel {
  final String id;
  final String email;
  final String password;
  final String deviceId;
  final bool hasBot;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.password,
    required this.deviceId,
    this.hasBot = false,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      password: json['password'] ?? '',
      deviceId: json['deviceId'] ?? '',
      hasBot: json['hasBot'] ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'password': password,
      'deviceId': deviceId,
      'hasBot': hasBot,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? password,
    String? deviceId,
    bool? hasBot,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      password: password ?? this.password,
      deviceId: deviceId ?? this.deviceId,
      hasBot: hasBot ?? this.hasBot,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
