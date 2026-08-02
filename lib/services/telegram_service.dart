import 'package:url_launcher/url_launcher.dart';

class TelegramService {
  static const String _channelUrl = 'https://t.me/ahrgq';
  static const String _supportUrl = 'https://t.me/ahrgq';

  static Future<bool> openChannel() async {
    return await _openUrl(_channelUrl);
  }

  static Future<bool> openSupport() async {
    return await _openUrl(_supportUrl);
  }

  static Future<bool> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    
    // نجرب الطريقة المباشرة الأولى
    if (await canLaunchUrl(uri)) {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    }
    
    // لو فشلت، نجرب بـ tg://
    final tgUri = Uri.parse('tg://resolve?domain=ahrgq');
    if (await canLaunchUrl(tgUri)) {
      return await launchUrl(
        tgUri,
        mode: LaunchMode.externalApplication,
      );
    }
    
    return false;
  }
}
