import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_model.dart';

class SSHService {
  static final Map<String, SSHClient> _clients = {};
  static final Map<String, SSHSession> _sessions = {};
  static final Map<String, StreamController<String>> _outputControllers = {};
  static final Map<String, bool> _connected = {};

  static Future<SSHClient> _connect(ServerModel server) async {
    final key = '${server.host}:${server.port}';
    
    if (_clients.containsKey(key) && _connected[key] == true) {
      try {
        final test = await _clients[key]!.execute('echo PING').timeout(const Duration(seconds: 5));
        await test.done;
        return _clients[key]!;
      } catch (_) {
        _disconnect(key);
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
    _connected[key] = true;
    return client;
  }

  static void _disconnect(String key) {
    _sessions[key]?.close();
    _sessions.remove(key);
    _clients[key]?.close();
    _clients.remove(key);
    _connected[key] = false;
    _outputControllers[key]?.close();
    _outputControllers.remove(key);
  }

  static Future<void> disconnectAll() async {
    for (final key in List.of(_clients.keys)) {
      _disconnect(key);
    }
  }

  // ========== TERMINAL SESSION ==========
  static Future<Stream<String>> startTerminalSession(
    ServerModel server,
    String userId, {
    Function(String)? onOutput,
    Function()? onDisconnect,
  }) async {
    final key = '${server.host}:${server.port}';
    final client = await _connect(server);
    
    // نعمل مجلد المستخدم لو مش موجود
    final userDir = '/root/bots/user_$userId';
    final setupResult = await client.execute('mkdir -p $userDir && cd $userDir && pwd');
    await setupResult.done;

    // نبدأ shell session
    final session = await client.shell(
      pty: const SSHPtyConfig(
        width: 120,
        height: 40,
      ),
    );

    _sessions[key] = session;

    // نروح للمجلد بتاع المستخدم
    session.stdin.add(utf8.encode('cd $userDir && clear && echo "=== Terminal Ready ===" && pwd\n'));

    final controller = StreamController<String>.broadcast();
    _outputControllers[key] = controller;

    session.stdout.listen(
      (data) {
        final text = utf8.decode(data);
        controller.add(text);
        onOutput?.call(text);
      },
      onError: (e) {
        controller.addError(e);
        onDisconnect?.call();
      },
      onDone: () {
        controller.close();
        onDisconnect?.call();
      },
    );

    session.stderr.listen(
      (data) {
        final text = utf8.decode(data);
        controller.add(text);
        onOutput?.call(text);
      },
    );

    return controller.stream;
  }

  static void sendCommand(ServerModel server, String command) {
    final key = '${server.host}:${server.port}';
    final session = _sessions[key];
    if (session != null) {
      session.stdin.add(utf8.encode('$command\n'));
    }
  }

  static void sendCtrlC(ServerModel server) {
    final key = '${server.host}:${server.port}';
    final session = _sessions[key];
    if (session != null) {
      session.stdin.add(Uint8List.fromList([0x03])); // Ctrl+C
    }
  }

  static bool isConnected(ServerModel server) {
    final key = '${server.host}:${server.port}';
    return _connected[key] == true;
  }

  // ========== FILE OPERATIONS ==========
  static Future<bool> uploadFile(
    ServerModel server,
    String userId,
    Uint8List fileBytes,
    String remotePath,
  ) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 20));
      final sftp = await client.sftp().timeout(const Duration(seconds: 15));
      
      final remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
      );
      await remoteFile.writeBytes(fileBytes);
      await remoteFile.close();
      return true;
    } catch (e) {
      print('Upload error: $e');
      return false;
    }
  }

  static Future<Uint8List?> downloadFile(
    ServerModel server,
    String remotePath,
  ) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 20));
      final sftp = await client.sftp().timeout(const Duration(seconds: 15));
      
      final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      final bytes = await remoteFile.readBytes();
      await remoteFile.close();
      return bytes;
    } catch (e) {
      print('Download error: $e');
      return null;
    }
  }

  static Future<List<FileInfo>> listFiles(
    ServerModel server,
    String remotePath,
  ) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 15));
      final result = await client.execute('ls -la "$remotePath" 2>/dev/null || echo "ERROR"');
      final output = await _readStream(result.stdout);
      await result.done;

      if (output.contains('ERROR')) return [];

      final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
      final files = <FileInfo>[];

      for (final line in lines.skip(1)) { // skip total
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 9) continue;

        final permissions = parts[0];
        final size = parts[4];
        final date = '${parts[5]} ${parts[6]} ${parts[7]}';
        final name = parts.sublist(8).join(' ');

        files.add(FileInfo(
          name: name,
          size: size,
          permissions: permissions,
          date: date,
          isDirectory: permissions.startsWith('d'),
          isExecutable: permissions.contains('x'),
        ));
      }

      return files;
    } catch (e) {
      print('List files error: $e');
      return [];
    }
  }

  static Future<bool> createDirectory(
    ServerModel server,
    String remotePath,
  ) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 15));
      final result = await client.execute('mkdir -p "$remotePath" && echo "OK"');
      final output = await _readStream(result.stdout);
      await result.done;
      return output.contains('OK');
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteFile(
    ServerModel server,
    String remotePath,
  ) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 15));
      final result = await client.execute('rm -rf "$remotePath" && echo "OK"');
      final output = await _readStream(result.stdout);
      await result.done;
      return output.contains('OK');
    } catch (e) {
      return false;
    }
  }

  static Future<String> executeCommand(
    ServerModel server,
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final client = await _connect(server).timeout(const Duration(seconds: 20));
      final result = await client.execute(command);
      final output = await _readStream(result.stdout, timeout: timeout);
      await result.done;
      return output;
    } catch (e) {
      return 'Error: $e';
    }
  }

  static Future<String> _readStream(
    Stream<Uint8List> stream, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
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
}

class FileInfo {
  final String name;
  final String size;
  final String permissions;
  final String date;
  final bool isDirectory;
  final bool isExecutable;

  FileInfo({
    required this.name,
    required this.size,
    required this.permissions,
    required this.date,
    required this.isDirectory,
    required this.isExecutable,
  });
}
