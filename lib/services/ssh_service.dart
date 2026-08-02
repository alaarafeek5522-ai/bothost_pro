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

  static Future<String> _readStream(Stream<Uint8List> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
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

      // Step 5: تثبيت المتطلبات (محسّن)
      steps['install'] = '🔄 جاري تثبيت المتطلبات...';
      
      // نجرب pip3 أولاً، بعدين python3 -m pip
      final installCmd = '''
        cd /root/bots/$botName && 
        (pip3 install -r requirements.txt 2>&1 && echo "===INSTALL_OK===") || 
        (python3 -m pip install -r requirements.txt 2>&1 && echo "===INSTALL_OK===") || 
        (pip install -r requirements.txt 2>&1 && echo "===INSTALL_OK===") || 
        echo "===INSTALL_FAILED==="
      ''';
      
      final installResult = await client.execute(installCmd);
      final installOutput = await _readStream(installResult.stdout);
      final installError = await _readStream(installResult.stderr);
      await installResult.done;

      // نحفظ اللوج كامل
      final fullInstallLog = 'STDOUT:\\n$installOutput\\n\\nSTDERR:\\n$installError';
      
      if (installOutput.contains('===INSTALL_OK===')) {
        steps['install'] = '✅ تم تثبيت المتطلبات';
      } else {
        steps['install'] = '❌ فشل تثبيت المتطلبات';
        steps['install_log'] = fullInstallLog;
        throw Exception('فشل تثبيت المتطلبات:\\n$fullInstallLog');
      }

      // Step 6: تشغيل البوت
      steps['run'] = '🔄 جاري تشغيل البوت...';
      
      // نتأكد إن telebot موجود
      final checkResult = await client.execute('python3 -c "import telebot; print(\\\"OK\\\")" 2>&1 || echo "MODULE_MISSING"');
      final checkOutput = await _readStream(checkResult.stdout);
      await checkResult.done;
      
      if (checkOutput.contains('MODULE_MISSING')) {
        steps['run'] = '❌ مكتبة telebot مش متوفرة بعد التثبيت';
        throw Exception('مكتبة telebot مش متوفرة - جرب تثبيت يدوي: pip3 install pyTelegramBotAPI');
      }

      final runResult = await client.execute(
        'cd /root/bots/$botName && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
      );
      final runOutput = await _readStream(runResult.stdout);
      await runResult.done;
      
      final pid = runOutput.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        steps['run'] = '❌ فشل تشغيل البوت: $runOutput';
        throw Exception(steps['run']);
      }
      steps['run'] = '✅ البوت شغال! PID: $pid';

    } catch (e) {
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
      // نجيب bot.log + نتأكد إن البوت شغال
      final result = await client.execute('''
        echo "=== BOT LOG ===" && 
        cat /root/bots/$botName/bot.log 2>&1 || echo "No logs yet" &&
        echo "" &&
        echo "=== PROCESS STATUS ===" &&
        ps aux | grep "$botName" | grep -v grep || echo "Bot process not found" &&
        echo "" &&
        echo "=== PYTHON PACKAGES ===" &&
        pip3 list 2>/dev/null | grep -i telebot || pip list 2>/dev/null | grep -i telebot || echo "telebot not in pip list"
      ''');
      final output = await _readStream(result.stdout);
      await result.done;
      return output;
    } finally {
      client.close();
    }
  }

  static Future<String> restartBot(ServerModel server, String botName, String botFileName) async {
    final client = await _connect(server);
    try {
      // نوقف البوت القديم
      await client.execute('pkill -f "/root/bots/$botName/$botFileName" || true');
      await Future.delayed(const Duration(seconds: 1));
      
      // نشغله تاني
      final result = await client.execute(
        'cd /root/bots/$botName && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
      );
      final output = await _readStream(result.stdout);
      await result.done;
      return output.trim();
    } finally {
      client.close();
    }
  }
}
