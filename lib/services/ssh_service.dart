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
    await client.execute('mkdir -p /root/bots/$botName');

    // رفع ملف البوت — نحول Uint8List لـ Stream
    final botRemote = await sftp.open(
      '/root/bots/$botName/$botFileName',
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    await botRemote.write(Stream.fromIterable([botFile]));
    await botRemote.close();

    // رفع requirements لو موجود
    if (reqFile != null) {
      final reqRemote = await sftp.open(
        '/root/bots/$botName/requirements.txt',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );
      await reqRemote.write(Stream.fromIterable([reqFile]));
      await reqRemote.close();
    }

    // تثبيت المتطلبات
    final installSession = await client.execute('cd /root/bots/$botName && pip install -r requirements.txt 2>&1 || echo "NO_REQ"');
    final installOutput = await installSession.stdout.join();
    await installSession.done;

    // تشغيل البوت في background
    final runSession = await client.execute('cd /root/bots/$botName && nohup python3 $botFileName > bot.log 2>&1 & echo \$!');
    final runOutput = await runSession.stdout.join();
    await runSession.done;

    final pid = runOutput.trim();

    client.close();

    if (pid.isEmpty || pid == '') {
      throw Exception('فشل في تشغيل البوت');
    }

    return '✅ البوت شغال!\nPID: $pid\nServer: ${server.name}\nInstall: ${installOutput.contains("NO_REQ") ? "No requirements" : "Done"}';
  }

  static Future<String> getLogs(ServerModel server, String botName) async {
    final client = await connect(server);
    final session = await client.execute('cat /root/bots/$botName/bot.log 2>&1 || echo "No logs yet"');
    final output = await session.stdout.join();
    await session.done;
    client.close();
    return output;
  }
}
