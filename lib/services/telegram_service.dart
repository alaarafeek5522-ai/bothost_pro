import 'package:url_launcher/url_launcher.dart';

class TelegramService {
  static const String _channelUrl = 'https://t.me/ahrgq';

  static Future<bool> openChannel() async {
    final uri = Uri.parse(_channelUrl);
    
    // نجرب فتح الرابط مباشرة
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
    
    // لو فشل، نجرب بـ tg://
    try {
      final tgUri = Uri.parse('tg://resolve?domain=ahrgq');
      if (await canLaunchUrl(tgUri)) {
        return await launchUrl(
          tgUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('Error launching tg://: $e');
    }
    
    // آخر محاولة: نفتح في المتصفح
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      print('Final launch error: $e');
    }
    
    return false;
  }
}
