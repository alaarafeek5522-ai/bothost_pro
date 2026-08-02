import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_model.dart';

class SSHService {
  static Future<SSHClient> _connect(ServerModel server) async {
    final socket = await SSHSocket.connect(server.host, server.port);
    final client = SSHClient(
      socket,
      username: server.user,
      onPasswordRequest: () => server.password,
    );
    return client;
  }

  static Future<Map<String, String>> deployBot({
    required ServerModel server,
    required Uint8List botFile,
    required String botFileName,
    required Uint8List? reqFile,
    required String botName,
  }) async {
    final steps = <String, String>{};

    // Step 1: الاتصال
    steps['connect'] = '🔄 جاري الاتصال بالسيرفر...';
    late final SSHClient client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      steps['connect'] = '✅ تم الاتصال بالسيرفر';
    } catch (e) {
      steps['connect'] = '❌ فشل الاتصال: $e';
      throw Exception(steps['connect']);
    }

    try {
      final sftp = await client.sftp();

      // Step 2: إنشاء المجلد
      steps['mkdir'] = '🔄 جاري إنشاء مجلد البوت...';
      await client.execute('mkdir -p /root/bots/$botName');
      steps['mkdir'] = '✅ تم إنشاء مجلد البوت';

      // Step 3: رفع bot.py
      steps['upload_bot'] = '🔄 جاري رفع bot.py...';
      final botRemote = await sftp.open(
        '/root/bots/$botName/$botFileName',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );
      await botRemote.writeBytes(botFile);
      await botRemote.close();
      steps['upload_bot'] = '✅ تم رفع bot.py';

      // Step 4: رفع requirements
      if (reqFile != null) {
        steps['upload_req'] = '🔄 جاري رفع requirements.txt...';
        final reqRemote = await sftp.open(
          '/root/bots/$botName/requirements.txt',
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        await reqRemote.writeBytes(reqFile);
        await reqRemote.close();
        steps['upload_req'] = '✅ تم رفع requirements.txt';
      } else {
        steps['upload_req'] = '⏭️ مفيش requirements.txt';
      }

      // Step 5: تثبيت المتطلبات
      steps['install'] = '🔄 جاري تثبيت المتطلبات...';
      final installResult = await client.execute(
        'cd /root/bots/$botName && pip3 install -r requirements.txt 2>&1 || python3 -m pip install -r requirements.txt 2>&1 || echo "NO_REQ"'
      );
      final installOutput = await installResult.stdout.transform(utf8.decoder).join();
      await installResult.done;
      
      if (installOutput.contains('ERROR') || installOutput.contains('Failed')) {
        steps['install'] = '⚠️ تحذير في التثبيت: ${installOutput.substring(0, installOutput.length > 100 ? 100 : installOutput.length)}';
      } else {
        steps['install'] = '✅ تم تثبيت المتطلبات';
      }

      // Step 6: تشغيل البوت
      steps['run'] = '🔄 جاري تشغيل البوت...';
      final runResult = await client.execute(
        'cd /root/bots/$botName && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
      );
      final runOutput = await runResult.stdout.transform(utf8.decoder).join();
      await runResult.done;
      
      final pid = runOutput.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        steps['run'] = '❌ فشل تشغيل البوت: $runOutput';
        throw Exception(steps['run']);
      }
      steps['run'] = '✅ البوت شغال! PID: $pid';

    } catch (e) {
      // لو فيه خطأ في أي خطوة
      if (!steps.containsKey('run')) {
        steps['error'] = '❌ خطأ: $e';
      }
      rethrow;
    } finally {
      client.close();
    }

    return steps;
  }

  static Future<String> getLogs(ServerModel server, String botName) async {
    final client = await _connect(server);
    try {
      final result = await client.execute('cat /root/bots/$botName/bot.log 2>&1 || echo "No logs yet"');
      final output = await result.stdout.transform(utf8.decoder).join();
      await result.done;
      return output;
    } finally {
      client.close();
    }
  }
}
