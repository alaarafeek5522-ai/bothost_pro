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
        final test = await _clients[key]!.execute('echo PING');
        await test.done;
        _lastUsed[key] = DateTime.now();
        return _clients[key]!;
      } catch (_) {
        _clients[key]?.close();
        _clients.remove(key);
      }
    }

    final socket = await SSHSocket.connect(server.host, server.port)
        .timeout(const Duration(seconds: 10));
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
      client = await _connect(server).timeout(const Duration(seconds: 15));
      steps['connect'] = '✅ تم الاتصال بالسيرفر';

      steps['pip'] = '🔄 جاري التأكد من pip...';
      await _ensurePip(client);
      steps['pip'] = '✅ pip جاهز';

      final sftp = await client.sftp().timeout(const Duration(seconds: 10));

      final userDir = '/root/bots/user_$userId';
      final botDir = '$userDir/$botName';

      steps['clean'] = '🔄 جاري تنظيف المجلد...';
      final cleanResult = await client.execute('rm -rf $botDir && mkdir -p $botDir && chmod 700 $userDir && echo "CLEAN_OK"');
      final cleanOutput = await _readStream(cleanResult.stdout);
      await cleanResult.done;
      if (!cleanOutput.contains('CLEAN_OK')) {
        throw Exception('فشل تنظيف المجلد');
      }
      steps['clean'] = '✅ تم تنظيف المجلد';

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
      final installOutput = await _readStream(installResult.stdout);
      final installError = await _readStream(installResult.stderr);
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

      steps['run'] = '🔄 جاري تشغيل البوت...';
      await client.execute('pkill -9 -f "$botDir" 2>/dev/null || true');
      await Future.delayed(const Duration(seconds: 1));
      
      // ✅ raw string - Dart ما بيعتبرش $ فيها
      final runResult = await client.execute(
        r'cd ' + botDir + r' && nohup python3 ' + botFileName + r' > bot.log 2>&1 & echo $!'
      );
      final runOutput = await _readStream(runResult.stdout);
      await runResult.done;
      
      final pid = runOutput.trim();
      if (pid.isEmpty || int.tryParse(pid) == null) {
        final psResult = await client.execute('ps aux | grep "$botFileName" | grep -v grep | awk \'{print \$2}\' | head -1');
        final psOutput = await _readStream(psResult.stdout);
        await psResult.done;
        
        final altPid = psOutput.trim();
        if (altPid.isEmpty || int.tryParse(altPid) == null) {
          steps['run'] = '❌ فشل تشغيل البوت';
          throw Exception('فشل تشغيل البوت - مفيش PID');
        }
        steps['run'] = '✅ البوت شغال! PID: $altPid';
      } else {
        steps['run'] = '✅ البوت شغال! PID: $pid';
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
      client = await _connect(server).timeout(const Duration(seconds: 10));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== STOPPING BOT ==="
        pkill -9 -f "$botDir" 2>/dev/null || true
        sleep 2
        for pid in \$(ps aux | grep "$botDir" | grep -v grep | awk '{print \$2}'); do
          echo "Killing PID: \$pid"
          kill -9 \$pid 2>/dev/null || true
        done
        sleep 1
        ps aux | grep "$botDir" | grep -v grep || echo "STOPPED"
      ''');
      
      final output = await _readStream(result.stdout);
      await result.done;
      
      return output.contains('STOPPED');
    } catch (e) {
      print('Stop bot error: $e');
      return false;
    }
  }

  static Future<bool> deleteBotFromServer(ServerModel server, String botName, String userId) async {
    await stopBot(server, botName, userId);
    await Future.delayed(const Duration(seconds: 2));
    
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 10));
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
      client = await _connect(server).timeout(const Duration(seconds: 10));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== BOT LOG ===" && 
        cat $botDir/bot.log 2>&1 || echo "No logs yet" &&
        echo "" &&
        echo "=== PROCESS STATUS ===" &&
        ps aux | grep "$botDir" | grep -v grep || echo "Bot process not found" &&
        echo "" &&
        echo "=== DISK USAGE ===" &&
        du -sh $botDir 2>/dev/null || echo "N/A" &&
        echo "" &&
        echo "=== BOT STATUS ===" &&
        if [ -f "$botDir/bot.py" ]; then echo "FILES_EXIST"; else echo "NO_FILES"; fi
      ''');
      
      final output = await _readStream(result.stdout);
      await result.done;
      return output;
    } catch (e) {
      return 'فشل في جلب السجلات: $e';
    }
  }

  static Future<String> restartBot(ServerModel server, String botName, String botFileName, String userId) async {
    await stopBot(server, botName, userId);
    await Future.delayed(const Duration(seconds: 2));
    
    SSHClient? client;
    try {
      client = await _connect(server).timeout(const Duration(seconds: 10));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final checkResult = await client.execute('ls $botDir/$botFileName 2>/dev/null && echo "EXISTS" || echo "MISSING"');
      final checkOutput = await _readStream(checkResult.stdout);
      await checkResult.done;
      
      if (checkOutput.contains('MISSING')) {
        throw Exception('ملف البوت مش موجود على السيرفر');
      }
      
      // ✅ raw string - Dart ما بيعتبرش $ فيها
      final result = await client.execute(
        r'cd ' + botDir + r' && nohup python3 ' + botFileName + r' > bot.log 2>&1 & echo $!'
      );
      final output = await _readStream(result.stdout);
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
      client = await _connect(server).timeout(const Duration(seconds: 10));
      final botDir = '/root/bots/user_$userId/$botName';
      
      final result = await client.execute('''
        echo "=== CHECK ==="
        ps aux | grep "$botDir" | grep -v grep | wc -l
        echo "---"
        ls -la $botDir 2>/dev/null && echo "DIR_EXISTS" || echo "NO_DIR"
        echo "---"
        cat $botDir/bot.log 2>/dev/null | tail -5 || echo "NO_LOG"
      ''');
      
      final output = await _readStream(result.stdout);
      await result.done;
      
      final lines = output.split('\n');
      int processCount = 0;
      bool dirExists = false;
      String lastLog = '';
      
      for (final line in lines) {
        if (int.tryParse(line.trim()) != null) {
          processCount = int.parse(line.trim());
        } else if (line.contains('DIR_EXISTS')) {
          dirExists = true;
        } else if (!line.startsWith('===') && !line.startsWith('---') && line.trim().isNotEmpty) {
          lastLog = line;
        }
      }
      
      return {
        'isRunning': processCount > 0,
        'dirExists': dirExists,
        'processCount': processCount,
        'lastLog': lastLog,
      };
    } catch (e) {
      return {
        'isRunning': false,
        'dirExists': false,
        'processCount': 0,
        'lastLog': 'Error: $e',
      };
    }
  }
}
