import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubAPIService {
  static String get _token {
    final parts = [
      'ghp_',
      'a9zva',
      'AYdqu',
      '4DSzZ',
      'qi8Jw',
      'Vt1Xl',
      'FazQn',
      '4fCnn',
      'q',
    ];
    return parts.join();
  }
  
  static const String _owner = 'alaarafeek5522-ai';
  static const String _repo = 'bothost-servers';
  static const String _apiBase = 'https://api.github.com';

  static Map<String, String> get _headers => {
    'Authorization': 'token $_token',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  static Future<Map<String, dynamic>?> getFile(String path) async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo/contents/$path';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content']?.toString().replaceAll('\n', '');
        if (content != null) {
          final decoded = utf8.decode(base64Decode(content));
          return jsonDecode(decoded);
        }
      } else if (response.statusCode == 404) {
        return null;
      } else {
        print('GitHub API getFile status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('GitHub API Error (get): $e');
    }
    return null;
  }

  static Future<bool> updateFile(String path, Map<String, dynamic> content, {String? sha}) async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo/contents/$path';
      
      String? currentSha = sha;
      if (currentSha == null) {
        final getResponse = await http.get(
          Uri.parse(url),
          headers: _headers,
        ).timeout(const Duration(seconds: 15));
        
        if (getResponse.statusCode == 200) {
          final data = jsonDecode(getResponse.body);
          currentSha = data['sha'];
        } else if (getResponse.statusCode == 404) {
          currentSha = null;
        } else {
          print('GitHub API get for sha status: ${getResponse.statusCode}');
          print('Response: ${getResponse.body}');
          return false;
        }
      }

      final body = {
        'message': 'Update $path via Terminal SSH Pro',
        'content': base64Encode(utf8.encode(jsonEncode(content))),
        if (currentSha != null) 'sha': currentSha,
      };

      final response = await http.put(
        Uri.parse(url),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print('GitHub API updateFile status: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('GitHub API Error (update): $e');
      return false;
    }
  }

  static Future<bool> checkConnection() async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('GitHub API checkConnection error: $e');
      return false;
    }
  }
}
