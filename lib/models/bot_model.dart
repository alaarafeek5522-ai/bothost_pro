class BotModel {
  final String name;
  final String serverName;
  final String status;
  final DateTime createdAt;
  final String fileName; // ✅ اسم ملف البوت الفعلي على السيرفر (مش لازم يبقى bot.py)

  BotModel({
    required this.name,
    required this.serverName,
    required this.status,
    required this.createdAt,
    this.fileName = 'bot.py', // ✅ افتراضي للتوافق مع بوتات قديمة متسجلة قبل التعديل
  });

  // ✅ للتخزين — نحول DateTime لـ int
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'serverName': serverName,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch, // ✅ int
      'fileName': fileName,
    };
  }

  // ✅ من التخزين
  factory BotModel.fromJson(Map<String, dynamic> json) {
    return BotModel(
      name: json['name'],
      serverName: json['serverName'],
      status: json['status'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']), // ✅ int
      fileName: json['fileName'] ?? 'bot.py', // ✅ لو بوت قديم متسجل قبل الحقل ده
    );
  }
}
