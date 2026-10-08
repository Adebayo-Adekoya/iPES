/// Evaluation against spec sections 11–12. Runs as a test so CI produces
/// build/eval/report.md and build/eval/results.json on every push.
///
/// Honest limits: the corpus is synthetic and was written by the same team
/// that wrote the cataloguer and the judged queries, so accuracy figures are
/// optimistic; timings come from the CI machine, not a phone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/export/dublin_core.dart';
import 'package:ipes/core/export/marc21.dart';
import 'package:ipes/core/isbn.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/builders.dart';
import 'package:ipes/core/sample/corpus.dart';
import 'package:ipes/core/search.dart';
import 'package:xml/xml.dart';

String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

bool sameName(String a, String b) {
  final ta = norm(a).split(' ').toSet();
  final tb = norm(b).split(' ').toSet();
  return ta.length == tb.length && ta.containsAll(tb);
}

bool sameDate(String got, String gold) => got.length >= 4 && gold.length >= 4 && got.substring(0, 4) == gold.substring(0, 4);

bool sameId(CatalogueRecord r, String gold) {
  for (final id in r.texts(Dc.identifier)) {
    if (gold.startsWith('doi:') && id.toLowerCase() == gold.toLowerCase()) return true;
    if (id.startsWith('ISBN ') && Isbn.toIsbn13(id.substring(5)) == gold) return true;
  }
  return false;
}

double ndcgAt(List<String> ranked, Map<String, int> rel, int k) {
  double dcg(List<int> gains) {
    var s = 0.0;
    for (var i = 0; i < gains.length && i < k; i++) {
      s += (pow(2, gains[i]) - 1) / (log(i + 2) / ln2);
    }
    return s;
  }

  final actual = dcg([for (final key in ranked) rel[key] ?? 0]);
  final ideal = dcg(rel.values.toList()..sort((a, b) => b.compareTo(a)));
  return ideal == 0 ? 0 : actual / ideal;
}

double percentile(List<double> xs, double p) {
  final s = List.of(xs)..sort();
  return s[min(s.length - 1, (p * s.length).floor())];
}

String pct(num x) => '${(x * 100).toStringAsFixed(1)}%';

