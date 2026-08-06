import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/server_model.dart';  // ✅ ناقص ده
import '../services/server_service.dart';
import '../services/auth_service.dart';
import '../services/ssh_service.dart';
import '../services/telegram_service.dart';
import 'terminal_screen.dart';
import 'file_manager_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    await _loadUser();
    await _loadServers();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      context.read<AppProvider>().saveUserEmail(user.email);
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

  Future<void> _connectToTerminal() async {
    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    final user = await AuthService.getCurrentUser();

    if (server == null) {
      _showError('❌ اختار سيرفر الأول');
      return;
    }

    if (user == null) {
      _showError('❌ لازم تسجل دخول');
      return;
    }

    setState(() => _isConnecting = true);

    try {
      await SSHService.startTerminalSession(
        server,
        user.deviceId,
        onOutput: (text) {
          provider.addTerminalOutput(text);
        },
        onDisconnect: () {
          provider.setTerminalConnected(false);
          _showError('❌ تم قطع الاتصال');
        },
      );

      provider.setTerminalConnected(true);
      provider.setCurrentPath('/root/bots/user_${user.deviceId}');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TerminalScreen()),
        );
      }
    } catch (e) {
      _showError('❌ فشل الاتصال: $e');
    }

    setState(() => _isConnecting = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE94560)),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          '🚪 تسجيل خروج',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'متأكد إنك عايز تخرج؟',
          style: TextStyle(color: Colors.white70),
        ),
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

    await SSHService.disconnectAll();
    await AuthService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _openTelegram() async {
    final success = await TelegramService.openChannel();
    if (!success) {
      _showError('❌ مقدرش أفتح التليجرام');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(provider),
                  const SizedBox(height: 25),

                  if (provider.servers.isNotEmpty) _buildServerSelector(provider),
                  const SizedBox(height: 20),

                  _buildQuickActionsGrid(provider),
                  const SizedBox(height: 20),

                  _buildServerStatus(provider),
                ],
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
          const Icon(Icons.terminal, size: 50, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            'Terminal SSH Pro',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            'ترمنال متصل بالسيرفر',
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

  Widget _buildServerSelector(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dns, color: Color(0xFF6C63FF), size: 20),
              SizedBox(width: 8),
              Text(
                'اختر السيرفر:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6C63FF),
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...provider.servers.map((server) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: provider.selectedServer?.name == server.name
                  ? const Color(0xFF6C63FF).withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: provider.selectedServer?.name == server.name
                    ? const Color(0xFF6C63FF)
                    : Colors.white12,
              ),
            ),
            child: RadioListTile<ServerModel>(
              title: Text(
                server.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${server.host}:${server.port} | Load: ${server.loadScore.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: server,
              groupValue: provider.selectedServer,
              activeColor: const Color(0xFF00BFA6),
              onChanged: (ServerModel? value) => provider.setSelectedServer(value),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(AppProvider provider) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.2,
      children: [
        _buildActionCard(
          icon: Icons.terminal,
          title: 'فتح الترمنال',
          subtitle: 'SSH Terminal',
          color: const Color(0xFF3FB950),
          onTap: _isConnecting ? null : _connectToTerminal,
          isLoading: _isConnecting,
        ),
        _buildActionCard(
          icon: Icons.folder_open,
          title: 'مدير الملفات',
          subtitle: 'رفع/تنزيل',
          color: const Color(0xFF58A6FF),
          onTap: provider.selectedServer == null
              ? () => _showError('❌ اختار سيرفر الأول')
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FileManagerScreen()),
                ),
        ),
        _buildActionCard(
          icon: Icons.cloud_upload,
          title: 'رفع ملف',
          subtitle: 'Upload File',
          color: const Color(0xFFD29922),
          onTap: provider.selectedServer == null
              ? () => _showError('❌ اختار سيرفر الأول')
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FileManagerScreen(initialAction: 'upload'),
                  ),
                ),
        ),
        _buildActionCard(
          icon: Icons.support_agent,
          title: 'الدعم',
          subtitle: 'قناة التليجرام',
          color: const Color(0xFF6C63FF),
          onTap: _openTelegram,
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStatus(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            provider.isTerminalConnected ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: provider.isTerminalConnected
                ? const Color(0xFF3FB950)
                : Colors.white38,
          ),
          const SizedBox(width: 8),
          Text(
            provider.isTerminalConnected
                ? 'متصل بالسيرفر ✅'
                : '${provider.servers.length} سيرفر متاح | غير متصل',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
