import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_model.dart';

class ServerService {
  static const String serversUrl = 'https://raw.githubusercontent.com/alaarafeek5522-ai/bothost-servers/master/servers.json';

  static Future<List<ServerModel>> fetchServers() async {
    final response = await http.get(Uri.parse(serversUrl)).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List servers = data['servers'] ?? [];
      return servers.map((s) => ServerModel.fromJson(s)).toList();
    }
    throw Exception('فشل في جلب السيرفرات: ${response.statusCode}');
  }

  static ServerModel getLeastLoadedServer(List<ServerModel> servers) {
    if (servers.isEmpty) throw Exception('مفيش سيرفرات متاحة');
    return servers.reduce((a, b) => a.botCount < b.botCount ? a : b);
  }
}