void main() {
  final results = <String, Object?>{};
  final rows = <List<String>>[]; // area, metric, measured, target, status

  void row(String area, String metric, String measured, String target, bool? met) =>
      rows.add([area, metric, measured, target, met == null ? (measured.startsWith('—') ? 'Not measured' : 'Info') : (met ? 'Met' : 'Not met')]);

  test('cataloguing accuracy', () {
    final cataloguer = Cataloguer();
    final items = [...SampleCorpus.curated(), ...SampleCorpus.generated(count: 150)];
    final counts = <String, List<int>>{'title': [0, 0], 'creator': [0, 0], 'date': [0, 0], 'identifier': [0, 0], 'language': [0, 0]};
    var lowEdit = 0;
    final misses = <String>[];
    final times = <double>[];
    for (final s in items) {
      final sw = Stopwatch()..start();
      final r = cataloguer.draft(ImportedFile(s.fileName, s.bytes), id: s.key);
      times.add(sw.elapsedMicroseconds / 1000);
      var edits = 0;
      void check(String field, String? gold, bool Function() ok) {
        if (gold == null) return;
        counts[field]![1]++;
        if (ok()) {
          counts[field]![0]++;
        } else {
          edits++;
          if (misses.length < 25) misses.add('${s.key} $field: got "${field == 'identifier' ? r.texts(Dc.identifier).join(', ') : r.text(field == 'title' ? Dc.title : field == 'creator' ? Dc.creator : field == 'date' ? Dc.date : Dc.language)}", want "$gold"');
        }
      }

      check('title', s.gold.title, () => norm(r.title) == norm(s.gold.title!));
      check('creator', s.gold.creator, () => r.texts(Dc.creator).isNotEmpty && sameName(r.texts(Dc.creator).first, s.gold.creator!));
      check('date', s.gold.date, () => sameDate(r.text(Dc.date), s.gold.date!));
      check('identifier', s.gold.identifier, () => sameId(r, s.gold.identifier!));
      check('language', s.gold.language, () => r.text(Dc.language) == s.gold.language);
      if (edits <= 1) lowEdit++;
    }
    final fieldAcc = {for (final e in counts.entries) e.key: e.value[1] == 0 ? 0.0 : e.value[0] / e.value[1]};
    final core4 = ['title', 'creator', 'date', 'identifier'];
    final coreCorrect = core4.fold<int>(0, (a, f) => a + counts[f]![0]);
    final coreTotal = core4.fold<int>(0, (a, f) => a + counts[f]![1]);
    final coreAcc = coreCorrect / coreTotal;
    final accepted = lowEdit / items.length;
    results['cataloguing'] = {
      'items': items.length,
      'fieldAccuracy': fieldAcc,
      'fieldCounts': counts,
      'coreFieldAccuracy': coreAcc,
      'acceptedWithAtMostOneEdit': accepted,
      'medianDraftMs': percentile(times, 0.5),
      'p95DraftMs': percentile(times, 0.95),
      'sampleMisses': misses,
    };
    row('Auto-cataloguing', 'Field accuracy: title, creator, date, identifier', pct(coreAcc), '≥ 90%', coreAcc >= 0.9);
    for (final f in core4) {
      row('Auto-cataloguing', '· $f (${counts[f]![1]} items with a known value)', pct(fieldAcc[f]!), '—', null);
    }
    row('Auto-cataloguing', 'Drafts accepted with ≤ 1 edit', pct(accepted), '≥ 75%', accepted >= 0.75);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('20-page PDF drafting time', () {
    final pages = [
      for (var i = 0; i < 20; i++)
        'Page ${i + 1}. ${List.filled(40, 'The committee reviewed the budget, the timetable and the plan for the new library building.').join(' ')}',
    ];
    final pdf = PdfBuilder.build(title: 'Twenty page report', author: 'Test Author', creationDate: '2026', pages: pages);
    final cataloguer = Cataloguer();
    cataloguer.draft(ImportedFile('warmup.pdf', pdf), id: 'w');
    final times = <double>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      final r = cataloguer.draft(ImportedFile('report.pdf', pdf), id: 'r$i');
      times.add(sw.elapsedMicroseconds / 1000);
      expect(r.pageCount, 20);
    }
    final median = percentile(times, 0.5);
    results['pdf20DraftMs'] = median;
    row('Performance', 'Draft record for a 20-page PDF, no LLM (CI machine)', '${median.toStringAsFixed(0)} ms', '≤ 2 s', median <= 2000);
  });

  test('search relevance', () {
    final lib = Library();
    final keyOf = <String, String>{};
    for (final s in SampleCorpus.curated()) {
      keyOf[lib.importFile(ImportedFile(s.fileName, s.bytes)).record.id] = s.key;
    }
    final byMode = <String, Map<String, List<double>>>{};
    final perQuery = <Map<String, Object>>[];
    for (final mode in [SearchMode.keyword, SearchMode.hybrid]) {
      for (final q in SampleCorpus.queries) {
        final ranked = lib.search(q.query, mode: mode, limit: 10).hits.map((h) => keyOf[h.record.id]!).toList();
        final ndcg = ndcgAt(ranked, q.relevance, 10);
        final top3 = ranked.take(3).any((k) => (q.relevance[k] ?? 0) == 2) ? 1.0 : 0.0;
        final bucket = byMode.putIfAbsent(mode.name, () => {});
        bucket.putIfAbsent('ndcg', () => []).add(ndcg);
        bucket.putIfAbsent('ndcg_${q.kind}', () => []).add(ndcg);
        bucket.putIfAbsent('top3', () => []).add(top3);
        if (mode == SearchMode.hybrid) {
          perQuery.add({'query': q.query, 'kind': q.kind, 'ndcg10': ndcg, 'top': ranked.take(3).toList()});
        }
      }
    }
    double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final hy = byMode['hybrid']!;
    final kw = byMode['keyword']!;
    final ndcgHy = mean(hy['ndcg']!);
    final ndcgKw = mean(kw['ndcg']!);
    final lift = ndcgKw == 0 ? 1.0 : (ndcgHy - ndcgKw) / ndcgKw;
    results['search'] = {
      'queries': SampleCorpus.queries.length,
      'ndcg10Hybrid': ndcgHy,
      'ndcg10Keyword': ndcgKw,
      'ndcg10HybridMeaningQueries': mean(hy['ndcg_meaning']!),
      'ndcg10KeywordMeaningQueries': mean(kw['ndcg_meaning']!),
      'ndcg10HybridKeywordQueries': mean(hy['ndcg_keyword']!),
      'successAt3Hybrid': mean(hy['top3']!),
      'liftOverKeyword': lift,
      'perQuery': perQuery,
    };
    row('Smart search', 'nDCG@10, ${SampleCorpus.queries.length} judged queries (hybrid)', ndcgHy.toStringAsFixed(3), '≥ 0.75', ndcgHy >= 0.75);
    row('Smart search', 'Lift over keyword-only (keyword nDCG ${ndcgKw.toStringAsFixed(3)})', pct(lift), '≥ 15%', lift >= 0.15);
    row('Smart search', '· vocabulary-mismatch queries: hybrid vs keyword',
        '${mean(hy['ndcg_meaning']!).toStringAsFixed(3)} vs ${mean(kw['ndcg_meaning']!).toStringAsFixed(3)}', '—', null);
    row('Smart search', 'Known item in top 3 results', pct(mean(hy['top3']!)), '≥ 90%', mean(hy['top3']!) >= 0.9);
  });

  test('classification accuracy', () {
    final cataloguer = Cataloguer();
    var n = 0, mainHits = 0, division = 0, first = 0;
    final misses = <String>[];
    for (final s in [...SampleCorpus.curated(), ...SampleCorpus.generated(count: 150)]) {
      final gold = s.gold.ddc;
      if (gold == null) continue;
      final r = cataloguer.draft(ImportedFile(s.fileName, s.bytes), id: s.key);
      n++;
      final sugg = r.classSuggestions.map((c) => c.number).toList();
      if (sugg.any((c) => c[0] == gold[0])) {
        mainHits++;
      } else if (misses.length < 20) {
        misses.add('${s.key}: suggested ${sugg.join(', ')}; want $gold');
      }
      if (sugg.any((c) => c.substring(0, 2) == gold.substring(0, 2))) division++;
      if (sugg.isNotEmpty && sugg.first[0] == gold[0]) first++;
    }
    results['classification'] = {
      'items': n,
      'top3MainClass': mainHits / n,
      'top3Division': division / n,
      'top1MainClass': first / n,
      'sampleMisses': misses,
    };
    row('Auto-classify', 'Correct main class (hundreds) in top 3 suggestions', pct(mainHits / n), '≥ 85%', mainHits / n >= 0.85);
    row('Auto-classify', '· correct division (tens) in top 3', pct(division / n), '—', null);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('standards conformance', () {
    final cataloguer = Cataloguer();
    final records = [
      for (final s in [...SampleCorpus.curated(), ...SampleCorpus.generated(count: 150)])
        cataloguer.draft(ImportedFile(s.fileName, s.bytes), id: s.key),
    ];
    var iso = 0, marcxml = 0, dc = 0;
    for (final r in records) {
      final m = Marc21.fromRecord(r);
      try {
        final back = Marc21.parseIso2709(Marc21.toIso2709(m));
        if (back.fields.length == m.fields.length &&
            back.fields.every((f) => m.fields.any((g) => g.tag == f.tag && g.data == f.data))) {
          iso++;
        }
      } catch (_) {}
      try {
        final doc = XmlDocument.parse(Marc21.toMarcXml([m]));
        if (doc.findAllElements('record').length == 1) marcxml++;
      } catch (_) {}
      try {
        XmlDocument.parse(DublinCore.toXml(r));
        dc++;
      } catch (_) {}
    }
    final n = records.length;
    results['conformance'] = {'records': n, 'iso2709RoundTrip': iso / n, 'marcxmlWellFormed': marcxml / n, 'dcWellFormed': dc / n};
    final all = iso == n && marcxml == n && dc == n;
    row('Conformance', 'MARC 21 ISO 2709 round trip / MARCXML / Dublin Core XML ($n records)',
        '${pct(iso / n)} / ${pct(marcxml / n)} / ${pct(dc / n)}', '100%', all);
    expect(all, isTrue, reason: 'Exports must always be valid');

    final completeness = records.map((r) => r.completeness).reduce((a, b) => a + b) / n;
    results['completeness'] = completeness;
    row('Collection health', 'Core Dublin Core fields filled per item', pct(completeness), '≥ 85%', completeness >= 0.85);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('search performance at 20,000 items', () {
    final rnd = Random(42);
    const vocab = [
      'agreement', 'lecture', 'recipe', 'family', 'photo', 'invoice', 'school', 'health', 'farm', 'cocoa', 'music',
      'history', 'contract', 'payment', 'travel', 'insurance', 'rent', 'tax', 'bank', 'novel', 'story', 'data', 'report',
      'meeting', 'church', 'wedding', 'football', 'market', 'price', 'water', 'electricity', 'road', 'car', 'phone',
      'garden', 'kitchen', 'project', 'budget', 'letter', 'certificate', 'exam', 'student', 'teacher', 'doctor', 'clinic',
    ];
    String words(int n) => List.generate(n, (_) => vocab[rnd.nextInt(vocab.length)]).join(' ');
    final records = [
      for (var i = 0; i < 20000; i++)
        CatalogueRecord(
          id: 'p$i',
          mediaType: MediaType.values[rnd.nextInt(5)],
          fileName: 'file$i.pdf',
          textContent: words(150),
          values: {
            Dc.title: [FieldValue(words(4))],
            Dc.creator: [FieldValue('Author ${rnd.nextInt(500)}')],
            Dc.subject: [FieldValue(words(2))],
            Dc.date: [FieldValue('${1990 + rnd.nextInt(36)}')],
          },
        ),
    ];
    final engine = SearchEngine();
    final sw = Stopwatch()..start();
    engine.indexAll(records);
    final indexMs = sw.elapsedMilliseconds;
    final kw = <double>[], hy = <double>[];
    for (var i = 0; i < 60; i++) {
      final q = words(2 + rnd.nextInt(3));
      if (i < 5) {
        engine.search(q);
        continue; // warm-up
      }
      var t = Stopwatch()..start();
      engine.search(q, mode: SearchMode.keyword);
      kw.add(t.elapsedMicroseconds / 1000);
      t = Stopwatch()..start();
      engine.search(q, mode: SearchMode.hybrid);
      hy.add(t.elapsedMicroseconds / 1000);
    }
    final kwP95 = percentile(kw, 0.95), hyP95 = percentile(hy, 0.95);
    results['performance'] = {'items': records.length, 'indexBuildMs': indexMs, 'keywordP95Ms': kwP95, 'hybridP95Ms': hyP95};
    row('Performance', 'Keyword search p95, 20,000 items (CI machine)', '${kwP95.toStringAsFixed(1)} ms', '≤ 150 ms', kwP95 <= 150);
    row('Performance', 'Smart (hybrid) search p95, 20,000 items (CI machine)', '${hyP95.toStringAsFixed(1)} ms', '≤ 500 ms', hyP95 <= 500);
    row('Performance', 'Index build for 20,000 items (one-off)', '${(indexMs / 1000).toStringAsFixed(1)} s', '—', null);
  }, timeout: const Timeout(Duration(minutes: 10)));

  tearDownAll(() {
    row('Usability', 'System Usability Scale', '—', '≥ 80', null);
    row('Usability', 'Custom module created unaided in ≤ 3 min', '— (module builder not in prototype)', '≥ 80%', null);
    row('Engagement', '30-day retention; store rating', '— (needs beta)', '≥ 35%; ≥ 4.5', null);
    row('Reliability', 'Crash-free sessions', '— (needs beta)', '≥ 99.5%', null);

    final dir = Directory('build/eval')..createSync(recursive: true);
    File('${dir.path}/results.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    final md = StringBuffer()
      ..writeln('# iPES prototype evaluation')
      ..writeln()
      ..writeln('Generated ${DateTime.now().toUtc().toIso8601String()} by `test/eval/evaluation_test.dart`.')
      ..writeln()
      ..writeln('| Area | Metric | Measured | Target | Status |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final r in rows) {
      md.writeln('| ${r.join(' | ')} |');
    }
    md
      ..writeln()
      ..writeln('Limits: synthetic corpus written alongside the cataloguer (accuracy is optimistic); '
          'the meaning-based ranker is a hashing stand-in for EmbeddingGemma; timings are from the CI machine, not a phone. '
          'Two cataloguing bugs found by the first run on this corpus were fixed, so it is not a held-out test set.');
    File('${dir.path}/report.md').writeAsStringSync(md.toString());
    // ignore: avoid_print
    print(md);
  });
}
