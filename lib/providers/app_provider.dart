import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bot_model.dart';
import '../models/server_model.dart';

class AppProvider extends ChangeNotifier {
  List<ServerModel> _servers = [];
  BotModel? _myBot;
  bool _isLoading = false;
  String? _error;
  String _logs = '';
  String? _userEmail;
  bool _hasBot = false;
  String? _botServerName;
  String? _botPid;

  // Getters
  List<ServerModel> get servers => _servers;
  BotModel? get myBot => _myBot;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get logs => _logs;
  String? get userEmail => _userEmail;
  bool get hasBot => _hasBot;
  String? get botServerName => _botServerName;
  String? get botPid => _botPid;

  AppProvider() {
    _loadAllData();
  }

  // ========== تحميل كل البيانات ==========
  Future<void> _loadAllData() async {
    await _loadSavedBot();
    await _loadUserData();
  }

  // ========== تحميل بيانات البوت ==========
  Future<void> _loadSavedBot() async {
    final prefs = await SharedPreferences.getInstance();
    
    // البوت المحفوظ
    final botJson = prefs.getString('saved_bot');
    if (botJson != null) {
      try {
        final data = jsonDecode(botJson);
        _myBot = BotModel(
          name: data['name'],
          serverName: data['serverName'],
          status: data['status'],
          createdAt: DateTime.parse(data['createdAt']),
        );
        _botServerName = data['serverName'];
        _botPid = data['pid'];
      } catch (e) {
        print('فشل تحميل البوت: $e');
      }
    }
    
    // حالة البوت
    _hasBot = prefs.getBool('has_bot') ?? false;
    
    notifyListeners();
  }

  // ========== تحميل بيانات المستخدم ==========
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('user_email');
    notifyListeners();
  }

  // ========== حفظ البوت ==========
  Future<void> _saveBot() async {
    if (_myBot == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'name': _myBot!.name,
      'serverName': _myBot!.serverName,
      'status': _myBot!.status,
      'createdAt': _myBot!.createdAt.toIso8601String(),
      'pid': _botPid,
    };
    await prefs.setString('saved_bot', jsonEncode(data));
    await prefs.setBool('has_bot', _hasBot);
  }

  // ========== حفظ بيانات المستخدم ==========
  Future<void> saveUserEmail(String email) async {
    _userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);
    notifyListeners();
  }

  // ========== مسح البوت ==========
  Future<void> clearSavedBot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_bot');
    await prefs.remove('has_bot');
    _myBot = null;
    _hasBot = false;
    _botServerName = null;
    _botPid = null;
    notifyListeners();
  }

  // ========== Setters ==========
  void setServers(List<ServerModel> servers) {
    _servers = servers;
    notifyListeners();
  }

  void setBot(BotModel bot, {String? pid}) {
    _myBot = bot;
    _hasBot = true;
    _botServerName = bot.serverName;
    _botPid = pid;
    _saveBot();
    notifyListeners();
  }

  void updateBotStatus(String status, {String? pid}) {
    if (_myBot == null) return;
    _myBot = BotModel(
      name: _myBot!.name,
      serverName: _myBot!.serverName,
      status: status,
      createdAt: _myBot!.createdAt,
    );
    if (pid != null) _botPid = pid;
    _saveBot();
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void setLogs(String logs) {
    _logs = logs;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ========== تحديث حالة البوت من السيرفر ==========
  Future<void> refreshBotStatus() async {
    if (_myBot == null || _servers.isEmpty) return;
    
    try {
      final server = _servers.firstWhere(
        (s) => s.name == _myBot!.serverName,
        orElse: () => throw Exception('السيرفر مش موجود'),
      );
      
      // هنستخدم SSHService.checkBotStatus
      // لكن عشان نتجنب circular dependency، هنحط المنطق هنا
      // أو نستخدم callback
      
      // ببساطة نحدّث الـ UI إننا بنعمل check
      notifyListeners();
    } catch (e) {
      print('Refresh error: $e');
    }
  }
}
