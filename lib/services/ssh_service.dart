import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_model.dart';

class SSHService {
  static final Map<String, SSHClient> _clients = {};
  static final Map<String, DateTime> _lastUsed = {};

  static Future<SSHClient> _connect(ServerModel server) async {
    final key = '${server.host}:${server.port}';
    
    if (_clients.containsKey(key)) {
      try {
        final test = await _clients[key]!.execute('echo PING').timeout(const Duration(seconds: 5));
        await test.done;
        _lastUsed[key] = DateTime.now();
        return _clients[key]!;
      } catch (_) {
        _clients[key]?.close();
        _clients.remove(key);
      }
    }

    final socket = await SSHSocket.connect(server.host, server.port)
        .timeout(const Duration(seconds: 15));
    final client = SSHClient(
      socket,
      username: server.user,
      onPasswordRequest: () => server.password,
    );
    
    _clients[key] = client;
    _lastUsed[key] = DateTime.now();
    return client;
  }

  static void closeAll() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    _lastUsed.clear();
  }

  static Future<String> _readStream(Stream<Uint8List> stream, {Duration timeout = const Duration(seconds: 30)}) async {
    final bytes = <int>[];
    final completer = Completer<String>();
    
    final subscription = stream.listen(
      (chunk) => bytes.addAll(chunk),
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(bytes));
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
    );

    Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(utf8.decode(bytes));
      }
    });

    return completer.future;
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
    final installOutput = await _readStream(installPip.stdout, timeout: const Duration(seconds: 60));
    await installPip.done;

    if (installOutput.contains('PIP_FAILED')) {
      throw Exception('❌ مقدرش أنزل pip على السيرفر');
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
    SSHClient? client;

    try {
      steps['connect'] = '🔄 جاري الاتصال بالسيرفر...';
      client = await _connect(server).timeout(const Duration(seconds: 20));
      steps['connect'] = '✅ تم الاتصال بالسيرفر';

      steps['pip'] = '🔄 جاري التأكد من pip...';
      await _ensurePip(client);
      steps['pip'] = '✅ pip جاهز';

      final sftp = await client.sftp().timeout(const Duration(seconds: 15));

      // ✅ كل بوت في مجلد منفصل: userId/botName
      final userDir = '/root/bots/user_$userId';
      final botDir = '$userDir/$botName';

      steps['clean'] = '🔄 جاري إعداد المجلد...';
      final cleanResult = await client.execute('mkdir -p $botDir && chmod 700 $userDir && echo "OK"');
      final cleanOutput = await _readStream(cleanResult.stdout);
      await cleanResult.done;
      if (!cleanOutput.contains('OK')) {
        throw Exception('فشل إنشاء المجلد');
      }
      steps['clean'] = '✅ تم إعداد المجلد';

      steps['upload_bot'] = '🔄 جاري رفع bot.py...';
      final botRemote = await sftp.open(
        '$botDir/$botFileName',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );
      await botRemote.writeBytes(botFile);
      await botRemote.close();
      await client.execute('chmod +x $botDir/$botFileName');
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
        pip3 install --no-cache-dir -r requirements.txt 2>&1 && echo "===INSTALL_OK===" || 
        (python3 -m pip install --no-cache-dir -r requirements.txt 2>&1 && echo "===INSTALL_OK===") || 
        echo "===INSTALL_FAILED==="
      ''';
      
      final installResult = await client.execute(installCmd);
      final installOutput = await _readStream(installResult.stdout, timeout: const Duration(seconds: 120));
      final installError = await _readStream(installResult.stderr, timeout: const Duration(seconds: 30));
      await installResult.done;

      final fullInstallLog = 'STDOUT:\\n$installOutput\\n\\nSTDERR:\\n$installError';
      
      if (installOutput.contains('===INSTALL_OK===')) {
        steps['install'] = '✅ تم تثبيت المتطلبات';
      } else {
        steps['install'] = '❌ فشل تثبيت المتطلبات';
        steps['install_log'] = fullInstallLog;
        throw Exception('فشل تثبيت المتطلبات');
      }

      steps['check'] = '🔄 جاري التحقق من المكتبات...';
      final checkResult = await client.execute('python3 -c "import telebot; print(\\\"OK\\\")" 2>&1 || echo "MODULE_MISSING"');
      final checkOutput = await _readStream(checkResult.stdout);
      await checkResult.done;
      
      if (checkOutput.contains('MODULE_MISSING')) {
        steps['check'] = '❌ مكتبة telebot مش متوفرة';
        throw Exception('مكتبة telebot مش متوفرة');
      }
      steps['check'] = '✅ المكتبات جاهزة';

      // ✅ نقتل أي process قديم بنفس المسار (مش بنفس الاسم عشان ماتقتلش بوتات تانية)
      steps['run'] = '🔄 جاري تشغيل البوت...';
      await client.execute('pkill -9 -f "$botDir/$botFileName" 2>/dev/null || true');
      await Future.delayed(const Duration(seconds: 2));
      
      // ✅ نستخدم screen عشان الـ process يفضل شغال حتى لو الـ SSH قفل
      final runCmd = '''
        cd $botDir && 
        (screen -dmS ${botName}_bot python3 $botFileName > bot.log 2>&1) && 
        sleep 1 && 
        ps aux | grep "$botDir/$botFileName" | grep -v grep | awk '{print \$2}' | head -1
      ''';
      
      final runResult = await client.execute(runCmd);
      final runOutput = await _readStream(runResult.stdout, timeout: const Duration(seconds: 15));
      await runResult.done;
      
      final pid = runOutput.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        // محاولة تانية بدون screen
        final fallbackCmd = r'cd ' + botDir + r' && nohup python3 ' + botFileName + r' > bot.log 2>&1 & echo $!';
        final fallbackResult = await client.execute(fallbackCmd);
        final fallbackOutput = await _readStream(fallbackResult.stdout);
        await fallbackResult.done;
        
        final fallbackPid = fallbackOutput.trim();
        if (fallbackPid.isEmpty || int.tryParse(fallbackPid) == null) {
          steps['run'] = '❌ فشل تشغيل البوت';
          throw Exception('فشل تشغيل البوت - مفيش PID');
        }
        steps['run'] = '✅ البوت شغال! PID: $fallbackPid';
      } else {
        steps['run'] = '✅ البوت شغال! PID: $pid (screen)';
      }

    } catch (e) {
      steps['error'] = '❌ خطأ: $e';
      rethrow;
    }

    return steps;
  }

  static Future<bool> stopBot(ServerModel server, String botName, String userId) async {
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== STOPPING BOT ==="
        # اقتل الـ screen session
        screen -S ${botName}_bot -X quit 2>/dev/null || true
        # اقتل بالمسار المحدد
        pkill -9 -f "$botDir/bot.py" 2>/dev/null || true
        sleep 2
        # تأكد
        ps aux | grep "$botDir/bot.py" | grep -v grep || echo "STOPPED"
      ''');
      
      final output = await _readStream(result.stdout, timeout: const Duration(seconds: 15));
      await result.done;
      
      return output.contains('STOPPED');
    } catch (e) {
      print('Stop bot error: $e');
      return false;
    }
  }

  static Future<bool> deleteBotFromServer(ServerModel server, String botName, String userId) async {
    await stopBot(server, botName, userId);
    await Future.delayed(const Duration(seconds: 3));
    
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== DELETING FILES ==="
        rm -rf $botDir 2>/dev/null && echo "DELETED" || echo "RM_FAILED"
        ls -la $botDir 2>/dev/null || echo "DIR_GONE"
      ''');
      
      final output = await _readStream(result.stdout);
      await result.done;
      
      return output.contains('DELETED') || output.contains('DIR_GONE');
    } catch (e) {
      print('Delete bot error: $e');
      return false;
    }
  }

  static Future<String> getLogs(ServerModel server, String botName, String userId) async {
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== BOT LOG ===" && 
        cat $botDir/bot.log 2>&1 || echo "No logs yet" &&
        echo "" &&
        echo "=== PROCESS STATUS ===" &&
        ps aux | grep "$botDir/bot.py" | grep -v grep || echo "Bot process not found" &&
        echo "" &&
        echo "=== SCREEN SESSIONS ===" &&
        screen -ls | grep ${botName}_bot || echo "No screen session" &&
        echo "" &&
        echo "=== DISK USAGE ===" &&
        du -sh $botDir 2>/dev/null || echo "N/A"
      ''');
      
      final output = await _readStream(result.stdout, timeout: const Duration(seconds: 20));
      await result.done;
      return output;
    } catch (e) {
      return 'فشل في جلب السجلات: $e';
    }
  }

  static Future<String> restartBot(ServerModel server, String botName, String botFileName, String userId) async {
    await stopBot(server, botName, userId);
    await Future.delayed(const Duration(seconds: 3));
    
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final checkResult = await client.execute('ls $botDir/$botFileName 2>/dev/null && echo "EXISTS" || echo "MISSING"');
      final checkOutput = await _readStream(checkResult.stdout);
      await checkResult.done;
      
      if (checkOutput.contains('MISSING')) {
        throw Exception('ملف البوت مش موجود على السيرفر');
      }
      
      final runCmd = '''
        cd $botDir && 
        (screen -dmS ${botName}_bot python3 $botFileName > bot.log 2>&1) && 
        sleep 1 && 
        ps aux | grep "$botDir/$botFileName" | grep -v grep | awk '{print \$2}' | head -1
      ''';
      
      final result = await client.execute(runCmd);
      final output = await _readStream(result.stdout, timeout: const Duration(seconds: 15));
      await result.done;
      
      final pid = output.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        throw Exception('فشل إعادة التشغيل - مفيش PID');
      }
      return pid;
    } catch (e) {
      throw Exception('فشل إعادة التشغيل: $e');
    }
  }

  static Future<Map<String, dynamic>> checkBotStatus(ServerModel server, String botName, String userId) async {
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 15));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== CHECK ==="
        ps aux | grep "$botDir/bot.py" | grep -v grep | wc -l
        echo "---"
        screen -ls | grep ${botName}_bot | wc -l
        echo "---"
        ls -la $botDir 2>/dev/null && echo "DIR_EXISTS" || echo "NO_DIR"
        echo "---"
        cat $botDir/bot.log 2>/dev/null | tail -5 || echo "NO_LOG"
      ''');
      
      final output = await _readStream(result.stdout, timeout: const Duration(seconds: 15));
      await result.done;
      
      final lines = output.split('\n');
      int processCount = 0;
      int screenCount = 0;
      bool dirExists = false;
      String lastLog = '';
      int section = 0;
      
      for (final line in lines) {
        if (line.contains('=== CHECK ===')) {
          section = 1;
          continue;
        } else if (line.contains('---')) {
          section++;
          continue;
        }
        
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        if (section == 1 && int.tryParse(trimmed) != null) {
          processCount = int.parse(trimmed);
        } else if (section == 2 && int.tryParse(trimmed) != null) {
          screenCount = int.parse(trimmed);
        } else if (section == 3 && trimmed.contains('DIR_EXISTS')) {
          dirExists = true;
        } else if (section == 4 && !trimmed.contains('NO_LOG')) {
          lastLog = trimmed;
        }
      }
      
      return {
        'isRunning': processCount > 0 || screenCount > 0,
        'dirExists': dirExists,
        'processCount': processCount,
        'screenCount': screenCount,
        'lastLog': lastLog,
      };
    } catch (e) {
      return {
        'isRunning': false,
        'dirExists': false,
        'processCount': 0,
        'screenCount': 0,
        'lastLog': 'Error: $e',
      };
    }
  }
}
