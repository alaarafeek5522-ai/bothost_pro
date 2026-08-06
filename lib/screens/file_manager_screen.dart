import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ssh_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class FileManagerScreen extends StatefulWidget {
  final String? initialAction;
  const FileManagerScreen({super.key, this.initialAction});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  List<FileInfo> _files = [];
  bool _isLoading = false;
  String _currentPath = '';
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _newFolderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initPath();
    if (widget.initialAction == 'upload') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _uploadFile());
    }
  }

  Future<void> _initPath() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      _currentPath = '/root/bots/user_${user.deviceId}';
      _pathController.text = _currentPath;
      context.read<AppProvider>().setCurrentPath(_currentPath);
      await _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server == null) return;

    setState(() => _isLoading = true);

    try {
      final files = await SSHService.listFiles(server, _currentPath);
      setState(() => _files = files);
    } catch (e) {
      _showError('❌ فشل تحميل الملفات: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.single.bytes == null) return;

    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server == null) return;

    final fileName = result.files.single.name;
    final fileBytes = result.files.single.bytes!;

    setState(() => _isLoading = true);

    try {
      final remotePath = '$_currentPath/$fileName';
      final success = await SSHService.uploadFile(server, '', fileBytes, remotePath);

      if (success) {
        _showSuccess('✅ تم رفع $fileName');
        await _loadFiles();
      } else {
        _showError('❌ فشل الرفع');
      }
    } catch (e) {
      _showError('❌ خطأ: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _downloadFile(String fileName) async {
    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server == null) return;

    setState(() => _isLoading = true);

    try {
      final remotePath = '$_currentPath/$fileName';
      final bytes = await SSHService.downloadFile(server, remotePath);

      if (bytes != null) {
        _showSuccess('✅ تم تنزيل $fileName (${bytes.length} bytes)');
      } else {
        _showError('❌ فشل التنزيل');
      }
    } catch (e) {
      _showError('❌ خطأ: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _createFolder() async {
    final name = _newFolderController.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server == null) return;

    setState(() => _isLoading = true);

    try {
      final newPath = '$_currentPath/$name';
      final success = await SSHService.createDirectory(server, newPath);

      if (success) {
        _showSuccess('✅ تم إنشاء المجلد');
        _newFolderController.clear();
        await _loadFiles();
      } else {
        _showError('❌ فشل إنشاء المجلد');
      }
    } catch (e) {
      _showError('❌ خطأ: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _deleteFile(String fileName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          '🗑️ حذف',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'متأكد إنك عايز تمسح $fileName؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final provider = context.read<AppProvider>();
    final server = provider.selectedServer;
    if (server == null) return;

    setState(() => _isLoading = true);

    try {
      final remotePath = '$_currentPath/$fileName';
      final success = await SSHService.deleteFile(server, remotePath);

      if (success) {
        _showSuccess('✅ تم الحذف');
        await _loadFiles();
      } else {
        _showError('❌ فشل الحذف');
      }
    } catch (e) {
      _showError('❌ خطأ: $e');
    }

    setState(() => _isLoading = false);
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      _currentPath = '$_currentPath/$folderName';
      _pathController.text = _currentPath;
    });
    context.read<AppProvider>().setCurrentPath(_currentPath);
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      setState(() {
        _currentPath = parts.join('/');
        if (_currentPath.isEmpty) _currentPath = '/';
        _pathController.text = _currentPath;
      });
      context.read<AppProvider>().setCurrentPath(_currentPath);
      _loadFiles();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE94560)),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF00BFA6)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dark,
      appBar: AppBar(
        title: const Text('📁 مدير الملفات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: const Color(0xFF30363D))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, color: AppTheme.terminalGreen),
                  onPressed: _navigateUp,
                ),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'المسار...',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                    onSubmitted: (value) {
                      setState(() => _currentPath = value);
                      context.read<AppProvider>().setCurrentPath(_currentPath);
                      _loadFiles();
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1117),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadFile,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('رفع ملف', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _showCreateFolderDialog(),
                    icon: const Icon(Icons.create_new_folder, size: 18),
                    label: const Text('مجلد جديد', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 60, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              '📂 المجلد فاضي',
                              style: TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final file = _files[index];
                          return _buildFileItem(file);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(FileInfo file) {
    final isDir = file.isDirectory;
    final icon = isDir ? Icons.folder : _getFileIcon(file.name);
    final color = isDir ? const Color(0xFFD29922) : const Color(0xFF58A6FF);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          file.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${file.size} | ${file.permissions} | ${file.date}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDir)
              IconButton(
                icon: const Icon(Icons.download, color: AppTheme.terminalGreen, size: 22),
                tooltip: 'تنزيل',
                onPressed: () => _downloadFile(file.name),
              ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppTheme.terminalRed, size: 22),
              tooltip: 'حذف',
              onPressed: () => _deleteFile(file.name),
            ),
          ],
        ),
        onTap: isDir ? () => _navigateToFolder(file.name) : null,
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.py')) return Icons.code;
    if (lower.endsWith('.txt')) return Icons.description;
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.sh')) return Icons.terminal;
    if (lower.endsWith('.js')) return Icons.javascript;
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return Icons.html;
    if (lower.endsWith('.css')) return Icons.css;
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz'))
      return Icons.folder_zip;
    if (lower.endsWith('.jpg') || lower.endsWith('.png') || lower.endsWith('.gif'))
      return Icons.image;
    if (lower.endsWith('.mp4') || lower.endsWith('.avi') || lower.endsWith('.mkv'))
      return Icons.video_file;
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.ogg'))
      return Icons.audio_file;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.md')) return Icons.description;
    return Icons.insert_drive_file;
  }

  void _showCreateFolderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          '📁 مجلد جديد',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _newFolderController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'اسم المجلد',
            labelStyle: const TextStyle(color: Colors.white70),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF30363D)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _newFolderController.clear();
              Navigator.pop(ctx);
            },
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createFolder();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA6)),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }
}
