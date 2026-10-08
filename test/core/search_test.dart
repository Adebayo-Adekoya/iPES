import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/corpus.dart';
import 'package:ipes/core/search.dart';

void main() {
  final lib = Library();
  final keyOf = <String, String>{};
  for (final s in SampleCorpus.curated()) {
    final r = lib.importFile(ImportedFile(s.fileName, s.bytes)).record;
    keyOf[r.id] = s.key;
  }
  List<String> top(String q, {SearchMode mode = SearchMode.hybrid, int n = 3}) =>
      lib.search(q, mode: mode).hits.take(n).map((h) => keyOf[h.record.id]!).toList();

  group('Query parsing', () {
    test('extracts media type and year facets', () {
      final q = QueryParser.parse('videos of grandma from 2019');
      expect(q.types, {MediaType.video});
      expect(q.year, '2019');
      expect(q.text, 'of grandma from');
    });
    test('explicit facets', () {
      final q = QueryParser.parse('type:audio year:2026 lecture');
      expect(q.types, {MediaType.audio});
      expect(q.year, '2026');
      expect(q.text, 'lecture');
    });
  });

  group('Search', () {
    test('a question finds the lease and quotes the notice clause', () {
      final result = lib.search('what does my lease say about notice');
      expect(keyOf[result.hits.first.record.id], 'lease');
      expect(result.hits.first.passage, contains('notice'));
    });

    test('facets filter by type and year', () {
      final result = lib.search('videos from 2024');
      expect(result.hits.map((h) => keyOf[h.record.id]), ['naming']);
    });

    test('identifier search', () {
      expect(top('9780306406157', n: 1), ['algonotes']);
    });

    test('meaning-based ranking finds items keyword search misses', () {
      expect(top('power bill', mode: SearchMode.keyword), isNot(contains('ecg')));
      expect(top('power bill'), contains('ecg'));
      expect(top('cooking', n: 5), containsAll(['jollof', 'cookbook']));
    });

    test('stemming: plural query matches singular text', () {
      expect(top('tenancies', n: 1), ['lease']);
    });

    test('empty text with a facet lists that type', () {
      final hits = lib.search('photos').hits;
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.record.mediaType == MediaType.image), isTrue);
    });
  });

  test('hashing embedder is deterministic and normalised', () {
    final e = HashingEmbedder();
    final a = e.embed('tenancy agreement and rent');
    final b = e.embed('tenancy agreement and rent');
    expect(a, b);
    final norm = a.fold<double>(0, (s, x) => s + x * x);
    expect(norm, closeTo(1, 1e-9));
  });
}
