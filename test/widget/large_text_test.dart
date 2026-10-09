// Every screen must lay out without overflow when the phone's font size is
// large (a common accessibility setting). Flutter reports any overflow as a
// test failure, so simply visiting each screen is the check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/app/controller.dart';
import 'package:ipes/app/screens/device_check.dart';
import 'package:ipes/app/shell.dart';
import 'package:ipes/core/library.dart';

import 'app_flow_test.dart' show FakeFileService;

void main() {
  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('phone screens at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(384, 832);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      final c = LibraryController(library: Library(), files: FakeFileService());
      await c.start();
      await tester.pumpWidget(IpesApp(controller: c));
      await tester.pumpAndSettle();

      // Library list.
      expect(find.byKey(const Key('library-list')), findsOneWidget);

      // Record view, both tabs.
      await tester.tap(find.byKey(Key('library-item-${c.records.first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MARC 21'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Search with results and a passage.
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search-field')), 'what does my lease say about notice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('best-passage')), findsOneWidget);

      // Review draft, skip it, then the empty state.
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accept-draft')), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('skipped'), findsWidgets);

      // Export sheet.
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export library'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-preview')), findsOneWidget);
    });

    testWidgets('device check results at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(384, 832);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(MaterialApp(
        home: DeviceCheckPage(runner: (stage, arg) async => stage(arg), searchItems: 200),
      ));
      await tester.tap(find.byKey(const Key('run-device-check')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('copy-results')), 200);
    });
  }
}
