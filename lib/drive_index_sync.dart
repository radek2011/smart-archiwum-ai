import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'drive_auth.dart';
import 'local_archive_store.dart';

/// Explicit, additive backup/restore of OCR metadata. Never uploads PDFs.
class DriveIndexSync {
  static String _clientId = '';
  static const _fileName = 'smart-archiwum-index-v1.json';

  static Future<int?> syncWithConsent(BuildContext context) async {
    final controller = TextEditingController(text: _clientId);
    Future<String>? authorization;
    try {
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Synchronizacja indeksu z Drive'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Zapiszemy lub pobierzemy nazwy, opisy i tekst OCR. '
                'Nie kopiujemy PDF-ów na telefon i nie usuwamy plików na Drive. '
                'Indeks może zawierać poufne informacje z dokumentów.'),
            const SizedBox(height: 12),
            TextField(controller: controller,
              decoration: const InputDecoration(labelText: 'Google OAuth Client ID',
                border: OutlineInputBorder())),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Anuluj')),
          FilledButton(onPressed: () {
            final id = controller.text.trim();
            if (!id.endsWith('.apps.googleusercontent.com')) return;
            _clientId = id;
            authorization = authorizeDrive(id);
            Navigator.pop(dialog);
          }, child: const Text('Połącz i synchronizuj')),
        ],
      ));
      if (authorization == null) return null;
      final token = await authorization!;
      final client = http.Client();
      try {
        return await _sync(client, token);
      } finally {
        client.close();
      }
    } finally {
      controller.dispose();
    }
  }

  /// Reuse the short-lived authorization granted for the PDF upload.
  /// The token is never written to disk.
  static Future<int> syncWithToken(String token) async {
    if (token.isEmpty) throw StateError('Brak ważnej sesji Google Drive');
    final client = http.Client();
    try {
      return await _sync(client, token);
    } finally {
      client.close();
    }
  }

  static Future<int> _sync(http.Client client, String token) async {
    final headers = {'Authorization': 'Bearer $token'};
    final q = "name = '$_fileName' and trashed = false and "
        "mimeType = 'application/json'";
    final listUri = Uri.https('www.googleapis.com','/drive/v3/files',{
      'q':q, 'fields':'nextPageToken,files(id,name,modifiedTime)',
      'pageSize':'100',
    });
    final listing = await client.get(listUri,headers:headers).timeout(const Duration(seconds: 20));
    if (listing.statusCode != 200) {
      throw StateError('Google Drive HTTP ${listing.statusCode} (odczyt indeksu)');
    }
    final data = jsonDecode(listing.body) as Map<String,dynamic>;
    final files = (data['files'] as List<dynamic>? ?? []);
    final ids = files.whereType<Map>().map((f)=>f['id']).whereType<String>().toList();
    if (ids.length > 1 || data['nextPageToken'] != null) {
      throw StateError('Znaleziono kilka indeksów o tej nazwie. '
          'Przerwano zapis, aby nie utracić danych.');
    }
    final existingId = ids.isEmpty ? null : ids.first;
    final remote = <String,LocalArchiveRecord>{};
    if (existingId != null) {
      final response = await client.get(
        Uri.https('www.googleapis.com','/drive/v3/files/$existingId',{'alt':'media'}),
        headers:headers).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('Nie udało się pobrać indeksu z Drive.');
      }
      final value = jsonDecode(response.body) as Map<String,dynamic>;
      if (value['schema'] != 1 || value['documents'] is! List) {
        throw const FormatException('Nieznany format indeksu w chmurze.');
      }
      for (final item in (value['documents'] as List)) {
        if (item is Map) {
          final record = LocalArchiveRecord.fromMap(
            item.map((k,v)=>MapEntry(k.toString(),v)));
          if (record.id.isNotEmpty && record.hasDrivePdf) remote[record.id] = record;
        }
      }
    }
    final local = await LocalArchiveStore.list();
    // Never upload old embedded local PDFs to the JSON index.
    final merged = <String,LocalArchiveRecord>{...remote};
    for (final record in local.where((r)=>r.hasDrivePdf)) {
      merged[record.id] = record;
    }
    // Persist cloud backup BEFORE adding remote items locally.
    final payload = jsonEncode({
      'schema':1,
      'updatedAt':DateTime.now().toUtc().toIso8601String(),
      'documents':merged.values.map((r)=>r.toMap()).toList(),
    });
    final url = existingId == null
      ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id')
      : Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$existingId?uploadType=media');
    http.Response response;
    if (existingId == null) {
      final boundary = 'smart_index_boundary';
      final body = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode({'name':_fileName,'mimeType':'application/json'})}\r\n'
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
          '$payload\r\n--$boundary--';
      response = await client.post(url,headers:{
        ...headers,'Content-Type':'multipart/related; boundary=$boundary',
      },body:utf8.encode(body)).timeout(const Duration(seconds: 20));
    } else {
      response = await client.patch(url,headers:{
        ...headers,'Content-Type':'application/json; charset=UTF-8',
      },body:payload).timeout(const Duration(seconds: 20));
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Google Drive HTTP ${response.statusCode} (zapis indeksu)');
    }
    var restored = 0;
    final localIds = local.map((r)=>r.id).toSet();
    for (final record in remote.values) {
      if (!localIds.contains(record.id)) {
        await LocalArchiveStore.save(record);
        restored++;
      }
    }
    return restored;
  }
}
