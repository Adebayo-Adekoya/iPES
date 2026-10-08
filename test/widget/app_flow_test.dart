import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/app/controller.dart';
import 'package:ipes/app/services.dart';
import 'package:ipes/app/shell.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/sample/builders.dart';
import 'package:xml/xml.dart';

class FakeFileService implements FileService {
  List<ImportedFile> toPick = [];
  final saved = <String, Uint8List>{};

  @override
  Future<List<ImportedFile>> pickFiles() async => toPick;

  @override
  Future<String?> saveFile(String fileName, Uint8List bytes, String mimeType) async {
    saved[fileName] = bytes;
    return 'Saved $fileName';
  }
}

Future<LibraryController> pumpApp(WidgetTester tester, Size size, {bool seed = false, FakeFileService? files}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = LibraryController(library: Library(), files: files ?? FakeFileService());
  await controller.start(seedSamples: seed);
  await tester.pumpWidget(IpesApp(controller: controller));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  final contract = ImportedFile(
    'contract_scan.pdf',
    PdfBuilder.build(
      title: 'Microsoft Word - final.docx',
      pages: [
        'Service Contract - Borehole Drilling\nThis contract is made between the client and Aqua Drillers.\n\n'
            'The contractor will drill a borehole and install a pump. Payment is made in two parts. '
            'Either party may cancel with fourteen days written notice.',
      ],
    ),
  );

  testWidgets('core flow on a phone: import → review → search → export', (tester) async {
    final files = FakeFileService()..toPick = [contract];
    final c = await pumpApp(tester, const Size(390, 844), files: files);
    expect(find.byKey(const Key('layout-compact')), findsOneWidget);

    // Import.
    await tester.tap(find.byKey(const Key('import-fab')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 drafted'), findsOneWidget);
    expect(c.drafts, hasLength(1));

    // Review: the title came from the first line, so it is highlighted; fix it and accept.
    await tester.tap(find.byKey(const Key('review-banner')));
    await tester.pumpAndSettle();
    final titleField = find.byKey(const Key('field-title'));
    expect(tester.widget<TextField>(titleField).controller!.text, 'Service Contract - Borehole Drilling');
    await tester.enterText(titleField, 'Borehole drilling contract');
    await tester.ensureVisible(find.byKey(const Key('accept-draft')));
    await tester.tap(find.byKey(const Key('accept-draft')));
    await tester.pumpAndSettle();
    expect(c.drafts, isEmpty);
    expect(c.records.single.title, 'Borehole drilling contract');

    // Importing the same file again is reported as a duplicate.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-fab')));
    await tester.pumpAndSettle();
    expect(find.textContaining('already in your library'), findsOneWidget);
    expect(c.records, hasLength(1));

    // Search with a question; the best passage answers it.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'how many days notice to cancel the borehole contract');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('best-passage')), findsOneWidget);
    expect(find.textContaining('fourteen days written notice'), findsOneWidget);

    // Open the record and export it as MARCXML.
    await tester.tap(find.byKey(Key('hit-${c.records.single.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record-title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('format-marcXml')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-export')));
    await tester.pumpAndSettle();

    expect(files.saved, hasLength(1));
    final xml = XmlDocument.parse(utf8.decode(files.saved.values.single));
    final titles = xml.findAllElements('datafield').where((e) => e.getAttribute('tag') == '245');
    expect(titles.single.findElements('subfield').first.innerText, 'Borehole drilling contract');
  });

  testWidgets('expanded layout (tablet landscape) shows list and record side by side', (tester) async {
    final c = await pumpApp(tester, const Size(1194, 834), seed: true);
    expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('library-list')), findsOneWidget);
    expect(find.byKey(const Key('record-title')), findsOneWidget);

    final second = c.visibleRecords[1];
    await tester.tap(find.byKey(Key('library-item-${second.id}')));
    await tester.pumpAndSettle();
    expect(c.selectedId, second.id);
    expect(tester.widget<Text>(find.byKey(const Key('record-title'))).data, second.title);
  });

  testWidgets('medium width uses a navigation rail with one pane', (tester) async {
    await pumpApp(tester, const Size(700, 1000), seed: true);
    expect(find.byKey(const Key('layout-medium')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('record-title')), findsNothing);
  });

  testWidgets('Expert view shows MARC 21', (tester) async {
    final c = await pumpApp(tester, const Size(1194, 834), seed: true);
    c.select(c.records.first.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expert · MARC 21'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marc-view')), findsOneWidget);
    final marc = tester.widget<SelectableText>(
        find.descendant(of: find.byKey(const Key('marc-view')), matching: find.byType(SelectableText)));
    expect(marc.data, startsWith('LDR'));
    expect(marc.data, contains('245 '));
  });
}
