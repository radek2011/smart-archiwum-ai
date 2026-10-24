import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'drive_auth.dart';

class DriveUploader {
  static String _clientIdThisSession = '';
  static Future<String?> uploadWithConsent(BuildContext context, {
    required Uint8List pdf,
    required String title,
    required String date,
    required String category,
  }) async {
    final clientController = TextEditingController(text: _clientIdThisSession);
    final completion = Completer<String?>();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Zapisz PDF na Dysku Google'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Po zalogowaniu Google dokument PDF zostanie '
                'przesłany do Smart Archiwum AI / wybrana kategoria. '
                'Ta wersja nie synchronizuje jeszcze archiwum.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('googleClientId'),
                controller: clientController,
                decoration: const InputDecoration(
                  labelText: 'Google OAuth Client ID',
                  hintText: '...apps.googleusercontent.com',
                  border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text('Wpisz identyfikator klienta aplikacji web '
                'z Google Cloud, a nie klucz API Gemini. '
                'Nie wpisuj hasła Google.'),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Anuluj')),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Połącz i wyślij'),
              onPressed: () {
                final id = clientController.text.trim();
                if (!id.endsWith('.apps.googleusercontent.com')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(
                      'Wprowadź poprawny OAuth Client ID z Google Cloud.')));
                  return;
                }
                // Authorization runs in the direct user-click stack so
                // mobile browsers can open Google consent.
                _clientIdThisSession = id;
                final authorization = authorizeDrive(id);
                Navigator.pop(dialogContext);
                _finishUpload(context, authorization, pdf, title, date, category)
                    .then((fileId) {
                      if (!completion.isCompleted) completion.complete(fileId);
                    });
              },
            ),
          ],
        ),
      );
    } finally {
      clientController.dispose();
    }
    if (!completion.isCompleted) completion.complete(null);
    return completion.future;
  }

  static Future<String?> _finishUpload(
    BuildContext context,
    Future<String> authorization,
    Uint8List pdf,
    String title,
    String date,
    String category,
  ) async {
    try {
      final token = await authorization;
      final client = http.Client();
      try {
        final rootId = await _findOrCreateFolder(
          client, token, 'Smart Archiwum AI', 'root');
        final categoryName = _allowedCategory(category);
        final categoryId = await _findOrCreateFolder(
          client, token, categoryName, rootId);
        final fileId = await _uploadPdf(client, token, pdf, title, date, categoryId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF zapisany w Google Drive: Smart Archiwum AI / ' +
              _allowedCategory(category)),
            duration: const Duration(seconds: 8)));
        }
        return fileId;
      } finally {
        client.close();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nie udało się wysłać PDF: ' + error.toString()),
          duration: const Duration(seconds: 12)));
      }
    }
  }

  static String _allowedCategory(String value) {
    const categories = [
      'Umowy', 'Faktury', 'Korespondencja', 'Notatki',
      'Dokumenty firmowe', 'Inne',
    ];
    return categories.contains(value) ? value : 'Inne';
  }

  // drive.file scope permits access to folders created by this app.
  // Query parent+name to avoid mixing files across categories.
  static Future<String> _findOrCreateFolder(
    http.Client client, String token, String folderName, String parentId,
  ) async {
    final escapedName = folderName
        .replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final query = "name = '$escapedName' and " +
      "mimeType = 'application/vnd.google-apps.folder' and " +
      "'$parentId' in parents and trashed = false";
    final listUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': query,
      'spaces': 'drive',
      'fields': 'nextPageToken,files(id,name,parents)',
      'pageSize': '100',
    });
    final response = await client.get(listUri,
      headers: {'Authorization': 'Bearer $token'}).timeout(
        const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Wyszukiwanie folderów: Google Drive HTTP ' +
        response.statusCode.toString());
    }
    final result = jsonDecode(response.body);
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Niepoprawna odpowiedź Google Drive');
    }
    final files = result['files'];
    if (files is List && files.isNotEmpty) {
      final first = files.first;
      if (first is Map && first['id'] is String) {
        return first['id'] as String;
      }
    }
    final created = await client.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentId],
      }),
    ).timeout(const Duration(seconds: 30));
    if (created.statusCode != 200 && created.statusCode != 201) {
      throw Exception('Tworzenie folderu: Google Drive HTTP ' +
        created.statusCode.toString());
    }
    final data = jsonDecode(created.body);
    if (data is! Map || data['id'] is! String) {
      throw const FormatException('Google nie zwrócił ID folderu');
    }
    return data['id'] as String;
  }

  static Future<String> _uploadPdf(
    http.Client client, String token, Uint8List pdf,
    String title, String date, String categoryId,
  ) async {
      final safeTitle = title.trim().isEmpty ? 'Dokument' : title.trim();
      final fileName = date + '_' +
        safeTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_') + '.pdf';
      final boundary = 'smart_archive_pdf_' +
        DateTime.now().millisecondsSinceEpoch.toString();
      final metadata = jsonEncode({
        'name': fileName,
        'mimeType': 'application/pdf',
        'description': 'Smart Archiwum AI - dokument użytkownika',
        'parents': [categoryId],
      });
      final header = utf8.encode('--' + boundary +
          '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' +
          metadata + '\r\n--' + boundary +
          '\r\nContent-Type: application/pdf\r\n\r\n');
      final trailer = utf8.encode('\r\n--' + boundary + '--');
      final body = Uint8List.fromList([...header, ...pdf, ...trailer]);
      final req = http.Request('POST', Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=multipart&fields=id,name,webViewLink'));
      req.headers['Authorization'] = 'Bearer ' + token;
      req.headers['Content-Type'] = 'multipart/related; boundary=' + boundary;
      req.bodyBytes = body;
      final streamed = await client.send(req).timeout(
        const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Google Drive HTTP ' +
          response.statusCode.toString() + '. ' +
          'Sprawdź uprawnienia OAuth oraz włączenie Drive API.');
      }
      final parsed = jsonDecode(response.body);
      if (parsed is! Map || parsed['id'] is! String) {
        throw const FormatException('Google Drive nie zwrócił ID przesłanego pliku');
      }
      return parsed['id'] as String;
    }
}
