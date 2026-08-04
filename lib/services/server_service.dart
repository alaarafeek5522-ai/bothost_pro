import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_model.dart';

class ServerService {
  // غير الرابط ده بـ raw URL بتاع servers.json على GitHub
  static const String serversUrl = 'https://raw.githubusercontent.com/alaarafeek5522-ai/bothost-servers/master/servers.json';

  static Future<List<ServerModel>> fetchServers() async {
    final response = await http.get(Uri.parse(serversUrl));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List servers = data['servers'];
      return servers.map((s) => ServerModel.fromJson(s)).toList();
    }
    throw Exception('فشل في جلب السيرفرات');
  }

  static ServerModel getLeastLoadedServer(List<ServerModel> servers) {
    return servers.reduce((a, b) => a.botCount < b.botCount ? a : b);
  }
}
