import 'scan_page.dart';
import 'local_archive_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const SmartArchiveApp());

const navy = Color(0xFF101F43);
const orange = Color(0xFFF36B21);
const canvasColor = Color(0xFFF7F8FB);

class SmartArchiveApp extends StatelessWidget {
  const SmartArchiveApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smart Archiwum AI',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy),
      scaffoldBackgroundColor: canvasColor,
    ),
    home: const ArchiveHome(),
  );
}

class ArchiveHome extends StatefulWidget {
  const ArchiveHome({super.key});
  @override
  State<ArchiveHome> createState() => _ArchiveHomeState();
}

class _ArchiveHomeState extends State<ArchiveHome> {
  int selected = 0;
  final archiveKey = GlobalKey<LocalArchivePageState>();
  String query = '';
  final search = TextEditingController();
  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(children: [
        Expanded(child: IndexedStack(index: selected, children: [
          _home(),
          ScanPage(onSaved: () => archiveKey.currentState?.reload()),
          LocalArchivePage(key: archiveKey),
          _settings(),
        ])),
      ]),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      indicatorColor: orange.withValues(alpha: .14),
      onDestinationSelected: (i) {
        setState(() => selected = i);
        if (i == 2) archiveKey.currentState?.reload();
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: orange), label: 'Start'),
        NavigationDestination(icon: Icon(Icons.document_scanner_outlined), label: 'Skanuj'),
        NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Archiwum'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ustawienia'),
      ],
    ),
  );

  Widget _heading(String text) => Text(text, style: const TextStyle(
      color: navy, fontSize: 22, fontWeight: FontWeight.w800));

  Widget _home() => ListView(
    key: const Key('homePage'),
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
    children: [
      Row(children: [
        const RentSideMark(),
        const Spacer(),
        IconButton(icon: const Icon(Icons.account_circle_outlined, color: navy),
          onPressed: () => setState(() => selected = 3)),
      ]),
      const SizedBox(height: 30),
      const Text('Smart Archiwum AI', style: TextStyle(
        fontSize: 29, fontWeight: FontWeight.w900, color: navy)),
      const SizedBox(height: 4),
      const Text('Skanuj, analizuj i archiwizuj dokumenty',
        style: TextStyle(color: Color(0xFF6D7690), fontSize: 14)),
      const SizedBox(height: 26),
      Row(children: [
        Expanded(child: FilledButton.icon(
          key: const Key('newScan'),
          style: FilledButton.styleFrom(backgroundColor: navy,
              padding: const EdgeInsets.symmetric(vertical: 17)),
          onPressed: () => setState(() => selected = 1),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Nowy skan'),
        )),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          key: const Key('searchButton'),
          style: OutlinedButton.styleFrom(foregroundColor: navy,
              padding: const EdgeInsets.symmetric(vertical: 17)),
          onPressed: () => setState(() => selected = 2),
          icon: const Icon(Icons.search, color: orange),
          label: const Text('Szukaj'),
        )),
      ]),
      const SizedBox(height: 22),
      TextField(
        key: const Key('homeSearch'),
        decoration: InputDecoration(
          hintText: 'Szukaj po nazwie, treści lub temacie',
          prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE1E5EE))),
        ),
        onSubmitted: (v) => setState(() {query = v; search.text = v; selected = 2;}),
      ),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _category('Umowy', Icons.description_outlined, const Color(0xFFEAF0FA))),
        const SizedBox(width: 8),
        Expanded(child: _category('Faktury', Icons.receipt_long_outlined, const Color(0xFFFFF0E8))),
        const SizedBox(width: 8),
        Expanded(child: _category('Notatki', Icons.article_outlined, const Color(0xFFFFF6EC))),
      ]),
      const SizedBox(height: 30),
      Row(children: [
        Expanded(child: _heading('Ostatnie dokumenty')),
        TextButton(onPressed: () => setState(() => selected = 2),
          child: const Text('Zobacz wszystkie', style: TextStyle(color: orange))),
      ]),
      const SizedBox(height: 8),
      const Text('PDF-y przechowujemy na Google Drive. '
        'Nazwy i tekst do wyszukiwania pozostają w lokalnym indeksie.',
        style: TextStyle(fontSize: 12, color: Color(0xFF81899B))),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() => selected = 2),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Otwórz indeks archiwum')),
    ],
  );

  Widget _category(String title, IconData icon, Color background) => InkWell(
    onTap: () => setState(() {query = title; search.text = title; selected = 2;}),
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(icon, color: title == 'Umowy' ? navy : orange, size: 27),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
      ]),
    ),
  );

  Widget _settings() => _subPage('Ustawienia', Icons.settings_outlined, [
    const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Google Drive'),
      subtitle: Text('Ręczny zapis PDF do Smart Archiwum AI na Drive')),
    const ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Gemini AI'),
      subtitle: Text('Analiza testowa przez Cloudflare dostępna w skanerze')),
    const ListTile(leading: Icon(Icons.lock_outline), title: Text('Bezpieczeństwo'),
      subtitle: Text('Klucze API nie są umieszczane w aplikacji')),
  ]);

  Widget _subPage(String title, IconData icon, List<Widget> children) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 66, color: orange),
        const SizedBox(height: 12),
        _heading(title),
        const SizedBox(height: 24),
        ...children,
      ]),
    ),
  );
}

// Vector approximation for the UI prototype; will be replaced with the
// user-provided original RentSide logo asset in a dedicated branding step.
class RentSideMark extends StatelessWidget {
  const RentSideMark({super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    ClipPath(
      clipper: _ArrowClipper(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 18, 6), color: navy,
        child: const Text('RENT', style: TextStyle(
          color: Colors.white, fontSize: 23, letterSpacing: -1,
          fontWeight: FontWeight.w900)),
      ),
    ),
    const SizedBox(width: 4),
    const Text('Side', style: TextStyle(
        color: orange, fontSize: 25, fontWeight: FontWeight.w700)),
  ]);
}

class _ArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)..lineTo(size.width - 13, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - 13, size.height)
    ..lineTo(0, size.height)..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
