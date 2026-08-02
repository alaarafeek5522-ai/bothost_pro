import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/server_model.dart';

class SSHService {
  static Future<String> _writeTempFile(Uint8List data, String name) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(data);
    return path;
  }

  static Future<Map<String, String>> deployBot({
    required ServerModel server,
    required Uint8List botFile,
    required String botFileName,
    required Uint8List? reqFile,
    required String botName,
  }) async {
    final steps = <String, String>{};

    // Step 1: الاتصال بالسيرفر
    steps['connect'] = 'جاري الاتصال بالسيرفر...';
    
    final testResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '-o', 'ConnectTimeout=10',
      '${server.user}@${server.host}',
      'echo "CONNECTED"'
    ]);

    if (testResult.exitCode != 0) {
      steps['connect'] = '❌ فشل الاتصال: ${testResult.stderr}';
      throw Exception(steps['connect']!);
    }
    steps['connect'] = '✅ تم الاتصال بالسيرفر';

    // Step 2: إنشاء المجلد
    steps['mkdir'] = 'جاري إنشاء مجلد البوت...';
    
    final mkdirResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'mkdir -p /root/bots/$botName'
    ]);

    if (mkdirResult.exitCode != 0) {
      steps['mkdir'] = '❌ فشل إنشاء المجلد: ${mkdirResult.stderr}';
      throw Exception(steps['mkdir']!);
    }
    steps['mkdir'] = '✅ تم إنشاء مجلد البوت';

    // Step 3: كتابة الملفات مؤقتاً
    steps['temp'] = 'جاري تحضير الملفات...';
    final botPath = await _writeTempFile(botFile, botFileName);
    String? reqPath;
    if (reqFile != null) {
      reqPath = await _writeTempFile(reqFile, 'requirements.txt');
    }
    steps['temp'] = '✅ تم تحضير الملفات';

    // Step 4: رفع ملف البوت
    steps['upload_bot'] = 'جاري رفع bot.py...';
    
    final scpBotResult = await Process.run('scp', [
      '-P', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      botPath,
      '${server.user}@${server.host}:/root/bots/$botName/$botFileName'
    ]);

    if (scpBotResult.exitCode != 0) {
      steps['upload_bot'] = '❌ فشل رفع bot.py: ${scpBotResult.stderr}';
      throw Exception(steps['upload_bot']!);
    }
    steps['upload_bot'] = '✅ تم رفع bot.py';

    // Step 5: رفع requirements
    if (reqPath != null) {
      steps['upload_req'] = 'جاري رفع requirements.txt...';
      
      final scpReqResult = await Process.run('scp', [
        '-P', '${server.port}',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        reqPath,
        '${server.user}@${server.host}:/root/bots/$botName/requirements.txt'
      ]);

      if (scpReqResult.exitCode != 0) {
        steps['upload_req'] = '❌ فشل رفع requirements.txt: ${scpReqResult.stderr}';
        throw Exception(steps['upload_req']!);
      }
      steps['upload_req'] = '✅ تم رفع requirements.txt';
    } else {
      steps['upload_req'] = '⏭️ مفيش requirements.txt';
    }

    // Step 6: تثبيت المتطلبات
    steps['install'] = 'جاري تثبيت المتطلبات...';
    
    final installResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'cd /root/bots/$botName && pip3 install -r requirements.txt 2>&1 || python3 -m pip install -r requirements.txt 2>&1 || echo "NO_REQ"'
    ]);

    final installOutput = installResult.stdout as String;
    if (installOutput.contains('ERROR') || installOutput.contains('Failed')) {
      steps['install'] = '⚠️ تحذير في التثبيت: $installOutput';
    } else {
      steps['install'] = '✅ تم تثبيت المتطلبات';
    }

    // Step 7: تشغيل البوت
    steps['run'] = 'جاري تشغيل البوت...';
    
    final runResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'cd /root/bots/$botName && nohup python3 $botFileName > bot.log 2>&1 & echo \$!'
    ]);

    final pid = (runResult.stdout as String).trim();

    // امسح الملفات المؤقتة
    await File(botPath).delete();
    if (reqPath != null) await File(reqPath).delete();

    if (pid.isEmpty || pid == '') {
      steps['run'] = '❌ فشل تشغيل البوت';
      throw Exception(steps['run']!);
    }
    steps['run'] = '✅ البوت شغال! PID: $pid';

    return steps;
  }

  static Future<String> getLogs(ServerModel server, String botName) async {
    final result = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'cat /root/bots/$botName/bot.log 2>&1 || echo "No logs yet"'
    ]);

    return result.stdout as String;
  }
}
