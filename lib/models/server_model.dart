class ServerModel {
  final int id;
  final String name;
  final String host;
  final int port;
  final String user;
  final String password;
  final int botCount;
  final double? cpuUsage;
  final double? memoryUsage;
  final String? region;

  ServerModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    this.botCount = 0,
    this.cpuUsage,
    this.memoryUsage,
    this.region,
  });

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    return ServerModel(
      id: json['id'],
      name: json['name'],
      host: json['host'],
      port: json['port'],
      user: json['user'],
      password: json['password'],
      botCount: json['botCount'] ?? 0,
      cpuUsage: json['cpuUsage']?.toDouble(),
      memoryUsage: json['memoryUsage']?.toDouble(),
      region: json['region'],
    );
  }

  // حساب score — الأقل = الأفضل
  double get loadScore {
    double score = botCount * 10;
    if (cpuUsage != null) score += cpuUsage!;
    if (memoryUsage != null) score += memoryUsage! / 2;
    return score;
  }

  String get displayName => '$name ${region != null ? '($region)' : ''}';
}
