import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class AiSuggestion {
  const AiSuggestion(this.title, this.category, this.date, this.summary);
  final String title, category, date, summary;
}

class AiAnalysis {
  static Future<AiSuggestion?> run(
    BuildContext context, List<Uint8List> pages) async {
    if (pages.isEmpty) return null;
    if (pages.length > 5) {
      _notice(context, 'AI obsługuje do 5 stron na jeden test.');
      return null;
    }
    final endpoint = TextEditingController();
    final token = TextEditingController();
    final settings = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Analiza z Gemini — test'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Zdjęcia zostaną wysłane do Twojego serwera '
                'i do Gemini. Nie używaj poufnych dokumentów. '
                'Ta funkcja wymaga skonfigurowanego serwera.'),
            const SizedBox(height: 12),
            TextField(controller: endpoint, decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'Adres serwera HTTPS')),
            const SizedBox(height: 12),
            TextField(controller: token, obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Token dostępu')),
            const SizedBox(height: 8),
            const Text('Nie wpisuj klucza API Gemini. '
              'Konfiguracja nie jest zapisywana.',
              style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext,
              [endpoint.text.trim(), token.text.trim()]),
            child: const Text('Wyślij do analizy')),
        ],
      ),
    );
    if (!context.mounted || settings == null) return null;
    final uri = Uri.tryParse(settings[0]);
    if (uri == null || uri.scheme != 'https' ||
        uri.host.isEmpty || settings[1].isEmpty) {
      _notice(context, 'Podaj prawidłowy adres HTTPS i token.');
      return null;
    }
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
          'Authorization': 'Bearer ' + settings[1],
        },
        body: jsonEncode({'images': images}),
      ).timeout(const Duration(seconds: 55));
      if (response.statusCode != 200) {
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
