import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../services/ssh_service.dart';
import '../services/auth_service.dart';
import '../services/telegram_service.dart';
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
  List<String> _deploySteps = [];
  bool _isCheckingStatus = false;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    await _loadUser();
    await _loadServers();
    await _checkUpdate();
    await _syncBotStatus();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      context.read<AppProvider>().saveUserEmail(user.email);
    }
  }

  Future<void> _syncBotStatus() async {
    final provider = context.read<AppProvider>();
    if (provider.myBot == null || provider.servers.isEmpty) return;

    final user = await AuthService.getCurrentUser();
    if (user == null) return;

    setState(() => _isCheckingStatus = true);

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      
      final status = await SSHService.checkBotStatus(
        server, 
        provider.myBot!.name, 
        user.deviceId,
      );
      
      final isRunning = status['isRunning'] as bool;
      final dirExists = status['dirExists'] as bool;
      
      if (!dirExists) {
        await AuthService.setBotStatus(false);
        await provider.clearSavedBot();
        _showStep('⚠️ البوت اتمسح من السيرفر');
      } else if (!isRunning && provider.myBot!.status.contains('شغال')) {
        provider.updateBotStatus('متوقف ⏹️ (الملفات موجودة)');
      } else if (isRunning && !provider.myBot!.status.contains('شغال')) {
        provider.updateBotStatus('شغال ✅');
      }
    } catch (e) {
      print('Sync error: $e');
    }

    setState(() => _isCheckingStatus = false);
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
    });
    
    final color = message.startsWith('❌') 
        ? const Color(0xFFE94560) 
        : message.startsWith('✅') || message.startsWith('🎯')
            ? const Color(0xFF00BFA6)
            : const Color(0xFF6C63FF);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: color,
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
      _showStep('❌ اسم البوت لازم يكون إنجليزي فقط');
      return;
    }

    final user = await AuthService.getCurrentUser();
    if (user == null) {
      _showStep('❌ لازم تسجل دخول الأول');
      return;
    }

    final provider = context.read<AppProvider>();
    
    if (provider.hasBot || provider.myBot != null) {
      _showStep('❌ عندك بوت! احذف القديم الأول');
      return;
    }

    provider.setLoading(true);
    provider.clearError();
    setState(() => _deploySteps = []);

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
        if (entry.key != 'install_log') {
          _showStep(entry.value);
        }
      }

      final finalStatus = steps['run'] ?? '✅ تم التشغيل';
      final pid = finalStatus.contains('PID:') 
          ? finalStatus.split('PID:').last.trim() 
          : null;
      
      await AuthService.setBotStatus(true);
      
      final currentUser = await AuthService.getCurrentUser();
      if (currentUser != null) {
        await AuthService.updateBotStatus(currentUser.deviceId, true);
      }
      
      provider.setBot(
        BotModel(
          name: botName,
          serverName: server.name,
          status: 'شغال ✅',
          createdAt: DateTime.now(),
        ),
        pid: pid,
      );

      _showStep('✅ البوت شغال بنجاح!');

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
      provider.updateBotStatus('شغال ✅ (تم إعادة التشغيل)', pid: pid);
    } catch (e) {
      _showStep('❌ فشل إعادة التشغيل: $e');
    }

    provider.setLoading(false);
  }

  Future<void> _stopBotOnly() async {
    final provider = context.read<AppProvider>();
    if (provider.myBot == null || provider.servers.isEmpty) return;

    final user = await AuthService.getCurrentUser();
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.stop_circle, color: Color(0xFFFFA726)),
            SizedBox(width: 10),
            Text('⏹️ إيقاف البوت'),
          ],
        ),
        content: const Text(
          'هيتم إيقاف البوت مؤقتاً.\n\n'
          'الملفات هتفضل موجودة على السيرفر.\n'
          'تقدر تشغله تاني لاحقاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFA726)),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    provider.setLoading(true);
    _showStep('⏹️ جاري إيقاف البوت...');

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      
      final stopped = await SSHService.stopBot(
        server, 
        provider.myBot!.name, 
        user.deviceId,
      );
      
      if (stopped) {
        _showStep('✅ تم إيقاف البوت');
        provider.updateBotStatus('متوقف ⏹️ (الملفات موجودة)');
      } else {
        _showStep('⚠️ البوت متوقف بالفعل');
      }
    } catch (e) {
      _showStep('❌ فشل الإيقاف: $e');
    }

    provider.setLoading(false);
  }

  Future<void> _deleteBotForever() async {
    final provider = context.read<AppProvider>();
    if (provider.myBot == null || provider.servers.isEmpty) return;

    final user = await AuthService.getCurrentUser();
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Color(0xFFE94560)),
            SizedBox(width: 10),
            Text('🗑️ حذف نهائي'),
          ],
        ),
        content: const Text(
          '⚠️ الحذف نهائي ولا يمكن التراجع!\n\n'
          '1. البوت هيتوقف\n'
          '2. الملفات هتمسح من السيرفر\n'
          '3. هتقدر ترفع بوت جديد\n\n'
          'متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    provider.setLoading(true);
    _showStep('🗑️ جاري الحذف النهائي...');

    try {
      final server = provider.servers.firstWhere(
        (s) => s.name == provider.myBot!.serverName,
      );
      
      final deleted = await SSHService.deleteBotFromServer(
        server, 
        provider.myBot!.name, 
        user.deviceId,
      );
      
      if (!deleted) {
        throw Exception('فشل حذف الملفات من السيرفر');
      }

      await AuthService.setBotStatus(false);
      
      final currentUser = await AuthService.getCurrentUser();
      if (currentUser != null) {
        await AuthService.updateBotStatus(currentUser.deviceId, false);
      }
      
      await provider.clearSavedBot();
      _showStep('✅ تم الحذف النهائي!');

      setState(() {
        _botFile = null;
        _botFileName = '';
        _reqFile = null;
        _reqFileName = '';
        _botNameController.clear();
        _deploySteps = [];
      });

    } catch (e) {
      _showStep('❌ فشل الحذف: $e');
    }

    provider.setLoading(false);
  }

  Future<void> _forceSync() async {
    _showStep('🔄 جاري التحقق من حالة البوت...');
    await _syncBotStatus();
    _showStep('✅ تم التحقق');
  }

  Future<void> _openTelegram() async {
    final success = await TelegramService.openChannel();
    if (!success) {
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
              if (_isCheckingStatus)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'مزامنة الحالة',
                onPressed: _isCheckingStatus ? null : _forceSync,
              ),
              IconButton(
                icon: const Icon(Icons.support_agent),
                tooltip: 'الدعم',
                onPressed: _openTelegram,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'خروج',
                onPressed: _logout,
              ),
            ],
          ),
          drawer: _buildDrawer(provider),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _syncBotStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(provider),
                    const SizedBox(height: 25),

                    if (provider.hasBot || provider.myBot != null)
                      _buildBotCard(provider),
                    
                    if (!provider.hasBot && provider.myBot == null)
                      _buildDeployForm(provider),

                    const SizedBox(height: 20),
                    _buildServerStatus(provider),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(AppProvider provider) {
    return Container(
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
          if (provider.userEmail != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '👤 ${provider.userEmail}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotCard(AppProvider provider) {
    final isRunning = provider.myBot?.status.contains('شغال') ?? false;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRunning ? const Color(0xFF00BFA6) : const Color(0xFFFFA726),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isRunning ? const Color(0xFF00BFA6) : const Color(0xFFFFA726)).withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF00BFA6) : const Color(0xFFFFA726),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isRunning ? const Color(0xFF00BFA6) : const Color(0xFFFFA726)).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isRunning ? 'البوت شغال 🟢' : 'البوت متوقف 🟡',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isRunning ? const Color(0xFF00BFA6) : const Color(0xFFFFA726),
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (provider.botPid != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'PID: ${provider.botPid}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
            ],
          ),
          const Divider(color: Colors.white24, height: 25),
          
          if (provider.myBot != null) ...[
            _buildInfoRow('الاسم:', provider.myBot!.name),
            _buildInfoRow('السيرفر:', provider.myBot!.serverName),
            _buildInfoRow('الحالة:', provider.myBot!.status),
            _buildInfoRow('التاريخ:', provider.myBot!.createdAt.toString().substring(0, 16)),
          ],
          
          const SizedBox(height: 20),
          
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!isRunning)
                ElevatedButton.icon(
                  onPressed: provider.isLoading ? null : _restartBot,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('تشغيل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA6),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              if (isRunning)
                ElevatedButton.icon(
                  onPressed: provider.isLoading ? null : _stopBotOnly,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('إيقاف'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA726),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: provider.isLoading ? null : _restartBot,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة تشغيل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                ),
                icon: const Icon(Icons.terminal, size: 18),
                label: const Text('السجلات'),
              ),
              ElevatedButton.icon(
                onPressed: provider.isLoading ? null : _deleteBotForever,
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text('حذف'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeployForm(AppProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _botNameController,
          decoration: InputDecoration(
            labelText: 'اسم البوت (إنجليزي فقط)',
            hintText: 'مثال: my_bot, bot123',
            prefixIcon: const Icon(Icons.smart_toy),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFF16213E),
            helperText: 'a-z, 0-9, -, _ فقط',
            helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        const SizedBox(height: 15),

        _buildFileCard(
          icon: Icons.code,
          label: 'ملف البوت (bot.py)',
          fileName: _botFileName,
          onTap: _pickBotFile,
          isRequired: true,
        ),
        const SizedBox(height: 10),

        _buildFileCard(
          icon: Icons.list_alt,
          label: 'ملف المتطلبات (requirements.txt)',
          fileName: _reqFileName,
          onTap: _pickReqFile,
          isRequired: false,
        ),
        const SizedBox(height: 20),

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

        if (_deploySteps.isNotEmpty) ...[
          const SizedBox(height: 20),
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
        ],
      ],
    );
  }

  Widget _buildServerStatus(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(15),
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
    );
  }

  Widget _buildDrawer(AppProvider provider) {
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
                  if (provider.userEmail != null)
                    Text(
                      provider.userEmail!,
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
                    const SizedBox(height: 5),
                    const Text('🔒 كل حساب = بوت واحد'),
                    const SizedBox(height: 5),
                    const Text('📱 جهاز واحد = حساب واحد'),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 13, 
                fontWeight: FontWeight.w500,
              ),
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
