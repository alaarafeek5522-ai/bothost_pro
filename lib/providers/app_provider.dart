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

  List<ServerModel> get servers => _servers;
  BotModel? get myBot => _myBot;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get logs => _logs;

  AppProvider() {
    _loadSavedBot();
  }

  // تحميل البوت المحفوظ
  Future<void> _loadSavedBot() async {
    final prefs = await SharedPreferences.getInstance();
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
        notifyListeners();
      } catch (e) {
        print('فشل تحميل البوت المحفوظ: $e');
      }
    }
  }

  // حفظ البوت
  Future<void> _saveBot() async {
    if (_myBot == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'name': _myBot!.name,
      'serverName': _myBot!.serverName,
      'status': _myBot!.status,
      'createdAt': _myBot!.createdAt.toIso8601String(),
    };
    await prefs.setString('saved_bot', jsonEncode(data));
  }

  // حذف البوت المحفوظ
  Future<void> clearSavedBot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_bot');
    _myBot = null;
    notifyListeners();
  }

  void setServers(List<ServerModel> servers) {
    _servers = servers;
    notifyListeners();
  }

  void setBot(BotModel bot) {
    _myBot = bot;
    _saveBot(); // حفظ تلقائي
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
}
