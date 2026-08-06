import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ssh_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;

    if (server == null) {
      _showError('❌ مفيش سيرفر متصل');
      return;
    }

    if (_commandHistory.isEmpty || _commandHistory.last != command) {
      _commandHistory.add(command);
    }
    _historyIndex = _commandHistory.length;

    provider.addTerminalOutput('\$ $command\n');
    SSHService.sendCommand(server, command);
    _commandController.clear();
    _focusNode.requestFocus();

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _sendCtrlC() {
    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server != null) {
      SSHService.sendCtrlC(server);
      provider.addTerminalOutput('^C\n');
    }
  }

  void _clearTerminal() {
    context.read<AppProvider>().clearTerminalOutput();
  }

  void _historyUp() {
    if (_commandHistory.isEmpty) return;
    if (_historyIndex > 0) {
      _historyIndex--;
      _commandController.text = _commandHistory[_historyIndex];
      _commandController.selection = TextSelection.collapsed(
        offset: _commandController.text.length,
      );
    }
  }

  void _historyDown() {
    if (_commandHistory.isEmpty) return;
    if (_historyIndex < _commandHistory.length - 1) {
      _historyIndex++;
      _commandController.text = _commandHistory[_historyIndex];
      _commandController.selection = TextSelection.collapsed(
        offset: _commandController.text.length,
      );
    } else {
      _historyIndex = _commandHistory.length;
      _commandController.clear();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE94560)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: AppTheme.terminalBg,
          appBar: AppBar(
            backgroundColor: AppTheme.terminalBg,
            title: Row(
              children: [
                const Icon(Icons.terminal, color: AppTheme.terminalGreen, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Terminal',
                  style: TextStyle(
                    color: AppTheme.terminalGreen,
                    fontFamily: 'monospace',
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: provider.isTerminalConnected
                        ? AppTheme.terminalGreen
                        : AppTheme.terminalRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.clear_all, color: AppTheme.terminalYellow),
                tooltip: 'مسح الشاشة',
                onPressed: _clearTerminal,
              ),
              IconButton(
                icon: const Icon(Icons.stop, color: AppTheme.terminalRed),
                tooltip: 'Ctrl+C (إيقاف)',
                onPressed: _sendCtrlC,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: RawKeyboardListener(
                    focusNode: FocusNode(),
                    onKey: (event) {
                      if (event is RawKeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _historyUp();
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _historyDown();
                        }
                      }
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: provider.terminalOutput.length,
                      itemBuilder: (context, index) {
                        return _buildTerminalLine(provider.terminalOutput[index]);
                      },
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  border: Border(
                    top: BorderSide(color: const Color(0xFF30363D)),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '\$ ',
                      style: TextStyle(
                        color: AppTheme.terminalGreen,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _commandController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'اكتب الأمر هنا...',
                          hintStyle: TextStyle(
                            color: Colors.white30,
                            fontFamily: 'monospace',
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _sendCommand(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppTheme.terminalGreen),
                      onPressed: _sendCommand,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1117),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickCommand('ls -la', 'عرض'),
                      _buildQuickCommand('pwd', 'مسار'),
                      _buildQuickCommand('clear', 'مسح'),
                      _buildQuickCommand('python3 ', 'بايثون'),
                      _buildQuickCommand('pip3 install ', 'pip'),
                      _buildQuickCommand('git clone ', 'git'),
                      _buildQuickCommand('nano ', 'nano'),
                      _buildQuickCommand('htop', 'htop'),
                      _buildQuickCommand('df -h', 'مساحة'),
                      _buildQuickCommand('ps aux', 'processes'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTerminalLine(String text) {
    Color textColor = Colors.white;
    FontWeight fontWeight = FontWeight.normal;

    if (text.startsWith('\$')) {
      textColor = AppTheme.terminalGreen;
      fontWeight = FontWeight.bold;
    } else if (text.startsWith('❌') ||
        text.contains('Error') ||
        text.contains('error') ||
        text.contains('FAILED') ||
        text.contains('failed')) {
      textColor = AppTheme.terminalRed;
    } else if (text.startsWith('✅') ||
        text.contains('OK') ||
        text.contains('success') ||
        text.contains('Done')) {
      textColor = AppTheme.terminalGreen;
    } else if (text.startsWith('⚠️') ||
        text.contains('Warning') ||
        text.contains('warning')) {
      textColor = AppTheme.terminalYellow;
    } else if (text.contains('http') || text.contains('https')) {
      textColor = AppTheme.terminalBlue;
    } else if (text.startsWith('drwx') || text.startsWith('-rw')) {
      textColor = const Color(0xFF79C0FF);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        text,
        style: TextStyle(
          color: textColor,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  Widget _buildQuickCommand(String command, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        backgroundColor: const Color(0xFF21262D),
        side: const BorderSide(color: Color(0xFF30363D)),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        onPressed: () {
          _commandController.text = command;
          _focusNode.requestFocus();
          _commandController.selection = TextSelection.collapsed(
            offset: _commandController.text.length,
          );
        },
      ),
    );
  }
}
