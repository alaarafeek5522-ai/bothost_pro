import 'package:url_launcher/url_launcher.dart';

class TelegramService {
  static const String _channelUrl = 'https://t.me/ahrgq';

  static Future<bool> openChannel() async {
    final uri = Uri.parse(_channelUrl);
    
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
