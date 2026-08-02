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

  static Future<void> _ensurePip(SSHClient client) async {
    final check = await client.execute('which pip3 2>/dev/null || which pip 2>/dev/null || echo "NO_PIP"');
    final output = await _readStream(check.stdout);
    await check.done;

    if (!output.contains('NO_PIP')) return;

    final installPip = await client.execute('''
      (curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py 2>/dev/null && python3 /tmp/get-pip.py 2>/dev/null && echo "PIP_OK") ||
      (apt-get update -qq && apt-get install -y -qq python3-pip 2>/dev/null && echo "PIP_OK") ||
      (python3 -m ensurepip --upgrade 2>/dev/null && echo "PIP_OK") ||
      echo "PIP_FAILED"
    ''');
    final installOutput = await _readStream(installPip.stdout);
    await installPip.done;

    if (installOutput.contains('PIP_FAILED')) {
      throw Exception('❌ مقدرش أنزل pip على السيرفر - جرب تثبيته يدوياً');
    }
  }

  static Future<Map<String, String>> deployBot({
    required ServerModel server,
    required Uint8List botFile,
    required String botFileName,
    required Uint8List? reqFile,
    required String botName,
    required String userId,
  }) async {
    final steps = <String, String>{};

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
      steps['pip'] = '🔄 جاري التأكد من pip...';
      await _ensurePip(client);
      steps['pip'] = '✅ pip جاهز';

      final sftp = await client.sftp();

      final userDir = '/root/bots/user_$userId';
      final botDir = '$userDir/$botName';

      steps['mkdir'] = '🔄 جاري إنشاء مجلد البوت...';
      await client.execute('mkdir -p $botDir && chmod 700 $userDir');
      steps['mkdir'] = '✅ تم إنشاء مجلد البوت (محمي)';

      steps['upload_bot'] = '🔄 جاري رفع bot.py...';
      final botRemote = await sftp.open(
        '$botDir/$botFileName',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );
      await botRemote.writeBytes(botFile);
      await botRemote.close();
      steps['upload_bot'] = '✅ تم رفع bot.py';

      if (reqFile != null) {
        steps['upload_req'] = '🔄 جاري رفع requirements.txt...';
        final reqRemote = await sftp.open(
          '$botDir/requirements.txt',
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        await reqRemote.writeBytes(reqFile);
        await reqRemote.close();
        steps['upload_req'] = '✅ تم رفع requirements.txt';
      } else {
        steps['upload_req'] = '⏭️ مفيش requirements.txt';
      }

      steps['install'] = '🔄 جاري تثبيت المتطلبات...';
      
      final installCmd = '''
        cd $botDir && 
        pip3 install -r requirements.txt 2>&1 && echo "===INSTALL_OK===" || 
        (python3 -m pip install -r requirements.txt 2>&1 && echo "===INSTALL_OK===") || 
        echo "===INSTALL_FAILED==="
      ''';
      
      final installResult = await client.execute(installCmd);
      final installOutput = await _readStream(installResult.stdout);
      final installError = await _readStream(installResult.stderr);
      await installResult.done;

      final fullInstallLog = 'STDOUT:\\n$installOutput\\n\\nSTDERR:\\n$installError';
      
      if (installOutput.contains('===INSTALL_OK===')) {
        steps['install'] = '✅ تم تثبيت المتطلبات';
      } else {
        steps['install'] = '❌ فشل تثبيت المتطلبات';
        steps['install_log'] = fullInstallLog;
        throw Exception('فشل تثبيت المتطلبات:\\n$fullInstallLog');
      }

      steps['check'] = '🔄 جاري التحقق من المكتبات...';
      final checkResult = await client.execute('python3 -c "import telebot; print(\\\"OK\\\")" 2>&1 || echo "MODULE_MISSING"');
      final checkOutput = await _readStream(checkResult.stdout);
      await checkResult.done;
      
      if (checkOutput.contains('MODULE_MISSING')) {
        steps['check'] = '❌ مكتبة telebot مش متوفرة';
        throw Exception('مكتبة telebot مش متوفرة - جرب تثبيت يدوي: pip3 install pyTelegramBotAPI');
      }
      steps['check'] = '✅ المكتبات جاهزة';

      steps['run'] = '🔄 جاري تشغيل البوت...';
      final runResult = await client.execute(
        'cd $botDir && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
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

  // ========== إيقاف البوت ==========
  static Future<bool> stopBot(ServerModel server, String botName, String userId) async {
    final client = await _connect(server);
    try {
      final botDir = '/root/bots/user_$userId/$botName';
      
      // نوقف كل process في المجلد
      final result = await client.execute('''
        pkill -f "$botDir" 2>/dev/null || true
        sleep 1
        ps aux | grep "$botDir" | grep -v grep || echo "STOPPED"
      ''');
      
      final output = await _readStream(result.stdout);
      await result.done;
      
      return output.contains('STOPPED');
    } finally {
      client.close();
    }
  }

  // ========== حذف البوت من السيرفر ==========
  static Future<bool> deleteBotFromServer(ServerModel server, String botName, String userId) async {
    // أولاً: نوقف البوت
    await stopBot(server, botName, userId);
    
    final client = await _connect(server);
    try {
      final botDir = '/root/bots/user_$userId/$botName';
      
      // نحذف المجلد
      final result = await client.execute('rm -rf $botDir && echo "DELETED" || echo "FAILED"');
      final output = await _readStream(result.stdout);
      await result.done;
      
      return output.contains('DELETED');
    } finally {
      client.close();
    }
  }

  static Future<String> getLogs(ServerModel server, String botName, String userId) async {
    final client = await _connect(server);
    try {
      final botDir = '/root/bots/user_$userId/$botName';
      final result = await client.execute('''
        echo "=== BOT LOG ===" && 
        cat $botDir/bot.log 2>&1 || echo "No logs yet" &&
        echo "" &&
        echo "=== PROCESS STATUS ===" &&
        ps aux | grep "$botDir" | grep -v grep || echo "Bot process not found" &&
        echo "" &&
        echo "=== DISK USAGE ===" &&
        du -sh $botDir 2>/dev/null || echo "N/A"
      ''');
      final output = await _readStream(result.stdout);
      await result.done;
      return output;
    } finally {
      client.close();
    }
  }

  static Future<String> restartBot(ServerModel server, String botName, String botFileName, String userId) async {
    // نوقف القديم
    await stopBot(server, botName, userId);
    await Future.delayed(const Duration(seconds: 2));
    
    final client = await _connect(server);
    try {
      final botDir = '/root/bots/user_$userId/$botName';
      final result = await client.execute(
        'cd $botDir && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
      );
      final output = await _readStream(result.stdout);
      await result.done;
      return output.trim();
    } finally {
      client.close();
    }
  }
}
