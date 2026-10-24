import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'local_archive_store.dart';

class LocalArchivePage extends StatefulWidget {
  const LocalArchivePage({super.key});
  @override
  LocalArchivePageState createState() => LocalArchivePageState();
}

class LocalArchivePageState extends State<LocalArchivePage> {
  List<LocalArchiveRecord> documents = [];
  bool busy = true;
  String? error;
  String query = '';

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (mounted) setState(() { busy = true; error = null; });
    try {
      final result = await LocalArchiveStore.list();
      if (mounted) setState(() => documents = result);
    } catch (_) {
      if (mounted) setState(() => error =
          'Nie udało się otworzyć lokalnego archiwum w tej przeglądarce.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openPdf(LocalArchiveRecord doc) async {
    try {
      await Printing.sharePdf(
        bytes: doc.pdfBytes,
        filename: doc.date + '_' + doc.id + '.pdf',
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć PDF.')));
    }
  }

  Future<void> remove(LocalArchiveRecord doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć dokument z archiwum?'),
        content: Text('Usuniesz lokalną kopię: ' + doc.title +
          '. Tej operacji nie można cofnąć.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LocalArchiveStore.delete(doc.id);
      await reload();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się usunąć dokumentu.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = documents.where((doc) =>
      (doc.title + ' ' + doc.category + ' ' + doc.date)
          .toLowerCase().contains(query.toLowerCase())).toList();
    return ListView(
      key: const Key('localArchivePage'),
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Archiwum', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          color: Color(0xFF101F43))),
        const SizedBox(height: 8),
        const Text('Dokumenty zapisane lokalnie w tej przeglądarce. '
          'Nie są synchronizowane z Google Drive ani innymi urządzeniami.'),
        const SizedBox(height: 12),
        const Text('UWAGA: wyczyszczenie danych przeglądarki, tryb prywatny '
          'lub brak miejsca mogą usunąć dokumenty. Zachowuj również kopie PDF '
          'poza aplikacją. To jeszcze nie jest archiwum firmowe.',
          style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
        const SizedBox(height: 14),
        TextField(
          key: const Key('localArchiveSearch'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Szukaj według nazwy, daty lub kategorii',
            border: OutlineInputBorder()),
          onChanged: (text) => setState(() => query = text),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Zapisane: ' + documents.length.toString()),
          const Spacer(),
          TextButton.icon(
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh),
            label: const Text('Odśwież')),
        ]),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (!busy && error == null && found.isEmpty)
          const Padding(padding: EdgeInsets.all(30),
            child: Center(child: Text('Brak zapisanych dokumentów. '
              'W zakładce Skanuj wybierz Zapisz w archiwum.'))),
        for (final doc in found)
          Card(child: ListTile(
            leading: const Icon(Icons.picture_as_pdf,
              color: Color(0xFFF36B21)),
            title: Text(doc.title),
            subtitle: Text(doc.category + ' • ' + doc.date + ' • ' +
              (doc.size / 1048576).toStringAsFixed(2) + ' MB'),
            onTap: () => openPdf(doc),
            trailing: IconButton(
              tooltip: 'Usuń z archiwum',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => remove(doc)),
          )),
      ],
    );
  }
}
