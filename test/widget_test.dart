import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_archiwum_ai/main.dart';

void main() {
  testWidgets('Ekran startowy i nawigacja działają', (tester) async {
    await tester.pumpWidget(const SmartArchiveApp());
    expect(find.text('Smart Archiwum AI'), findsOneWidget);
    expect(find.byKey(const Key('newScan')), findsOneWidget);
    await tester.tap(find.byKey(const Key('newScan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cameraButton')), findsOneWidget);
    expect(find.byKey(const Key('galleryButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
