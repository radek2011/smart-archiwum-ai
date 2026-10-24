import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'drive_auth.dart';

class DriveUploader {
  static Future<void> uploadWithConsent(BuildContext context, {
    required Uint8List pdf,
    required String title,
    required String date,
  }) async {
    final clientController = TextEditingController();
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
                'przesłany do folderu Mój dysk wybranego konta. '
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
                final authorization = authorizeDrive(id);
                Navigator.pop(dialogContext);
                _finishUpload(context, authorization, pdf, title, date);
              },
            ),
          ],
        ),
      );
    } finally {
      clientController.dispose();
    }
  }

  static Future<void> _finishUpload(
    BuildContext context,
    Future<String> authorization,
    Uint8List pdf,
    String title,
    String date,
  ) async {
    try {
      final token = await authorization;
      final safeTitle = title.trim().isEmpty ? 'Dokument' : title.trim();
      final fileName = date + '_' +
        safeTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_') + '.pdf';
      final boundary = 'smart_archive_pdf_' +
        DateTime.now().millisecondsSinceEpoch.toString();
      final metadata = jsonEncode({
        'name': fileName,
        'mimeType': 'application/pdf',
        'description': 'Smart Archiwum AI - dokument użytkownika',
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
      final client = http.Client();
      late http.Response response;
      try {
        final streamed = await client.send(req).timeout(
          const Duration(seconds: 60));
        response = await http.Response.fromStream(streamed);
      } finally {
        client.close();
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Google Drive HTTP ' +
          response.statusCode.toString() + '. ' +
          'Sprawdź uprawnienia OAuth oraz włączenie Drive API.');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PDF zapisany na Dysku Google. '
            'Sprawdź folder Mój dysk.'),
          duration: Duration(seconds: 8)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nie udało się wysłać PDF: ' + error.toString()),
          duration: const Duration(seconds: 12)));
      }
    }
  }
}
