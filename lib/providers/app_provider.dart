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
    await _loadSavedBots(); // ✅ نحمل البوتات الأول
    // السيرفرات هتتحمل من HomeScreen
  }

  Future<void> _loadSavedBots() async {
    final prefs = await SharedPreferences.getInstance();
    
    // ✅ نحاول الجديد الأول
    final botsJson = prefs.getString('saved_bots');
    if (botsJson != null && botsJson.isNotEmpty) {
      try {
        final List<dynamic> data = jsonDecode(botsJson);
        _myBots = data.map((b) => BotModel(
          name: b['name'],
          serverName: b['serverName'],
          status: b['status'],
          createdAt: DateTime.parse(b['createdAt']),
        )).toList();
        print('✅ Loaded ${_myBots.length} bots from saved_bots');
      } catch (e) {
        print('❌ Failed to load saved_bots: $e');
        _myBots = [];
      }
    } else {
      // ✅ Fallback للقديم
      final oldBot = prefs.getString('saved_bot');
      if (oldBot != null && oldBot.isNotEmpty) {
        try {
          final b = jsonDecode(oldBot);
          _myBots = [BotModel(
            name: b['name'],
            serverName: b['serverName'],
            status: b['status'],
            createdAt: DateTime.parse(b['createdAt']),
          )];
          print('✅ Loaded 1 bot from old saved_bot');
          // نحول للجديد
          await _saveBots();
          await prefs.remove('saved_bot');
        } catch (e) {
          print('❌ Failed to load old saved_bot: $e');
          _myBots = [];
        }
      } else {
        _myBots = [];
      }
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

  // ✅ نستدعيها من HomeScreen بعد ما السيرفرات تتحمل
  Future<void> loadSelectedServer() async {
    if (_servers.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final selectedServerName = prefs.getString('selected_server');
    
    if (selectedServerName != null) {
      try {
        _selectedServer = _servers.firstWhere(
          (s) => s.name == selectedServerName,
        );
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
      return;
    }
    
    final data = _myBots.map((b) => {
      'name': b.name,
      'serverName': b.serverName,
      'status': b.status,
      'createdAt': b.createdAt.toIso8601String(),
    }).toList();
    await prefs.setString('saved_bots', jsonEncode(data));
    print('💾 Saved ${_myBots.length} bots');
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
    // ✅ نحدد السيرفر المختار بعد ما السيرفرات تيجي
    if (_selectedServer == null && servers.isNotEmpty) {
      _selectedServer = servers.first;
    }
    notifyListeners();
  }

  void addBot(BotModel bot) {
    _myBots.add(bot);
    _saveBots();
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
    _saveBots();
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

  List<BotModel> getBotsOnServer(String serverName) {
    return _myBots.where((b) => b.serverName == serverName).toList();
  }
}
