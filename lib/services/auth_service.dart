import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'github_api_service.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _usersFile = 'users.json';
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

  // ========== جلب المستخدمين من GitHub ==========
  static Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final data = await GitHubAPIService.getFile(_usersFile);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data['users'] ?? []);
  }

  // ========== حفظ المستخدمين على GitHub ==========
  static Future<bool> _saveUsers(List<Map<String, dynamic>> users) async {
    return await GitHubAPIService.updateFile(_usersFile, {'users': users});
  }

  // ========== التحقق من الإيميل ==========
  static Future<bool> emailExists(String email) async {
    final users = await _fetchUsers();
    return users.any((u) => u['email'] == email);
  }

  // ========== التحقق من الجهاز ==========
  static Future<bool> deviceExists(String deviceId) async {
    final users = await _fetchUsers();
    return users.any((u) => u['deviceId'] == deviceId);
  }

  // ========== التحقق إن المستخدم عنده بوت ==========
  static Future<bool> userHasBot(String deviceId) async {
    final users = await _fetchUsers();
    final user = users.firstWhere(
      (u) => u['deviceId'] == deviceId,
      orElse: () => {},
    );
    if (user.isEmpty) return false;
    return user['hasBot'] == true;
  }

  // ========== تسجيل جديد ==========
  static Future<UserModel?> register(String email, String password) async {
    final deviceId = await getDeviceId();

    // التحقق 1: الإيميل مستخدم؟
    if (await emailExists(email)) {
      throw Exception('❌ الإيميل ده مستخدم قبل كده');
    }

    // التحقق 2: الجهاز مسجل؟
    if (await deviceExists(deviceId)) {
      throw Exception('❌ الجهاز ده مسجل قبل كده!\nجهاز واحد = حساب واحد فقط');
    }

    // التحقق 3: صحة الإيميل
    if (!email.contains('@') || !email.contains('.')) {
      throw Exception('❌ الإيميل غير صالح');
    }

    // التحقق 4: قوة الباسورد
    if (password.length < 6) {
      throw Exception('❌ الباسورد لازم 6 أحرف على الأقل');
    }

    final users = await _fetchUsers();
    
    final newUser = {
      'id': deviceId,
      'email': email,
      'password': _hashPassword(password),
      'deviceId': deviceId,
      'hasBot': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    users.add(newUser);

    // حفظ على GitHub
    final saved = await _saveUsers(users);
    if (!saved) {
      throw Exception('❌ فشل حفظ الحساب على السيرفر - جرب تاني');
    }

    final user = UserModel.fromJson(newUser);

    // حفظ محلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setBool(_hasBotKey, false);
    
    return user;
  }

  // ========== تسجيل دخول ==========
  static Future<UserModel?> login(String email, String password) async {
    final users = await _fetchUsers();
    
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

  // ========== تسجيل دخول سريع ==========
  static Future<UserModel?> quickLogin() async {
    final deviceId = await getDeviceId();
    final users = await _fetchUsers();
    
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

  // ========== تحديث حالة البوت ==========
  static Future<bool> updateBotStatus(String deviceId, bool hasBot) async {
    final users = await _fetchUsers();
    
    final index = users.indexWhere((u) => u['deviceId'] == deviceId);
    if (index == -1) return false;

    users[index]['hasBot'] = hasBot;
    
    final saved = await _saveUsers(users);
    
    if (saved) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasBotKey, hasBot);
    }
    
    return saved;
  }

  // ========== جلب المستخدم الحالي ==========
  static Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    return UserModel.fromJson(jsonDecode(userJson));
  }

  // ========== التحقق من البوت ==========
  static Future<bool> currentUserHasBot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasBotKey) ?? false;
  }

  // ========== تعيين حالة البوت محلياً ==========
  static Future<void> setBotStatus(bool hasBot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasBotKey, hasBot);
  }

  // ========== تسجيل خروج ==========
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_hasBotKey);
  }

  // ========== تشفير الباسورد ==========
  static String _hashPassword(String password) {
    return base64Encode(utf8.encode(password));
  }
}
