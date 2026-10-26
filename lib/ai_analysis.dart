import 'dart:convert';
import 'session_store.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class AiSuggestion {
  const AiSuggestion(this.title, this.category, this.date, this.summary, this.extractedText);
  final String title, category, date, summary, extractedText;
}

class AiAnalysis {
  // In-memory only; disappears when the page reloads or tab is closed.
  static const serverUrl = 'https://smart-archiwum-ai.radek-f53.workers.dev';
  static String _sessionToken = readSessionValue('smart_ai_token') ?? '';
  static bool get configured => _sessionToken.isNotEmpty;
  static void clearSessionToken() {
    _sessionToken = '';
    removeSessionValue('smart_ai_token');
  }

  static Future<AiSuggestion?> run(
    BuildContext context, List<Uint8List> pages) async {
    if (pages.isEmpty) return null;
    if (pages.length > 5) {
      _notice(context, 'AI obsługuje do 5 stron na jeden test.');
      return null;
    }
    if (_sessionToken.isEmpty) {
      final input = TextEditingController();
      try {
        final entered = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Połącz Gemini na tę sesję'),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Adres serwera jest ustawiony automatycznie. '
                    'Wpisz token APP_ACCESS_TOKEN z Cloudflare tylko raz '
                    'na czas otwartej sesji. Zdjęcia zostaną wysłane do '
                    'Cloudflare i Gemini; nie używaj poufnych dokumentów.'),
                const SizedBox(height: 12),
                const SelectableText(serverUrl),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Token dostępu (nie klucz Gemini API)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Anuluj')),
              FilledButton(onPressed: () => Navigator.pop(
                  dialogContext, input.text.trim()),
                child: const Text('Połącz i analizuj')),
            ],
          ),
        );
        if (!context.mounted || entered == null) return null;
        if (entered.isEmpty) {
          _notice(context, 'Wprowadź token dostępu Cloudflare.');
          return null;
        }
        _sessionToken = entered;
        writeSessionValue('smart_ai_token', entered);
      } finally {
        input.dispose();
      }
    }
    final uri = Uri.parse(serverUrl);
    try {
      final images = <String>[];
      for (final bytes in pages) {
        final source = img.decodeImage(bytes);
        if (source == null) throw const FormatException('Niepoprawne zdjęcie');
        final longest = source.width > source.height
            ? source.width : source.height;
        final factor = longest > 1400 ? 1400 / longest : 1.0;
        final resized = factor < 1
            ? img.copyResize(source,
                width: (source.width * factor).round(),
                height: (source.height * factor).round())
            : source;
        images.add(base64Encode(img.encodeJpg(resized, quality: 78)));
      }
      final response = await http.post(uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + _sessionToken,
        },
        body: jsonEncode({'images': images}),
      ).timeout(const Duration(seconds: 55));
      if (response.statusCode != 200) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          clearSessionToken();
        }
        String detail = '';
        try {
          final payload = jsonDecode(response.body);
          if (payload is Map<String, dynamic>) {
            final provider = payload['providerStatus'];
            final reason = payload['error'];
            if (reason is String) detail = reason;
            if (provider is int) {
              detail += ' (Gemini HTTP ' + provider.toString() + ')';
            }
          }
        } catch (_) {
          // The Worker may return a non-JSON response.
        }
        throw Exception('Serwer HTTP ' + response.statusCode.toString() +
            (detail.isEmpty ? '' : ': ' + detail));
      }
      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Niepoprawna odpowiedź');
      }
      if (!context.mounted) return null;
      final result = AiSuggestion(
        (parsed['title'] ?? '').toString(),
        (parsed['category'] ?? 'Inne').toString(),
        (parsed['date'] ?? '').toString(),
        (parsed['summary'] ?? '').toString(),
        (parsed['extractedText'] ?? '').toString(),
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Propozycja AI'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nazwa: ' + result.title),
              Text('Kategoria: ' + result.category),
              Text('Data: ' + (result.date.isEmpty
                ? 'nieustalona' : result.date)),
              const SizedBox(height: 10),
              Text('Opis: ' + result.summary),
              const SizedBox(height: 8),
              Text('Tekst rozpoznany: ' + result.extractedText.length.toString() + ' znaków'),
              const SizedBox(height: 10),
              const Text('Sprawdź propozycję. AI może popełnić błędy.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Odrzuć')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Zastosuj dane')),
          ],
        ),
      );
      return confirmed == true ? result : null;
    } catch (e) {
      if (context.mounted) _notice(context,
        'Nie udało się wykonać analizy: ' + e.toString());
      return null;
    }
  }

  static void _notice(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 12)));
  }
}
