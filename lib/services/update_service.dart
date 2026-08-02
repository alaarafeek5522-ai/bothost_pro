import 'dart:convert';
import 'package:http/http.dart' as http';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  // غير الرابط ده بـ raw URL بتاع update.json
  static const String _updateUrl = 'https://raw.githubusercontent.com/alaarafeek5522-ai/bothost-servers/main/update.json';
  static const String _lastCheckKey = 'last_update_check';

  static Future<Map<String, dynamic>?> checkUpdate() async {
    try {
      final response = await http.get(Uri.parse(_updateUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      print('فشل جلب التحديثات: $e');
      return null;
    }
  }

  static Future<bool> shouldShowUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // نتحقق مرة كل ساعة
    if (now - lastCheck < 3600000) return false;
    
    await prefs.setInt(_lastCheckKey, now);
    return true;
  }
}
