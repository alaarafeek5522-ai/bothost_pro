class ServerModel {
  final int id;
  final String name;
  final String host;
  final int port;
  final String user;
  final String password;
  final int botCount;

  ServerModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.botCount,
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
    );
  }
}
