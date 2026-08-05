class BotModel {
  final String name;
  final String serverName;
  final String status;
  final DateTime createdAt;

  BotModel({
    required this.name,
    required this.serverName,
    required this.status,
    required this.createdAt,
  });

  // ✅ للتخزين — نحول DateTime لـ int
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'serverName': serverName,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch, // ✅ int
    };
  }

  // ✅ من التخزين
  factory BotModel.fromJson(Map<String, dynamic> json) {
    return BotModel(
      name: json['name'],
      serverName: json['serverName'],
      status: json['status'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']), // ✅ int
    );
  }
}
