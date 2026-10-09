/// Exports the search evaluation set so embedding models can be compared
/// outside Dart (tool/embedding_eval.py). For each judged query it records
/// the text the semantic ranker sees (facet words removed), the items the
/// facets allow, the keyword-only ranking, and the current hybrid ranking.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/corpus.dart';
import 'package:ipes/core/search.dart';
import 'package:ipes/core/text.dart';

void main() {
  test('export search evaluation set', () {
    final lib = Library();
    final keyOf = <String, String>{};
    final records = <String, CatalogueRecord>{};
    for (final s in SampleCorpus.curated()) {
      final r = lib.importFile(ImportedFile(s.fileName, s.bytes)).record;
      keyOf[r.id] = s.key;
      records[s.key] = r;
    }

    final docs = [
      for (final e in records.entries)
        {
          'key': e.key,
          'type': e.value.mediaType.name,
          'title': e.value.title,
          // Same fields the in-app ranker embeds, with more body text so
          // models with longer context can use it.
          'text': [
            e.value.texts(Dc.creator).join(', '),
            e.value.texts(Dc.subject).join('; '),
            e.value.text(Dc.description),
            e.value.textContent.length > 6000 ? e.value.textContent.substring(0, 6000) : e.value.textContent,
          ].where((s) => s.trim().isNotEmpty).join('\n'),
        },
    ];

    final queries = <Map<String, Object?>>[];
    for (final q in SampleCorpus.queries) {
      final parsed = QueryParser.parse(q.query);
      bool allowed(CatalogueRecord r) =>
          (parsed.types.isEmpty || parsed.types.contains(r.mediaType)) &&
          (parsed.year == null || r.text(Dc.date).startsWith(parsed.year!) || r.addedAt.year.toString() == parsed.year);
      List<String> ranked(SearchMode mode, int limit) =>
          lib.search(q.query, mode: mode, limit: limit).hits.map((h) => keyOf[h.record.id]!).toList();
      queries.add({
        'query': q.query,
        'kind': q.kind,
        'relevance': q.relevance,
        'semanticText': parsed.text,
        'textEmpty': TextTools.terms(parsed.text).isEmpty,
        'allowed': [for (final e in records.entries) if (allowed(e.value)) e.key],
        'keyword': ranked(SearchMode.keyword, 100),
        'currentHybrid': ranked(SearchMode.hybrid, 10),
      });
    }

    final dir = Directory('build/eval')..createSync(recursive: true);
    File('${dir.path}/search_set.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'docs': docs, 'queries': queries}));
    expect(queries, hasLength(SampleCorpus.queries.length));
  });
}
