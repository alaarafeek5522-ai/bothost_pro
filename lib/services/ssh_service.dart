import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_model.dart';

class SSHService {
  static Future<SSHClient> connect(ServerModel server) async {
    final socket = await SSHSocket.connect(server.host, server.port);
    final client = SSHClient(
      socket,
      username: server.user,
      onPasswordRequest: () => server.password,
    );
    return client;
  }

  static Future<String> deployBot({
    required ServerModel server,
    required Uint8List botFile,
    required String botFileName,
    required Uint8List? reqFile,
    required String botName,
  }) async {
    final client = await connect(server);
    final sftp = await client.sftp();

    // إنشاء مجلد البوت
    final botDir = '/root/bots/$botName';
    await client.execute('mkdir -p $botDir');

    // رفع ملف البوت
    final botRemote = await sftp.open('$botDir/$botFileName', mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
    await botRemote.write(botFile);
    await botRemote.close();

    // رفع requirements لو موجود
    if (reqFile != null) {
      final reqRemote = await sftp.open('$botDir/requirements.txt', mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
      await reqRemote.write(reqFile);
      await reqRemote.close();
    }

    // تثبيت المتطلبات
    final installResult = await client.execute('cd $botDir && pip install -r requirements.txt 2>&1 || echo "NO_REQ"');
    final installOutput = await installResult.stdout.readBytes();
    final installText = String.fromCharCodes(installOutput);

    // تشغيل البوت في background
    final runResult = await client.execute('cd $botDir && nohup python3 $botFileName > bot.log 2>&1 & echo \$!');
    final runOutput = await runResult.stdout.readBytes();
    final pid = String.fromCharCodes(runOutput).trim();

    client.close();

    if (pid.isEmpty || pid == '') {
      throw Exception('فشل في تشغيل البوت');
    }

    return '✅ البوت شغال!\nPID: $pid\nServer: ${server.name}\nInstall: ${installText.contains("NO_REQ") ? "No requirements" : "Done"}';
  }

  static Future<String> getLogs(ServerModel server, String botName) async {
    final client = await connect(server);
    final result = await client.execute('cat /root/bots/$botName/bot.log 2>&1 || echo "No logs yet"');
    final output = await result.stdout.readBytes();
    client.close();
    return String.fromCharCodes(output);
  }
}
