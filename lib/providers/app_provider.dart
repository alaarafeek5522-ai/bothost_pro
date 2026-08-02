import 'package:flutter/material.dart';
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

  void setServers(List<ServerModel> servers) {
    _servers = servers;
    notifyListeners();
  }

  void setBot(BotModel bot) {
    _myBot = bot;
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
