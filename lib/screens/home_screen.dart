import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../services/ssh_service.dart';
import '../models/bot_model.dart';
import 'logs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? _botFile;
  String _botFileName = '';
  Uint8List? _reqFile;
  String _reqFileName = '';
  final _botNameController = TextEditingController();
  String _deployStatus = '';
  List<String> _deploySteps = [];

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    final provider = context.read<AppProvider>();
    provider.setLoading(true);
    try {
      final servers = await ServerService.fetchServers();
      provider.setServers(servers);
      provider.clearError();
    } catch (e) {
      provider.setError('فشل في جلب السيرفرات: $e');
    }
    provider.setLoading(false);
  }

  Future<void> _pickBotFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['py'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _botFile = result.files.single.bytes;
        _botFileName = result.files.single.name;
      });
    }
  }

  Future<void> _pickReqFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _reqFile = result.files.single.bytes;
        _reqFileName = result.files.single.name;
      });
    }
  }

  bool _isValidBotName(String name) {
    final regex = RegExp(r'^[a-zA-Z0-9_-]+$');
    return regex.hasMatch(name);
  }

  void _showStep(String message) {
    setState(() {
      _deploySteps.add(message);
      _deployStatus = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: message.startsWith('❌') 
            ? const Color(0xFFE94560) 
            : message.startsWith('✅')
                ? const Color(0xFF00BFA6)
                : const Color(0xFF6C63FF),
      ),
    );
  }

  Future<void> _deployBot() async {
    if (_botFile == null || _botNameController.text.isEmpty) {
      _showStep('❌ اختار ملف البوت واكتب الاسم');
      return;
    }

    final botName = _botNameController.text.trim();

    if (!_isValidBotName(botName)) {
      _showStep('❌ اسم البوت لازم يكون إنجليزي فقط (a-z, 0-9, -, _)');
      return;
    }

    final provider = context.read<AppProvider>();
    provider.setLoading(true);
    provider.clearError();
    setState(() {
      _deploySteps = [];
      _deployStatus = 'جاري البدء...';
    });

    try {
      final servers = provider.servers;
      if (servers.isEmpty) {
        throw Exception('مفيش سيرفرات متاحة');
      }

      final server = ServerService.getLeastLoadedServer(servers);
      _showStep('🎯 تم اختيار السيرفر: ${server.name}');

      final steps = await SSHService.deployBot(
        server: server,
        botFile: _botFile!,
        botFileName: _botFileName,
        reqFile: _reqFile,
        botName: botName,
      );

      for (final entry in steps.entries) {
        _showStep(entry.value);
      }

      final finalStatus = steps['run'] ?? '✅ تم التشغيل';
      
      provider.setBot(BotModel(
        name: botName,
        serverName: server.name,
        status: finalStatus,
        createdAt: DateTime.now(),
      ));

    } catch (e) {
      _showStep('❌ فشل: $e');
      provider.setError(e.toString());
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LogsScreen()),
      );
    }

    provider.setLoading(false);
  }

  Future<void> _restartBot() async {
    final provider = context.read<AppProvider>();
    if (provider.myBot == null || provider.servers.isEmpty) return;

    provider.setLoading(true);
    _showStep('🔄 جاري إعادة تشغيل البوت...');

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      final pid = await SSHService.restartBot(
        server, 
        provider.myBot!.name,
        'bot.py'
      );
      _showStep('✅ تم إعادة التشغيل! PID: $pid');
      
      provider.setBot(BotModel(
        name: provider.myBot!.name,
        serverName: provider.myBot!.serverName,
        status: 'تم إعادة التشغيل ✅ PID: $pid',
        createdAt: provider.myBot!.createdAt,
      ));
    } catch (e) {
      _showStep('❌ فشل إعادة التشغيل: $e');
    }

    provider.setLoading(false);
  }

  Future<void> _deleteBot() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف البوت؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final provider = context.read<AppProvider>();
    await provider.clearSavedBot();
    _showStep('🗑️ تم حذف البوت');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF00BFA6)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.rocket_launch, size: 50, color: Colors.white),
                        const SizedBox(height: 10),
                        Text(
                          '🤖 BotHost Pro',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'استضافة البوتات بضغطة زر',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Bot Name
                  TextField(
                    controller: _botNameController,
                    decoration: InputDecoration(
                      labelText: 'اسم البوت (إنجليزي فقط)',
                      hintText: 'مثال: my_bot, bot123, test-bot',
                      prefixIcon: const Icon(Icons.smart_toy),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFF16213E),
                      helperText: 'a-z, 0-9, -, _ فقط',
                      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Bot File
                  _buildFileCard(
                    icon: Icons.code,
                    label: 'ملف البوت (bot.py)',
                    fileName: _botFileName,
                    onTap: _pickBotFile,
                    isRequired: true,
                  ),
                  const SizedBox(height: 10),

                  // Requirements File
                  _buildFileCard(
                    icon: Icons.list_alt,
                    label: 'ملف المتطلبات (requirements.txt)',
                    fileName: _reqFileName,
                    onTap: _pickReqFile,
                    isRequired: false,
                  ),
                  const SizedBox(height: 20),

                  // Deploy Button
                  SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: provider.isLoading ? null : _deployBot,
                      icon: provider.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.rocket_launch),
                      label: Text(
                        provider.isLoading ? 'جاري التشغيل...' : '🚀 شغل البوت',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Progress Steps
                  if (_deploySteps.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF6C63FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋 خطوات التشغيل:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6C63FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._deploySteps.map((step) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  step.startsWith('❌') 
                                      ? Icons.error 
                                      : step.startsWith('✅')
                                          ? Icons.check_circle
                                          : Icons.pending,
                                  size: 16,
                                  color: step.startsWith('❌') 
                                      ? const Color(0xFFE94560) 
                                      : step.startsWith('✅')
                                          ? const Color(0xFF00BFA6)
                                          : Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    step,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: step.startsWith('❌') 
                                          ? const Color(0xFFE94560) 
                                          : step.startsWith('✅')
                                              ? const Color(0xFF00BFA6)
                                              : Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],

                  // My Bot Status
                  if (provider.myBot != null) ...[
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00BFA6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF00BFA6)),
                              const SizedBox(width: 8),
                              Text(
                                'بوتك شغال!',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFF00BFA6),
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('الاسم: ${provider.myBot!.name}'),
                          Text('السيرفر: ${provider.myBot!.serverName}'),
                          Text('الحالة: ${provider.myBot!.status}'),
                          Text('تاريخ الإنشاء: ${provider.myBot!.createdAt.toString().substring(0, 16)}'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _restartBot,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('إعادة تشغيل'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00BFA6),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _deleteBot,
                                  icon: const Icon(Icons.delete, size: 18, color: Color(0xFFE94560)),
                                  label: const Text('حذف', style: TextStyle(color: Color(0xFFE94560))),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFE94560)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                      icon: const Icon(Icons.terminal),
                      label: const Text('عرض السجلات'),
                    ),
                  ],

                  const Spacer(),

                  // Servers Status
                  if (provider.servers.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.dns, size: 18, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            '${provider.servers.length} سيرفر متاح',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileCard({
    required IconData icon,
    required String label,
    required String fileName,
    required VoidCallback onTap,
    required bool isRequired,
  }) {
    final hasFile = fileName.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile ? const Color(0xFF00BFA6) : Colors.white24,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: hasFile ? const Color(0xFF00BFA6) : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    hasFile ? '✅ $fileName' : (isRequired ? 'مطلوب *' : 'اختياري'),
                    style: TextStyle(
                      color: hasFile ? const Color(0xFF00BFA6) : Colors.white38,
                      fontWeight: hasFile ? FontWeight.bold : null,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              hasFile ? Icons.check_circle : Icons.add_circle_outline,
              color: hasFile ? const Color(0xFF00BFA6) : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}
