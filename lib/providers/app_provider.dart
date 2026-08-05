import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bot_model.dart';
import '../models/server_model.dart';

class AppProvider extends ChangeNotifier {
  List<ServerModel> _servers = [];
  List<BotModel> _myBots = [];
  bool _isLoading = false;
  String? _error;
  String _logs = '';
  String? _userEmail;
  ServerModel? _selectedServer;
  String? _savedBotFileName;
  String? _savedReqFileName;

  List<ServerModel> get servers => _servers;
  List<BotModel> get myBots => _myBots;
  BotModel? get myBot => _myBots.isNotEmpty ? _myBots.last : null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get logs => _logs;
  String? get userEmail => _userEmail;
  bool get hasBot => _myBots.isNotEmpty;
  ServerModel? get selectedServer => _selectedServer;
  String? get savedBotFileName => _savedBotFileName;
  String? get savedReqFileName => _savedReqFileName;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadUserData();
    await _loadSavedFileNames();
    await _loadSavedBots(); // ✅ أول حاجة نحمل البوتات
  }

  Future<void> _loadSavedBots() async {
    final prefs = await SharedPreferences.getInstance();
    _myBots = []; // نبدأ بفاضي

    try {
      // ✅ نحاول الجديد
      final botsJson = prefs.getString('saved_bots');
      if (botsJson != null && botsJson.isNotEmpty && botsJson != '[]') {
        final List<dynamic> data = jsonDecode(botsJson);
        _myBots = data.map((b) => BotModel.fromJson(b)).toList();
        print('✅ Loaded ${_myBots.length} bots');
      } else {
        // ✅ Fallback للقديم
        final oldBot = prefs.getString('saved_bot');
        if (oldBot != null && oldBot.isNotEmpty) {
          final b = jsonDecode(oldBot);
          _myBots = [BotModel(
            name: b['name'],
            serverName: b['serverName'],
            status: b['status'],
            createdAt: DateTime.parse(b['createdAt']),
          )];
          // نحول للجديد
          await _saveBots();
          await prefs.remove('saved_bot');
        }
      }
    } catch (e) {
      print('❌ Error loading bots: $e');
      _myBots = [];
    }

    notifyListeners();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('user_email');
  }

  Future<void> _loadSavedFileNames() async {
    final prefs = await SharedPreferences.getInstance();
    _savedBotFileName = prefs.getString('saved_bot_file_name');
    _savedReqFileName = prefs.getString('saved_req_file_name');
  }

  Future<void> loadSelectedServer() async {
    if (_servers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('selected_server');
    if (name != null) {
      try {
        _selectedServer = _servers.firstWhere((s) => s.name == name);
      } catch (_) {
        _selectedServer = _servers.first;
      }
    } else {
      _selectedServer = _servers.first;
    }
    notifyListeners();
  }

  Future<void> _saveBots() async {
    final prefs = await SharedPreferences.getInstance();
    if (_myBots.isEmpty) {
      await prefs.remove('saved_bots');
      print('🗑️ Cleared saved_bots');
      return;
    }

    try {
      final data = _myBots.map((b) => b.toJson()).toList();
      final jsonStr = jsonEncode(data);
      await prefs.setString('saved_bots', jsonStr);
      print('💾 Saved ${_myBots.length} bots: $jsonStr');
    } catch (e) {
      print('❌ Error saving bots: $e');
    }
  }

  Future<void> saveFileNames({String? botFileName, String? reqFileName}) async {
    final prefs = await SharedPreferences.getInstance();
    if (botFileName != null) {
      _savedBotFileName = botFileName;
      await prefs.setString('saved_bot_file_name', botFileName);
    }
    if (reqFileName != null) {
      _savedReqFileName = reqFileName;
      await prefs.setString('saved_req_file_name', reqFileName);
    }
    notifyListeners();
  }

  Future<void> clearFileNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_bot_file_name');
    await prefs.remove('saved_req_file_name');
    _savedBotFileName = null;
    _savedReqFileName = null;
    notifyListeners();
  }

  Future<void> saveUserEmail(String email) async {
    _userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);
    notifyListeners();
  }

  Future<void> setSelectedServer(ServerModel? server) async {
    _selectedServer = server;
    final prefs = await SharedPreferences.getInstance();
    if (server != null) {
      await prefs.setString('selected_server', server.name);
    } else {
      await prefs.remove('selected_server');
    }
    notifyListeners();
  }

  Future<void> clearSavedBots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_bots');
    await prefs.remove('saved_bot');
    _myBots = [];
    notifyListeners();
  }

  Future<void> removeBot(String botName) async {
    _myBots.removeWhere((b) => b.name == botName);
    await _saveBots();
    notifyListeners();
  }

  void setServers(List<ServerModel> servers) {
    _servers = servers;
    if (_selectedServer == null && servers.isNotEmpty) {
      _selectedServer = servers.first;
    }
    notifyListeners();
  }

  void addBot(BotModel bot) {
    _myBots.add(bot);
    _saveBots(); // ✅ حفظ فوري
    notifyListeners();
  }

  void updateBotStatus(String botName, String status) {
    final index = _myBots.indexWhere((b) => b.name == botName);
    if (index == -1) return;
    _myBots[index] = BotModel(
      name: _myBots[index].name,
      serverName: _myBots[index].serverName,
      status: status,
      createdAt: _myBots[index].createdAt,
    );
    _saveBots(); // ✅ حفظ فوري
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
