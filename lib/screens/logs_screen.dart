import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ssh_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _isLoading = false;

  Future<void> _refreshLogs() async {
    final provider = context.read<AppProvider>();
    if (provider.myBot == null || provider.servers.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      final logs = await SSHService.getLogs(server, provider.myBot!.name);
      provider.setLogs(logs);
    } catch (e) {
      provider.setLogs('فشل في جلب السجلات: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('📋 سجلات البوت'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refreshLogs,
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Error Banner
                if (provider.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE94560).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE94560)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Color(0xFFE94560)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.error!,
                            style: const TextStyle(color: Color(0xFFE94560)),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Logs Terminal
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            child: SelectableText(
                              provider.logs.isEmpty
                                  ? 'اضغط 🔄 عشان تجيب السجلات'
                                  : provider.logs,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFF00FF00),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _refreshLogs,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تحديث السجلات'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('رجوع'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
