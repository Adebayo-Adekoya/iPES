import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/app/controller.dart';
import 'package:ipes/app/screens/search_models.dart';
import 'package:ipes/app/semantic_service.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/corpus.dart';
import 'package:ipes/core/search.dart';
import 'package:ipes/core/semantic.dart';

import '../widget/app_flow_test.dart' show FakeFileService;

/// Stands in for an ONNX model: the built-in hashing embedder, async.
class FakeModel implements EmbeddingModel {
  FakeModel(this.spec);
  @override
  final ModelSpec spec;
  final _hash = HashingEmbedder();
  int calls = 0;
  bool closed = false;

  @override
  Future<Float32List> embed(String text) async {
    calls++;
    return Float32List.fromList(_hash.embed(text));
  }

  @override
  Future<void> close() async => closed = true;
}

Future<Directory> fakeDownload(Directory base, ModelSpec m) async {
  for (final f in m.files) {
    final file = File('${base.path}/models/${m.id}/${f.path}');
    await file.parent.create(recursive: true);
    await file.writeAsString('x');
  }
  return base;
}

void main() {
  late Directory base;
  final loaded = <FakeModel>[];
  SemanticService service() => SemanticService(
        loader: (spec, dir) async {
          final m = FakeModel(spec);
          loaded.add(m);
          return m;
        },
        baseDir: () async => base,
      );

  setUp(() async {
    base = await Directory.systemTemp.createTemp('ipes_models');
    loaded.clear();
  });
  tearDown(() => base.delete(recursive: true));

  List<CatalogueRecord> sampleRecords() {
    final lib = Library();
    for (final s in SampleCorpus.curated()) {
      lib.importFile(ImportedFile(s.fileName, s.bytes));
    }
    return lib.records;
  }

  test('finds downloaded models and remembers the chosen one', () async {
    await fakeDownload(base, ModelSpec.e5Small);
    final s = service();
    await s.start();
    expect(s.state['e5-small'], ModelState.downloaded);
    expect(s.state['embeddinggemma'], ModelState.notDownloaded);
    await s.choose('e5-small', sampleRecords());
    final again = service();
    await again.start();
    expect(again.activeId, 'e5-small');
  });

  test('indexes the library, ranks queries and reuses stored vectors', () async {
    await fakeDownload(base, ModelSpec.e5Small);
    final records = sampleRecords();
    final s = service();
    await s.start();
    await s.choose('e5-small', records);
    expect(s.indexed, records.length);
    expect(loaded.single.calls, records.length);

    final ranking = await s.rank('power bill');
    expect(ranking, isNotNull);
    final top = records.firstWhere((r) => r.id == ranking!.first);
    expect(top.title, contains('Electricity'));

    // A new session loads stored vectors instead of embedding again.
    final again = service();
    await again.start();
    await again.sync(records);
    expect(loaded.last.calls, 0);
    expect(again.indexed, records.length);

    // Editing one record re-embeds just that record.
    records.first.setOne(Dc.title, const FieldValue('Something new'));
    await again.sync(records);
    expect(loaded.last.calls, 1);
  });

  test('switching back to built-in closes the model and search falls back', () async {
    await fakeDownload(base, ModelSpec.e5Small);
    final s = service();
    await s.start();
    await s.choose('e5-small', sampleRecords());
    await s.choose(null, const []);
    expect(loaded.single.closed, isTrue);
    expect(await s.rank('power bill'), isNull);
    expect(s.statusLine, 'Built-in search');
  });

  test('model ranking feeds hybrid search through the controller', () async {
    await fakeDownload(base, ModelSpec.e5Small);
    final s = service();
    final c = LibraryController(library: Library(), files: FakeFileService(), semantic: s);
    await c.start();
    await s.choose('e5-small', c.records);
    final result = await c.smartSearch('what does my lease say about notice');
    expect(result.hits.first.record.title, contains('Tenancy'));
  });

  test('sample evaluation scores a model like the CI evaluation', () async {
    final (quality, timings) = await evaluateModelOnSamples(FakeModel(ModelSpec.e5Small));
    expect(timings.itemMs, hasLength(38));
    expect(timings.queryMs, hasLength(SampleCorpus.queries.length));
    // The fake model is the built-in ranker, so it should match its score.
    expect(quality.ndcg, greaterThan(0.85));
    expect(quality.keywordNdcg, closeTo(0.844, 0.02));
  });

  testWidgets('search model page lists the models and their sizes', (tester) async {
    final c = LibraryController(library: Library(), files: FakeFileService());
    await tester.pumpWidget(MaterialApp(home: SearchModelsPage(controller: c)));
    expect(find.byKey(const Key('model-builtin')), findsOneWidget);
    expect(find.byKey(const Key('model-e5-small')), findsOneWidget);
    expect(find.byKey(const Key('model-embeddinggemma')), findsOneWidget);
    expect(find.textContaining('135 MB'), findsOneWidget);
    expect(find.textContaining('On-device models run in the Android and iOS apps'), findsOneWidget);
  });
}
