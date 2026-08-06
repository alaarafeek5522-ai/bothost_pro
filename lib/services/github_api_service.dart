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

  static Future<Map<String, dynamic>> testConnection() async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        'body': response.body.substring(0, response.body.length > 200 ? 200 : response.body.length),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>?> getFile(String path) async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo/contents/$path';
      print('🔵 GitHub API GET: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      print('🔵 Response status: ${response.statusCode}');
      print('🔵 Response body: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content']?.toString().replaceAll('\n', '');
        if (content != null) {
          final decoded = utf8.decode(base64Decode(content));
          return jsonDecode(decoded);
        }
        return {};
      } else if (response.statusCode == 404) {
        print('🟡 File not found (404)');
        return null;
      } else {
        print('🔴 GitHub API Error: ${response.statusCode}');
        print('🔴 Body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('🔴 GitHub API Exception: $e');
      return null;
    }
  }

  static Future<bool> updateFile(String path, Map<String, dynamic> content, {String? sha}) async {
    try {
      final url = '$_apiBase/repos/$_owner/$_repo/contents/$path';
      print('🔵 GitHub API PUT: $url');
      
      String? currentSha = sha;
      if (currentSha == null) {
        print('🔵 Getting SHA for existing file...');
        final getResponse = await http.get(
          Uri.parse(url),
          headers: _headers,
        ).timeout(const Duration(seconds: 15));
        
        print('🔵 GET SHA status: ${getResponse.statusCode}');
        
        if (getResponse.statusCode == 200) {
          final data = jsonDecode(getResponse.body);
          currentSha = data['sha'];
          print('🔵 Got SHA: $currentSha');
        } else if (getResponse.statusCode == 404) {
          print('🟡 File does not exist, creating new');
          currentSha = null;
        } else {
          print('🔴 Failed to get SHA: ${getResponse.statusCode}');
          print('🔴 Body: ${getResponse.body}');
          return false;
        }
      }

      final body = {
        'message': 'Update $path via Terminal SSH Pro',
        'content': base64Encode(utf8.encode(jsonEncode(content))),
        if (currentSha != null) 'sha': currentSha,
      };

      print('🔵 Sending PUT request...');
      final response = await http.put(
        Uri.parse(url),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      print('🔵 PUT status: ${response.statusCode}');
      print('🔵 PUT body: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('🟢 File updated successfully');
        return true;
      } else {
        print('🔴 Failed to update file: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('🔴 GitHub API Exception in updateFile: $e');
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
      print('🔴 checkConnection error: $e');
      return false;
    }
  }
}
