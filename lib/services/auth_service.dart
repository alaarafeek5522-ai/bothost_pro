import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _usersUrl = 'https://raw.githubusercontent.com/alaarafeek5522-ai/bothost-servers/master/users.json';
  static const String _userKey = 'current_user';
  static const String _deviceIdKey = 'device_id';
  static const String _hasBotKey = 'has_bot';

  // ========== DEVICE ID ==========
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      deviceId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    
    return deviceId;
  }

  static String _generateDeviceId() {
    final random = Random();
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // ========== FETCH USERS FROM GITHUB ==========
  static Future<List<Map<String, dynamic>>> _fetchUsersFromGitHub() async {
    try {
      final response = await http.get(Uri.parse(_usersUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['users'] ?? []);
      }
    } catch (e) {
      print('فشل جلب المستخدمين من GitHub: $e');
    }
    return [];
  }

  // ========== CHECK IF EMAIL EXISTS ==========
  static Future<bool> emailExists(String email) async {
    final users = await _fetchUsersFromGitHub();
    return users.any((u) => u['email'] == email);
  }

  // ========== CHECK IF DEVICE EXISTS ==========
  static Future<bool> deviceExists(String deviceId) async {
    final users = await _fetchUsersFromGitHub();
    return users.any((u) => u['deviceId'] == deviceId);
  }

  // ========== CHECK IF USER HAS BOT ==========
  static Future<bool> userHasBot(String deviceId) async {
    final users = await _fetchUsersFromGitHub();
    final user = users.firstWhere(
      (u) => u['deviceId'] == deviceId,
      orElse: () => {},
    );
    if (user.isEmpty) return false;
    return user['hasBot'] == true;
  }

  // ========== REGISTER ==========
  static Future<UserModel?> register(String email, String password) async {
    final deviceId = await getDeviceId();

    // التحقق 1: الإيميل مستخدم قبل كده؟
    if (await emailExists(email)) {
      throw Exception('❌ الإيميل ده مستخدم قبل كده');
    }

    // التحقق 2: الجهاز مسجل قبل كده؟ (حساب واحد للجهاز)
    if (await deviceExists(deviceId)) {
      throw Exception('❌ الجهاز ده مسجل قبل كده بحساب تاني.\nجهاز واحد = حساب واحد فقط!');
    }

    // التحقق 3: صحة الإيميل
    if (!email.contains('@') || !email.contains('.')) {
      throw Exception('❌ الإيميل غير صالح');
    }

    // التحقق 4: قوة الباسورد
    if (password.length < 6) {
      throw Exception('❌ الباسورد لازم 6 أحرف على الأقل');
    }

    final user = UserModel(
      id: deviceId,
      email: email,
      password: _hashPassword(password),
      deviceId: deviceId,
      hasBot: false,
      createdAt: DateTime.now(),
    );

    // حفظ محلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setBool(_hasBotKey, false);
    
    return user;
  }

  // ========== LOGIN ==========
  static Future<UserModel?> login(String email, String password) async {
    final users = await _fetchUsersFromGitHub();
    
    final userData = users.firstWhere(
      (u) => u['email'] == email,
      orElse: () => throw Exception('❌ الإيميل مش موجود'),
    );

    if (userData['password'] != _hashPassword(password)) {
      throw Exception('❌ كلمة المرور غلط');
    }

    final user = UserModel.fromJson(userData);

    // حفظ محلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setBool(_hasBotKey, user.hasBot);
    
    return user;
  }

  // ========== QUICK LOGIN (BY DEVICE) ==========
  static Future<UserModel?> quickLogin() async {
    final deviceId = await getDeviceId();
    final users = await _fetchUsersFromGitHub();
    
    try {
      final userData = users.firstWhere((u) => u['deviceId'] == deviceId);
      final user = UserModel.fromJson(userData);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      await prefs.setBool(_hasBotKey, user.hasBot);
      
      return user;
    } catch (e) {
      return null;
    }
  }

  // ========== GET CURRENT USER ==========
  static Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    return UserModel.fromJson(jsonDecode(userJson));
  }

  // ========== CHECK IF CURRENT USER HAS BOT ==========
  static Future<bool> currentUserHasBot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasBotKey) ?? false;
  }

  // ========== SET BOT STATUS ==========
  static Future<void> setBotStatus(bool hasBot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasBotKey, hasBot);
  }

  // ========== LOGOUT ==========
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_hasBotKey);
  }

  // ========== PASSWORD HASH ==========
  static String _hashPassword(String password) {
    // بسيط — في الإنتاج استخدم bcrypt
    return base64Encode(utf8.encode(password));
  }
}
