class BotModel {
  final String name;
  final String serverName;
  final String status;
  final DateTime createdAt;
  final String? pid;

  BotModel({
    required this.name,
    required this.serverName,
    required this.status,
    required this.createdAt,
    this.pid,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'serverName': serverName,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'pid': pid,
    };
  }

  factory BotModel.fromJson(Map<String, dynamic> json) {
    return BotModel(
      name: json['name'] ?? '',
      serverName: json['serverName'] ?? '',
      status: json['status'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      pid: json['pid'],
    );
  }

  BotModel copyWith({
    String? name,
    String? serverName,
    String? status,
    DateTime? createdAt,
    String? pid,
  }) {
    return BotModel(
      name: name ?? this.name,
      serverName: serverName ?? this.serverName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      pid: pid ?? this.pid,
    );
  }
}
