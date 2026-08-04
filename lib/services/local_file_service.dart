import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class LocalFileService {
  static Future<String> get _botDir async {
    final dir = await getApplicationDocumentsDirectory();
    final botDir = Directory('${dir.path}/bot_files');
    if (!await botDir.exists()) {
      await botDir.create(recursive: true);
    }
    return botDir.path;
  }

  /// حفظ ملف البوت محلياً
  static Future<String> saveBotFile(Uint8List bytes, String fileName) async {
    final dir = await _botDir;
    final path = '$dir/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  /// حفظ requirements.txt محلياً
  static Future<String?> saveReqFile(Uint8List? bytes, String fileName) async {
    if (bytes == null) return null;
    final dir = await _botDir;
    final path = '$dir/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  /// قراءة ملف البوت المحفوظ
  static Future<Uint8List?> readBotFile(String fileName) async {
    try {
      final dir = await _botDir;
      final file = File('$dir/$fileName');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      print('Error reading bot file: $e');
    }
    return null;
  }

  /// قراءة requirements.txt المحفوظ
  static Future<Uint8List?> readReqFile(String fileName) async {
    try {
      final dir = await _botDir;
      final file = File('$dir/$fileName');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      print('Error reading req file: $e');
    }
    return null;
  }

  /// حذف الملفات المحلية
  static Future<void> clearFiles() async {
    try {
      final dir = await _botDir;
      final directory = Directory(dir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      print('Error clearing files: $e');
    }
  }

  /// قائمة الملفات المحفوظة
  static Future<List<String>> getSavedFiles() async {
    try {
      final dir = await _botDir;
      final directory = Directory(dir);
      if (!await directory.exists()) return [];
      final files = await directory.list().toList();
      return files.whereType<File>().map((f) => f.path.split('/').last).toList();
    } catch (e) {
      return [];
    }
  }
}
