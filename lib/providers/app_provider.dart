import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_model.dart';

class AppProvider extends ChangeNotifier {
  List<ServerModel> _servers = [];
  bool _isLoading = false;
  String? _error;
  String? _userEmail;
  ServerModel? _selectedServer;
  String _currentPath = '';
  List<String> _terminalOutput = [];
  bool _isTerminalConnected = false;

  List<ServerModel> get servers => _servers;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get userEmail => _userEmail;
  ServerModel? get selectedServer => _selectedServer;
  String get currentPath => _currentPath;
  List<String> get terminalOutput => _terminalOutput;
  bool get isTerminalConnected => _isTerminalConnected;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('user_email');
  }

  Future<void> saveUserEmail(String email) async {
    _userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);
    notifyListeners();
  }

  void setServers(List<ServerModel> servers) {
    _servers = servers;
    if (_selectedServer == null && servers.isNotEmpty) {
      _selectedServer = servers.first;
    }
    notifyListeners();
  }

  void setSelectedServer(ServerModel? server) async {
    _selectedServer = server;
    final prefs = await SharedPreferences.getInstance();
    if (server != null) {
      await prefs.setString('selected_server', server.name);
    } else {
      await prefs.remove('selected_server');
    }
    notifyListeners();
  }

  void setCurrentPath(String path) {
    _currentPath = path;
    notifyListeners();
  }

  void addTerminalOutput(String text) {
    _terminalOutput.add(text);
    notifyListeners();
  }

  void clearTerminalOutput() {
    _terminalOutput.clear();
    notifyListeners();
  }

  void setTerminalConnected(bool connected) {
    _isTerminalConnected = connected;
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
