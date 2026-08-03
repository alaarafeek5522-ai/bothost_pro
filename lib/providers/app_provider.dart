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
  bool _isInitialized = false;

  List<ServerModel> get servers => List.unmodifiable(_servers);
  BotModel? get myBot => _myBot;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get logs => _logs;
  bool get isInitialized => _isInitialized;

  AppProvider() {
    _loadSavedBot();
  }

  Future<void> _loadSavedBot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final botJson = prefs.getString('saved_bot');
      if (botJson != null) {
        final data = jsonDecode(botJson);
        _myBot = BotModel.fromJson(data);
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('فشل تحميل البوت المحفوظ: $e');
      _isInitialized = true;
    }
    notifyListeners();
  }

  Future<void> _saveBot() async {
    if (_myBot == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_bot', jsonEncode(_myBot!.toJson()));
    } catch (e) {
      debugPrint('فشل حفظ البوت: $e');
    }
  }

  Future<void> clearSavedBot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_bot');
      _myBot = null;
      notifyListeners();
    } catch (e) {
      debugPrint('فشل حذف البوت: $e');
    }
  }

  void setServers(List<ServerModel> servers) {
    _servers = List.from(servers);
    notifyListeners();
  }

  void setBot(BotModel bot) {
    _myBot = bot;
    _saveBot();
    notifyListeners();
  }

  void updateBotStatus(String status, {String? pid}) {
    if (_myBot == null) return;
    _myBot = _myBot!.copyWith(status: status, pid: pid);
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

  void addServer(ServerModel server) {
    _servers.add(server);
    notifyListeners();
  }

  void removeServer(int id) {
    _servers.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}
