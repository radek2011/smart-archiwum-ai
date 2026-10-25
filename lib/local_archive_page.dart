import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'local_archive_store.dart';
import 'drive_uploader.dart';
import 'drive_open.dart';
import 'drive_index_sync.dart';

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
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  static String _normalize(String value) {
    const accents = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
    const plain = 'acelnoszzACELNOSZZ';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final index = accents.indexOf(char);
      buffer.write(index < 0 ? char.toLowerCase() : plain[index].toLowerCase());
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _terms(String value) =>
      _normalize(value).split(' ').where((term) => term.isNotEmpty).toList();

  bool _matches(LocalArchiveRecord doc) {
    final content = _normalize([
      doc.title, doc.category, doc.date, doc.summary, doc.extractedText,
    ].join(' '));
    return _terms(query).every(content.contains);
  }

  void setSearchQuery(String value) {
    if (!mounted) return;
    searchController.text = value;
    setState(() => query = value);
  }

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

  Future<void> syncIndex() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final restored = await DriveIndexSync.syncWithConsent(context);
      if (!mounted) return;
      if (restored != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Indeks zsynchronizowany. Przywrócono $restored wpisów.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Błąd synchronizacji: $e')));
    } finally {
      await reload();
    }
  }

  Future<void> openPdf(LocalArchiveRecord doc) async {
    if (doc.hasDrivePdf) {
      openDriveFile(doc.driveFileId);
      return;
    }
    if (!doc.hasLegacyLocalPdf) return;
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

  Future<void> moveLegacyToDrive(LocalArchiveRecord doc) async {
    if (!doc.hasLegacyLocalPdf) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Przenieść starszy PDF na Google Drive?'),
        content: const Text('Plik zostanie wysłany na Drive. '
          'Dopiero po potwierdzeniu wysłania usuniemy jego lokalną '
          'kopię z bazy przeglądarki. Jeśli wcześniej przesłałeś ten '
          'dokument ręcznie, na Drive może powstać duplikat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Wyślij na Drive')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final fileId = await DriveUploader.uploadWithConsent(
      context, pdf: doc.pdfBytes, title: doc.title,
      date: doc.date, category: doc.category);
    if (fileId == null) return;
    try {
      await LocalArchiveStore.save(LocalArchiveRecord(
        id: doc.id,
        title: doc.title,
        category: doc.category,
        date: doc.date,
        createdAt: doc.createdAt,
        driveFileId: fileId,
        summary: doc.summary,
        extractedText: doc.extractedText,
      ));
      await reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Przeniesiono na Drive. '
          'Lokalna kopia PDF została usunięta.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF jest na Drive, '
          'ale lokalny wpis nie został zaktualizowany.')));
    }
  }

  Future<void> remove(LocalArchiveRecord doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć dokument z archiwum?'),
        content: Text('Usuniesz wpis z indeksu: ' + doc.title +
          '. Plik na Google Drive NIE zostanie usunięty. '
          'Starsza kopia PDF zapisana lokalnie zostanie usunięta razem z wpisem.'),
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

  Widget _matchingExcerpt(LocalArchiveRecord doc) {
    final term = query.trim();
    final words = _terms(term);
    if (term.isEmpty) {
      return doc.summary.isEmpty ? const SizedBox.shrink()
          : Text(doc.summary, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final sources = [doc.extractedText, doc.summary, doc.title, doc.category];
    String source = '';
    int at = -1;
    for (final candidate in sources) {
      at = candidate.toLowerCase().indexOf(term.toLowerCase());
      if (at < 0 && words.isNotEmpty) {
        at = _normalize(candidate).indexOf(words.first);
      }
      if (at >= 0) {
        source = candidate;
        break;
      }
    }
    if (at < 0) return const SizedBox.shrink();
    final begin = at > 72 ? at - 72 : 0;
    final end = at + term.length + 95 < source.length
        ? at + term.length + 95 : source.length;
    final segment = source.substring(begin, end)
        .replaceAll(RegExp(r'\\s+'), ' ');
    final highlighted = segment.toLowerCase().contains(term.toLowerCase())
        ? term : (words.isNotEmpty ? words.first : term);
    final inSegment = segment.toLowerCase().indexOf(highlighted);
    if (inSegment < 0) return Text(segment);
    return Text.rich(TextSpan(children: [
      TextSpan(text: begin > 0 ? '…' : ''),
      TextSpan(text: segment.substring(0, inSegment)),
      TextSpan(
        text: segment.substring(inSegment, inSegment + highlighted.length),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0xFFFFE4AA),
          color: Colors.black87,
        ),
      ),
      TextSpan(text: segment.substring(inSegment + highlighted.length)),
      TextSpan(text: end < source.length ? '…' : ''),
    ]), maxLines: 4, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final found = documents.where(_matches).toList();
    return ListView(
      key: const Key('localArchivePage'),
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Archiwum', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          color: Color(0xFF101F43))),
        const SizedBox(height: 8),
        const Text('Nowe dokumenty są przechowywane wyłącznie na Google Drive. '
          'Tutaj zostaje lokalny indeks nazw, kategorii i tekstu OCR. '
          'Starsze lokalne PDF-y możesz pojedynczo przenieść na Drive.'),
        const SizedBox(height: 12),
        const Text('Bez synchronizacji wyczyszczenie przeglądarki usunie lokalny indeks '
          'wyszukiwania, nie PDF-y już przesłane na Drive. '
          'Użyj przycisku Synchronizuj, aby wykonać kopię indeksu na Drive. '
          'Starsze lokalne PDF-y pozostają na urządzeniu do ręcznego przeniesienia.',

          style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : syncIndex,
          icon: const Icon(Icons.sync), label: const Text('Synchronizuj indeks z Google Drive')),
        const SizedBox(height: 14),
        TextField(
          key: const Key('localArchiveSearch'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Szukaj po nazwie, opisie lub treści',
            hintText: 'np. faktura energia październik',
            border: OutlineInputBorder()),
          controller: searchController,
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
              'W zakładce Skanuj wybierz Zapisz na Google Drive.'))),
        for (final doc in found)
          Card(child: ListTile(
            leading: const Icon(Icons.picture_as_pdf,
              color: Color(0xFFF36B21)),
            title: Text(doc.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.category + ' • ' + doc.date + ' • ' +
                  (doc.hasDrivePdf ? 'Google Drive' : 'Starszy PDF lokalny') +
                  (doc.extractedText.isNotEmpty ? ' • OCR' : ' • bez OCR')),
                const SizedBox(height: 5),
                _matchingExcerpt(doc),
              ],
            ),
            onTap: () => openPdf(doc),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: doc.hasDrivePdf
                  ? 'Otwórz PDF na Dysku Google'
                  : 'Przenieś lokalny PDF na Google Drive',
                icon: Icon(doc.hasDrivePdf
                  ? Icons.open_in_new : Icons.cloud_upload_outlined),
                onPressed: () => doc.hasDrivePdf
                  ? openPdf(doc) : moveLegacyToDrive(doc)),
              IconButton(
                tooltip: 'Usuń z archiwum',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => remove(doc)),
            ]),
          )),
      ],
    );
  }
}
