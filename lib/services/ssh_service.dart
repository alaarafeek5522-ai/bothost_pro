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

  static Future<String> deployBot({
    required ServerModel server,
    required Uint8List botFile,
    required String botFileName,
    required Uint8List? reqFile,
    required String botName,
  }) async {
    // اكتب الملفات مؤقتاً
    final botPath = await _writeTempFile(botFile, botFileName);
    String? reqPath;
    if (reqFile != null) {
      reqPath = await _writeTempFile(reqFile, 'requirements.txt');
    }

    // إنشاء مجلد البوت على السيرفر
    final mkdirResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'mkdir -p /root/bots/$botName'
    ]);

    if (mkdirResult.exitCode != 0) {
      throw Exception('فشل إنشاء المجلد: ${mkdirResult.stderr}');
    }

    // رفع ملف البوت
    final scpBotResult = await Process.run('scp', [
      '-P', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      botPath,
      '${server.user}@${server.host}:/root/bots/$botName/$botFileName'
    ]);

    if (scpBotResult.exitCode != 0) {
      throw Exception('فشل رفع bot.py: ${scpBotResult.stderr}');
    }

    // رفع requirements لو موجود
    if (reqPath != null) {
      final scpReqResult = await Process.run('scp', [
        '-P', '${server.port}',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        reqPath,
        '${server.user}@${server.host}:/root/bots/$botName/requirements.txt'
      ]);

      if (scpReqResult.exitCode != 0) {
        throw Exception('فشل رفع requirements.txt: ${scpReqResult.stderr}');
      }
    }

    // تثبيت المتطلبات
    final installResult = await Process.run('ssh', [
      '-p', '${server.port}',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '${server.user}@${server.host}',
      'cd /root/bots/$botName && pip3 install -r requirements.txt 2>&1 || python3 -m pip install -r requirements.txt 2>&1 || echo "NO_REQ"'
    ]);

    // تشغيل البوت
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

    if (pid.isEmpty) {
      throw Exception('فشل في تشغيل البوت');
    }

    return '✅ البوت شغال!\nPID: $pid\nServer: ${server.name}';
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
