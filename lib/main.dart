import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/app_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/update_service.dart';
import 'services/vpn_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BotHostPro());
}

class BotHostPro extends StatelessWidget {
  const BotHostPro({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'BotHost Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await Future.delayed(const Duration(seconds: 2));

    // تحقق من التحديثات
    if (await UpdateService.shouldShowUpdate()) {
      final update = await UpdateService.checkUpdate();
      if (update != null && mounted) {
        if (update['stopped'] == true) {
          _showStoppedDialog(update['stop_message']);
          return;
        }
        if (update['force_update'] == true) {
          _showUpdateDialog(update['update_message'], update['download_url']);
          return;
        }
      }
    }

    // تحقق من VPN
    // VPNService.showVPNDialog(context); // فعلها لو عايز

    // تحقق من تسجيل الدخول
    final user = await AuthService.getCurrentUser();
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user != null ? const HomeScreen() : const LoginScreen(),
        ),
      );
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

  void _showUpdateDialog(String message, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🚀 تحديث جديد'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            onPressed: () {
              // افتح الرابط
              Navigator.pop(ctx);
            },
            child: const Text('تحديث الآن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rocket_launch, size: 100, color: Color(0xFF6C63FF)),
            const SizedBox(height: 20),
            Text(
              'BotHost Pro',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6C63FF),
                  ),
            ),
            const SizedBox(height: 10),
            const Text('جاري التحميل...', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
