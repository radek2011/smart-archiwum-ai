import 'dart:convert';
import 'dart:typed_data';
import 'package:idb_shim/idb_browser.dart';

/// Local browser archive. Data stays in IndexedDB for this site/browser.
/// Browser data removal, private mode, or storage eviction can delete it.
class LocalArchiveRecord {
  const LocalArchiveRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.date,
    required this.createdAt,
    required this.pdfBase64,
    this.summary = '',
    this.extractedText = '',
  });

  final String id, title, category, date, createdAt, pdfBase64;
  final String summary, extractedText;
  Uint8List get pdfBytes => base64Decode(pdfBase64);
  int get size => (pdfBase64.length * 3 / 4).round();

  factory LocalArchiveRecord.fromMap(Map<String, dynamic> data) =>
      LocalArchiveRecord(
        id: (data['id'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        category: (data['category'] ?? '').toString(),
        date: (data['date'] ?? '').toString(),
        createdAt: (data['createdAt'] ?? '').toString(),
        pdfBase64: (data['pdfBase64'] ?? '').toString(),
        summary: (data['summary'] ?? '').toString(),
        extractedText: (data['extractedText'] ?? '').toString(),
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'date': date,
    'createdAt': createdAt,
    'pdfBase64': pdfBase64,
    'summary': summary,
    'extractedText': extractedText,
  };
}

class LocalArchiveStore {
  static const _dbName = 'smart_archiwum_local_v1';
  static const _store = 'documents';

  static Future<Database> _open() async {
    final factory = getIdbFactory();
    if (factory == null) {
      throw StateError('IndexedDB nie jest dostępne w tej przeglądarce.');
    }
    return factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore(_store, keyPath: 'id');
      },
    );
  }

  static Future<void> save(LocalArchiveRecord record) async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadWrite);
      await txn.objectStore(_store).put(record.toMap());
      await txn.completed;
    } finally {
      db.close();
    }
  }

  static Future<List<LocalArchiveRecord>> list() async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadOnly);
      final values = await txn.objectStore(_store).getAll();
      await txn.completed;
      final records = values
          .whereType<Map>()
          .map((v) => LocalArchiveRecord.fromMap(
              v.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } finally {
      db.close();
    }
  }

  static Future<void> delete(String id) async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadWrite);
      await txn.objectStore(_store).delete(id);
      await txn.completed;
    } finally {
      db.close();
    }
  }
}
