import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _usersUrl = 'https://raw.githubusercontent.com/alaarafeek5522-ai/bothost-servers/master/users.json';
  static const String _userKey = 'current_user';
  static const String _deviceIdKey = 'device_id';

  // توليد device_id فريد
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

  // جلب كل المستخدمين من GitHub
  static Future<List<UserModel>> _fetchUsers() async {
    try {
      final response = await http.get(Uri.parse(_usersUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List users = data['users'] ?? [];
        return users.map((u) => UserModel.fromJson(u)).toList();
      }
    } catch (e) {
      print('فشل جلب المستخدمين: $e');
    }
    return [];
  }

  // تسجيل حساب جديد
  static Future<UserModel?> register(String email, String password) async {
    final deviceId = await getDeviceId();
    final users = await _fetchUsers();

    // نتحقق إن الـ email مش مستخدم قبل كده
    if (users.any((u) => u.email == email)) {
      throw Exception('❌ الإيميل ده مستخدم قبل كده');
    }

    // نتحقق إن الـ device_id مش مستخدم قبل كده (حساب واحد للجهاز)
    if (users.any((u) => u.deviceId == deviceId)) {
      throw Exception('❌ الجهاز ده مسجل قبل كده بحساب تاني');
    }

    final user = UserModel(
      id: deviceId,
      email: email,
      password: _hashPassword(password),
      deviceId: deviceId,
      createdAt: DateTime.now(),
    );

    // حفظ محلي مؤقت
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    
    return user;
  }

  // تسجيل دخول
  static Future<UserModel?> login(String email, String password) async {
    final users = await _fetchUsers();
    final user = users.firstWhere(
      (u) => u.email == email,
      orElse: () => throw Exception('❌ الإيميل مش موجود'),
    );

    if (user.password != _hashPassword(password)) {
      throw Exception('❌ كلمة المرور غلط');
    }

    // حفظ محلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    
    return user;
  }

  // تسجيل دخول سريع بالـ device_id
  static Future<UserModel?> quickLogin() async {
    final deviceId = await getDeviceId();
    final users = await _fetchUsers();
    
    try {
      final user = users.firstWhere((u) => u.deviceId == deviceId);
      
      // حفظ محلي
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      
      return user;
    } catch (e) {
      return null;
    }
  }

  // جلب المستخدم الحالي
  static Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    return UserModel.fromJson(jsonDecode(userJson));
  }

  // تسجيل خروج
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  static String _hashPassword(String password) {
    // بسيط — في الإنتاج استخدم bcrypt
    return base64Encode(utf8.encode(password));
  }
}
