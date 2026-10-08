/// Device check: the spec's performance targets (section 10), measured on
/// whatever device runs the app. Each stage is a top-level function taking
/// one argument and returning plain data, so it can run in a background
/// isolate (Flutter's `compute`) without freezing the screen.
library;

import 'dart:math';

import 'cataloguer.dart';
import 'export/marc21.dart';
import 'record.dart';
import 'sample/builders.dart';
import 'sample/corpus.dart';
import 'search.dart';

class BenchmarkRow {
  const BenchmarkRow(this.metric, this.measured, this.target, this.met);
  final String metric;
  final String measured;
  final String target;

  /// null when there is no target (informational).
  final bool? met;

  Map<String, Object?> toJson() => {'metric': metric, 'measured': measured, 'target': target, 'met': met};
  factory BenchmarkRow.fromJson(Map<String, Object?> j) =>
      BenchmarkRow(j['metric'] as String, j['measured'] as String, j['target'] as String, j['met'] as bool?);

  String get status => met == null ? 'info' : (met! ? 'met' : 'NOT met');
}

double _percentile(List<double> xs, double p) {
  final s = List.of(xs)..sort();
  return s[min(s.length - 1, (p * s.length).floor())];
}

String _ms(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(2)} s' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ms';

/// Stage 1: draft records for the 38 sample files and a 20-page PDF.
List<Map<String, Object?>> benchmarkCataloguing(int repeats) {
  final cataloguer = Cataloguer();
  final samples = SampleCorpus.curated();
  // Warm up once so one-off start-up work is not counted.
  cataloguer.draft(ImportedFile(samples.first.fileName, samples.first.bytes), id: 'warm');
  final per = <double>[];
  for (var r = 0; r < repeats; r++) {
    for (final s in samples) {
      final sw = Stopwatch()..start();
      cataloguer.draft(ImportedFile(s.fileName, s.bytes), id: s.key);
      per.add(sw.elapsedMicroseconds / 1000);
    }
  }
  final pages = [
    for (var i = 0; i < 20; i++)
      'Page ${i + 1}. ${List.filled(40, 'The committee reviewed the budget, the timetable and the plan for the new library building.').join(' ')}',
  ];
  final pdf = PdfBuilder.build(title: 'Twenty page report', author: 'Test Author', creationDate: '2026', pages: pages);
  final pdfTimes = <double>[];
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    cataloguer.draft(ImportedFile('report.pdf', pdf), id: 'pdf$i');
    pdfTimes.add(sw.elapsedMicroseconds / 1000);
  }
  final pdfMedian = _percentile(pdfTimes, 0.5);
  return [
    BenchmarkRow('Draft a record, typical file (median of ${per.length})', _ms(_percentile(per, 0.5)), '—', null).toJson(),
    BenchmarkRow('Draft a record for a 20-page PDF, no AI model', _ms(pdfMedian), '≤ 2 s', pdfMedian <= 2000).toJson(),
  ];
}

/// Stage 2: build a search index of [items] records and time 30 queries in
/// each mode. Also times a MARC 21 export of 1,000 records.
List<Map<String, Object?>> benchmarkSearch(int items) {
  final rnd = Random(42);
  const vocab = [
    'agreement', 'lecture', 'recipe', 'family', 'photo', 'invoice', 'school', 'health', 'farm', 'cocoa', 'music',
    'history', 'contract', 'payment', 'travel', 'insurance', 'rent', 'tax', 'bank', 'novel', 'story', 'data', 'report',
    'meeting', 'church', 'wedding', 'football', 'market', 'price', 'water', 'electricity', 'road', 'car', 'phone',
    'garden', 'kitchen', 'project', 'budget', 'letter', 'certificate', 'exam', 'student', 'teacher', 'doctor', 'clinic',
  ];
  String words(int n) => List.generate(n, (_) => vocab[rnd.nextInt(vocab.length)]).join(' ');
  final records = [
    for (var i = 0; i < items; i++)
      CatalogueRecord(
        id: 'b$i',
        mediaType: MediaType.values[rnd.nextInt(5)],
        fileName: 'file$i.pdf',
        textContent: words(150),
        addedAt: DateTime(2026, 1, 1),
        values: {
          Dc.title: [FieldValue(words(4))],
          Dc.creator: [FieldValue('Author ${rnd.nextInt(500)}')],
          Dc.subject: [FieldValue(words(2))],
          Dc.date: [FieldValue('${1990 + rnd.nextInt(36)}')],
        },
      ),
  ];
  final engine = SearchEngine();
  final indexWatch = Stopwatch()..start();
  engine.indexAll(records);
  final indexMs = indexWatch.elapsedMicroseconds / 1000;

  final kw = <double>[], hy = <double>[];
  for (var i = 0; i < 35; i++) {
    final q = words(2 + rnd.nextInt(3));
    if (i < 5) {
      engine.search(q);
      continue;
    }
    var sw = Stopwatch()..start();
    engine.search(q, mode: SearchMode.keyword);
    kw.add(sw.elapsedMicroseconds / 1000);
    sw = Stopwatch()..start();
    engine.search(q, mode: SearchMode.hybrid);
    hy.add(sw.elapsedMicroseconds / 1000);
  }
  final kwP95 = _percentile(kw, 0.95), hyP95 = _percentile(hy, 0.95);

  final exportWatch = Stopwatch()..start();
  Marc21.collectionToIso2709(records.take(1000).map((r) => Marc21.fromRecord(r)));
  final exportMs = exportWatch.elapsedMicroseconds / 1000;

  final n = _count(items);
  return [
    BenchmarkRow('Keyword search p95, $n items', _ms(kwP95), '≤ 150 ms', items >= 20000 ? kwP95 <= 150 : null).toJson(),
    BenchmarkRow('Smart search p95, $n items', _ms(hyP95), '≤ 500 ms', items >= 20000 ? hyP95 <= 500 : null).toJson(),
    BenchmarkRow('Build search index, $n items (one-off)', _ms(indexMs), '—', null).toJson(),
    BenchmarkRow('Export 1,000 records as MARC 21', _ms(exportMs), '—', null).toJson(),
  ];
}

String _count(int n) => n >= 1000 ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}' : '$n';

/// Plain-text summary for pasting into a message or issue.
String benchmarkText(List<BenchmarkRow> rows, Map<String, String> device) {
  final b = StringBuffer('iPES device check\n');
  device.forEach((k, v) => b.writeln('$k: $v'));
  b.writeln();
  for (final r in rows) {
    b.writeln('${r.metric}: ${r.measured} (target ${r.target}, ${r.status})');
  }
  return b.toString();
}
