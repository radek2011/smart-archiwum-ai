import 'dart:typed_data';
import 'document_processor.dart';
import 'manual_crop_page.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _PagePhoto {
  _PagePhoto(this.bytes, this.width, this.height);
  Uint8List? corrected;
  Uint8List get displayed => corrected ?? bytes;
  final Uint8List bytes;
  final int width;
  final int height;
}

class _ScanPageState extends State<ScanPage> {
  final ImagePicker picker = ImagePicker();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController dateController = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10));
  String category = 'Inne';
  static const categories = <String>[
    'Umowy', 'Faktury', 'Korespondencja', 'Notatki',
    'Dokumenty firmowe', 'Inne',
  ];

  @override
  void dispose() {
    titleController.dispose();
    dateController.dispose();
    super.dispose();
  }

  String safePart(String text) {
    final normalized = text.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ _-]'), '');
    final compact = normalized.replaceAll(RegExp(r'\\s+'), '_');
    return compact.isEmpty ? 'Dokument' : compact.substring(
      0, compact.length > 55 ? 55 : compact.length);
  }

  Future<void> selectDocumentDate() async {
    final initial = DateTime.tryParse(dateController.text) ?? DateTime.now();
    final chosen = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(1990), lastDate: DateTime(2100));
    if (chosen != null && mounted) {
      setState(() => dateController.text =
          chosen.toIso8601String().substring(0, 10));
    }
  }
  final List<_PagePhoto> pages = [];
  int selected = 0;
  bool busy = false;
  String progress = '';
  static const navy = Color(0xFF101F43);
  static const orange = Color(0xFFF36B21);

  String size(int bytes) => bytes < 1048576
      ? (bytes / 1024).toStringAsFixed(0) + ' KB'
      : (bytes / 1048576).toStringAsFixed(2) + ' MB';

  Future<_PagePhoto> optimize(XFile file) async {
    final raw = await file.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) throw const FormatException('Nieobsługiwany format');
    final upright = img.bakeOrientation(decoded);
    final longest = upright.width > upright.height ? upright.width : upright.height;
    var target = upright;
    if (longest > 2800) {
      final factor = 2800 / longest;
      target = img.copyResize(upright,
        width: (upright.width * factor).round(),
        height: (upright.height * factor).round(),
        interpolation: img.Interpolation.average);
    }
    return _PagePhoto(
      Uint8List.fromList(img.encodeJpg(target, quality: 88)),
      target.width, target.height);
  }

  Future<void> addPhotos(bool camera) async {
    if (busy) return;
    setState(() { busy = true; progress = 'Wybieranie zdjęcia…'; });
    try {
      final List<XFile> photos;
      if (camera) {
        final photo = await picker.pickImage(source: ImageSource.camera,
          maxWidth: 2800, maxHeight: 2800, imageQuality: 92);
        photos = photo == null ? [] : [photo];
      } else {
        photos = await picker.pickMultiImage(
          maxWidth: 2800, maxHeight: 2800, imageQuality: 92);
      }
      var errors = 0;
      for (var i = 0; i < photos.length; i++) {
        if (!mounted) return;
        if (pages.length >= 30) {
          message('Limit 30 stron w jednym dokumencie.');
          break;
        }
        setState(() => progress = 'Optymalizacja ' +
            (i + 1).toString() + ' / ' + photos.length.toString());
        try {
          final page = await optimize(photos[i]);
          if (!mounted) return;
          setState(() { pages.add(page); selected = pages.length - 1; });
        } catch (_) {
          errors++;
        }
      }
      if (mounted && errors > 0) {
        message('Nie udało się odczytać ' + errors.toString() +
          ' zdjęć. Spróbuj z plikami JPG lub PNG.');
      }
    } catch (e) {
      if (mounted) message('Problem z aparatem lub galerią: ' + e.toString());
    } finally {
      if (mounted) setState(() { busy = false; progress = ''; });
    }
  }

  void message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  void move(int offset) {
    final next = selected + offset;
    if (next < 0 || next >= pages.length) return;
    setState(() {
      final page = pages.removeAt(selected);
      pages.insert(next, page);
      selected = next;
    });
  }

  void remove() {
    setState(() {
      pages.removeAt(selected);
      if (selected >= pages.length) {
        selected = pages.isEmpty ? 0 : pages.length - 1;
      }
    });
  }

  Future<void> correctSelected() async {
    if (busy || pages.isEmpty) return;
    final originalPage = pages[selected];
    setState(() {
      busy = true;
      progress = 'Bezpieczne wykrywanie całej kartki…';
    });
    try {
      final result = deskewDocument(originalPage.bytes);
      if (!mounted) return;
      if (result == null) {
        message('Nie udało się pewnie wykryć całej kartki. Zachowano oryginał. '
          'Spróbuj fotografować na ciemnym, jednolitym tle.');
        return;
      }
      final apply = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Porównaj skan z korektą'),
          content: SizedBox(
            width: 440,
            child: ListView(shrinkWrap: true, children: [
              const Text('Oryginał', style: TextStyle(
                fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Image.memory(originalPage.bytes, height: 240,
                fit: BoxFit.contain),
              const SizedBox(height: 12),
              const Text('Bezpieczne kadrowanie (wersja 0.4.1)',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Image.memory(result, height: 240, fit: BoxFit.contain),
              const SizedBox(height: 8),
              const Text('Sprawdź, czy nie obcięto tekstu, podpisów lub pieczątek.',
                style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Zachowaj oryginał')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Zastosuj korektę')),
          ],
        ),
      );
      if (!mounted) return;
      if (apply == true && pages.contains(originalPage)) {
        setState(() => originalPage.corrected = result);
        message('Korekta zastosowana. Oryginał pozostał do przywrócenia.');
      }
    } catch (e) {
      if (mounted) message('Korekta nie powiodła się: $e');
    } finally {
      if (mounted) setState(() { busy = false; progress = ''; });
    }
  }

  Future<void> cropSelectedManually() async {
    if (busy || pages.isEmpty) return;
    final selectedPage = pages[selected];
    final corrected = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => ManualCropPage(source: selectedPage.bytes),
      ),
    );
    if (!mounted || corrected == null || !pages.contains(selectedPage)) return;
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zatwierdź ręczne kadrowanie'),
        content: SizedBox(
          width: 440,
          child: ListView(shrinkWrap: true, children: [
            const Text('Przed', style: TextStyle(fontWeight: FontWeight.bold)),
            Image.memory(selectedPage.bytes, height: 180, fit: BoxFit.contain),
            const SizedBox(height: 10),
            const Text('Po', style: TextStyle(fontWeight: FontWeight.bold)),
            Image.memory(corrected, height: 280, fit: BoxFit.contain),
            const SizedBox(height: 8),
            const Text('Upewnij się, że tekst i podpisy nie zostały ucięte.'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Wróć bez zmian')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Zastosuj korektę')),
        ],
      ),
    );
    if (!mounted) return;
    if (apply == true && pages.contains(selectedPage)) {
      setState(() => selectedPage.corrected = corrected);
      message('Kadrowanie zastosowane. Możesz przywrócić oryginał.');
    }
  }

  void restoreOriginal() {
    if (pages.isEmpty || busy) return;
    setState(() => pages[selected].corrected = null);
    message('Przywrócono oryginalny skan.');
  }

  void rotateSelected() {
    if (busy || pages.isEmpty) return;
    final original = img.decodeJpg(pages[selected].displayed);
    if (original == null) {
      message('Nie można obrócić tej strony.');
      return;
    }
    final rotated = img.copyRotate(original, angle: 90);
    final data = Uint8List.fromList(img.encodeJpg(rotated, quality: 88));
    setState(() => pages[selected] =
        _PagePhoto(data, rotated.width, rotated.height));
  }

  Future<void> exportPdf() async {
    if (busy || pages.isEmpty) return;
    setState(() { busy = true; progress = 'Tworzenie pliku PDF…'; });
    try {
      final documentTitle = titleController.text.trim().isEmpty
          ? 'Skan dokumentu' : titleController.text.trim();
      final document = pw.Document(
        compress: true, title: documentTitle,
        author: 'Smart Archiwum AI – RentSide',
        subject: category,
      );
      for (final page in pages) {
        final photo = pw.MemoryImage(page.displayed);
        document.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (context) => pw.Center(
            child: pw.Image(photo, fit: pw.BoxFit.contain),
          ),
        ));
      }
      final bytes = await document.save();
      if (!mounted) return;
      final documentDate = DateTime.tryParse(dateController.text)
          ?.toIso8601String().substring(0, 10) ??
          DateTime.now().toIso8601String().substring(0, 10);
      final fileName = '${documentDate}_${safePart(category)}_'
          '${safePart(documentTitle)}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      if (mounted) message('PDF przygotowany. Zapisz go z menu telefonu.');
    } catch (e) {
      if (mounted) message('Nie udało się utworzyć PDF: $e');
    } finally {
      if (mounted) setState(() { busy = false; progress = ''; });
    }
  }

  void preview() {
    Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('Strona ' + (selected + 1).toString())),
        body: InteractiveViewer(
          minScale: 0.7, maxScale: 6,
          child: Center(child: Image.memory(
            pages[selected].displayed, fit: BoxFit.contain)),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = pages.fold<int>(0, (sum, item) => sum + item.displayed.length);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Nowy skan', style: TextStyle(fontSize: 25,
        fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 8),
      const Text('Fotografuj kolejne strony lub wybierz kilka zdjęć z galerii. '
        'Każda strona zostanie zoptymalizowana do czytelnego JPEG.'),
      const SizedBox(height: 18),
      const Text('Opis dokumentu', style: TextStyle(
        fontSize: 17, fontWeight: FontWeight.bold, color: navy)),
      const SizedBox(height: 8),
      TextField(
        key: const Key('documentTitle'),
        controller: titleController,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Nazwa dokumentu',
          hintText: 'np. Umowa najmu',
          border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: const Key('documentCategory'),
        initialValue: category,
        decoration: const InputDecoration(
          labelText: 'Kategoria', border: OutlineInputBorder()),
        items: categories.map((value) => DropdownMenuItem<String>(
          value: value, child: Text(value))).toList(),
        onChanged: busy ? null : (value) {
          if (value != null) setState(() => category = value);
        },
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('documentDate'),
        controller: dateController,
        readOnly: true,
        onTap: selectDocumentDate,
        decoration: InputDecoration(
          labelText: 'Data dokumentu',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Wybierz datę',
            onPressed: selectDocumentDate,
            icon: const Icon(Icons.calendar_month_outlined)),
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        key: const Key('cameraButton'),
        onPressed: busy ? null : () => addPhotos(true),
        style: FilledButton.styleFrom(backgroundColor: navy,
          padding: const EdgeInsets.symmetric(vertical: 16)),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Zrób zdjęcie strony')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('galleryButton'),
        onPressed: busy ? null : () => addPhotos(false),
        style: OutlinedButton.styleFrom(foregroundColor: navy,
          padding: const EdgeInsets.symmetric(vertical: 16)),
        icon: const Icon(Icons.photo_library_outlined, color: orange),
        label: const Text('Dodaj z galerii')),
      if (busy) ...[
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
        Text(progress, textAlign: TextAlign.center),
      ],
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: Text('Strony: ' + pages.length.toString(),
          style: const TextStyle(color: navy, fontWeight: FontWeight.bold,
            fontSize: 18))),
        Text(size(total), style: const TextStyle(color: navy)),
      ]),
      const SizedBox(height: 12),
      if (pages.isEmpty)
        Container(
          padding: const EdgeInsets.all(35),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
          child: const Column(children: [
            Icon(Icons.document_scanner_outlined, size: 62, color: orange),
            SizedBox(height: 12),
            Text('Dodaj pierwszą stronę', textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text('Zdjęcia nie są wysyłane do chmury.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          ]),
        )
      else ...[
        Card(color: Colors.white, clipBehavior: Clip.antiAlias,
          child: Column(children: [
            InkWell(onTap: preview,
              child: SizedBox(width: double.infinity, height: 350,
                child: Image.memory(pages[selected].displayed,
                  key: ValueKey(pages[selected].displayed),
                  fit: BoxFit.contain))),
            Padding(padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text((pages[selected].corrected == null ? 'Oryginał • ' : 'Po korekcie • ') +
                  'Strona ' + (selected + 1).toString() +
                  ' z ' + pages.length.toString() + ' • ' +
                  pages[selected].width.toString() + '×' +
                  pages[selected].height.toString() + ' px • ' +
                  size(pages[selected].displayed.length),
                  textAlign: TextAlign.center),
                const Text('Dotknij zdjęcia, aby powiększyć',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
                Wrap(alignment: WrapAlignment.center, children: [
                  IconButton(tooltip: 'Poprzednia',
                    onPressed: selected > 0
                      ? () => setState(() => selected--) : null,
                    icon: const Icon(Icons.chevron_left)),
                  IconButton(tooltip: 'Przesuń wcześniej',
                    onPressed: selected > 0 ? () => move(-1) : null,
                    icon: const Icon(Icons.arrow_back)),
                  IconButton(tooltip: 'Automatyczna korekta',
                    onPressed: busy ? null : correctSelected,
                    icon: const Icon(Icons.auto_fix_high)),
                  IconButton(tooltip: 'Kadruj ręcznie',
                    onPressed: busy ? null : cropSelectedManually,
                    icon: const Icon(Icons.crop_free)),
                  IconButton(tooltip: 'Przywróć oryginał',
                    onPressed: !busy && pages[selected].corrected != null
                      ? restoreOriginal : null,
                    icon: const Icon(Icons.settings_backup_restore)),
                  IconButton(tooltip: 'Obróć o 90 stopni',
                    onPressed: busy ? null : rotateSelected,
                    icon: const Icon(Icons.rotate_right)),
                  IconButton(tooltip: 'Usuń',
                    onPressed: remove,
                    icon: const Icon(Icons.delete_outline, color: Colors.red)),
                  IconButton(tooltip: 'Przesuń później',
                    onPressed: selected + 1 < pages.length
                      ? () => move(1) : null,
                    icon: const Icon(Icons.arrow_forward)),
                  IconButton(tooltip: 'Następna',
                    onPressed: selected + 1 < pages.length
                      ? () => setState(() => selected++) : null,
                    icon: const Icon(Icons.chevron_right)),
                ]),
              ])),
          ])),
        SizedBox(height: 85,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => InkWell(
              onTap: () => setState(() => selected = i),
              child: Container(width: 65, clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: i == selected
                      ? orange : Colors.grey.shade300,
                    width: i == selected ? 3 : 1),
                  borderRadius: BorderRadius.circular(8)),
                child: Image.memory(pages[i].displayed,
                  key: ValueKey(pages[i].displayed), fit: BoxFit.cover)),
            ),
          )),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('exportPdfButton'),
          onPressed: busy ? null : exportPdf,
          style: FilledButton.styleFrom(backgroundColor: navy,
            padding: const EdgeInsets.symmetric(vertical: 16)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Utwórz i zapisz PDF')),
        const SizedBox(height: 10),
        const Text('Wersja 0.4.2: ostrożne kadrowanie na kontrastowym tle; '
          'bez automatycznej korekcji perspektywy. '
          'Zawsze sprawdź podgląd przed zatwierdzeniem. '
          'Skany są tylko w pamięci. '
          'Odświeżenie lub zamknięcie strony usuwa je. '
          'Zapisz wyeksportowany PDF na telefonie. '
          'OCR, ręczna korekta narożników i Drive będą rozwijane później.',
          style: TextStyle(color: Colors.redAccent, fontSize: 12)),
      ],
    ]);
  }
}
