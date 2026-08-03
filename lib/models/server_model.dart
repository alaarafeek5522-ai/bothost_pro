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
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      host: json['host'] ?? '',
      port: json['port'] ?? 22,
      user: json['user'] ?? 'root',
      password: json['password'] ?? '',
      botCount: json['botCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'user': user,
      'password': password,
      'botCount': botCount,
    };
  }
}
