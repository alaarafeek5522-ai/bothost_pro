
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../services/ssh_service.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../models/bot_model.dart';
import 'logs_screen.dart';
import 'login_screen.dart';

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
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadServers();
    _checkUpdate();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() => _userEmail = user.email);
    }
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

  Future<void> _checkUpdate() async {
    if (await UpdateService.shouldShowUpdate()) {
      final update = await UpdateService.checkUpdate();
      if (update != null && mounted) {
        if (update['stopped'] == true) {
          _showStoppedDialog(update['stop_message']);
          return;
        }
      }
    }
  }

  void _showStoppedDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⛔ التطبيق متوقف'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
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

    final user = await AuthService.getCurrentUser();
    if (user == null) {
      _showStep('❌ لازم تسجل دخول الأول');
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
        userId: user.deviceId,
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

    final user = await AuthService.getCurrentUser();
    if (user == null) return;

    provider.setLoading(true);
    _showStep('🔄 جاري إعادة تشغيل البوت...');

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      final pid = await SSHService.restartBot(
        server, 
        provider.myBot!.name,
        'bot.py',
        user.deviceId,
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
        title: const Row(
          children: [
            Icon(Icons.warning, color: Color(0xFFE94560)),
            SizedBox(width: 10),
            Text('⚠️ تأكيد الحذف'),
          ],
        ),
        content: const Text('هل أنت متأكد من حذف البوت؟\nالحذف نهائي!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final provider = context.read<AppProvider>();
    final user = await AuthService.getCurrentUser();
    if (user == null || provider.myBot == null) return;

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      await SSHService.deleteBot(server, provider.myBot!.name, user.deviceId);
      await provider.clearSavedBot();
      _showStep('🗑️ تم حذف البوت نهائياً');
    } catch (e) {
      _showStep('❌ فشل الحذف: $e');
    }
  }

  Future<void> _openTelegram() async {
    const url = 'https://t.me/ahrgq';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showStep('❌ مقدرش أفتح التليجرام');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚪 تسجيل خروج'),
        content: const Text('متأكد إنك عايز تخرج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج', style: TextStyle(color: Color(0xFFE94560))),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('🤖 BotHost Pro'),
            centerTitle: true,
            actions: [
              // زر الدعم
              IconButton(
                icon: const Icon(Icons.support_agent),
                tooltip: 'الدعم',
                onPressed: _openTelegram,
              ),
              // زر الخروج
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'خروج',
                onPressed: _logout,
              ),
            ],
          ),
          drawer: _buildDrawer(),
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
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.rocket_launch, size: 50, color: Colors.white),
                        const SizedBox(height: 10),
                        Text(
                          'BotHost Pro',
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
                        if (_userEmail != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '👤 $_userEmail',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: const Color(0xFF6C63FF).withOpacity(0.5),
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
                        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.list_alt, color: Color(0xFF6C63FF), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'خطوات التشغيل:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6C63FF),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ..._deploySteps.map((step) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  step.startsWith('❌') 
                                      ? Icons.error 
                                      : step.startsWith('✅')
                                          ? Icons.check_circle
                                          : step.startsWith('🎯')
                                              ? Icons.location_on
                                              : Icons.pending,
                                  size: 16,
                                  color: step.startsWith('❌') 
                                      ? const Color(0xFFE94560) 
                                      : step.startsWith('✅') || step.startsWith('🎯')
                                          ? const Color(0xFF00BFA6)
                                          : Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    step,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: step.startsWith('❌') 
                                          ? const Color(0xFFE94560) 
                                          : step.startsWith('✅') || step.startsWith('🎯')
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
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00BFA6).withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF00BFA6)),
                              const SizedBox(width: 8),
                              Text(
                                'بوتك شغال! 🎉',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFF00BFA6),
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 20),
                          _buildInfoRow('الاسم:', provider.myBot!.name),
                          _buildInfoRow('السيرفر:', provider.myBot!.serverName),
                          _buildInfoRow('الحالة:', provider.myBot!.status),
                          _buildInfoRow('التاريخ:', provider.myBot!.createdAt.toString().substring(0, 16)),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _restartBot,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('إعادة تشغيل'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00BFA6),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _deleteBot,
                                  icon: const Icon(Icons.delete, size: 18, color: Color(0xFFE94560)),
                                  label: const Text('حذف', style: TextStyle(color: Color(0xFFE94560))),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFE94560)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                      label: const Text('📋 عرض السجلات'),
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
                          const SizedBox(width: 15),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00BFA6),
                              shape: BoxShape.circle,
                            ),
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

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: const Color(0xFF1A1A2E),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00BFA6)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.rocket_launch, size: 50, color: Colors.white),
                  const SizedBox(height: 10),
                  Text(
                    'BotHost Pro',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (_userEmail != null)
                    Text(
                      _userEmail!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent, color: Color(0xFF6C63FF)),
              title: const Text('الدعم والمساعدة'),
              onTap: () {
                Navigator.pop(context);
                _openTelegram();
              },
            ),
            ListTile(
              leading: const Icon(Icons.telegram, color: Color(0xFF00BFA6)),
              title: const Text('قناة التليجرام'),
              onTap: () {
                Navigator.pop(context);
                _openTelegram();
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.white70),
              title: const Text('عن التطبيق'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: 'BotHost Pro',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.rocket_launch, color: Color(0xFF6C63FF)),
                  children: [
                    const Text('استضافة البوتات بضغطة زر'),
                    const SizedBox(height: 10),
                    const Text('📢 قناة التليجرام: @ahrgq'),
                  ],
                );
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFE94560)),
              title: const Text('تسجيل خروج', style: TextStyle(color: Color(0xFFE94560))),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
                    style: const TextStyle(
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
