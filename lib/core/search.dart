/// Smart search (spec section 8): hybrid keyword + vector ranking merged with
/// reciprocal rank fusion, natural-language facet parsing, and passage answers.
///
/// The prototype's [HashingEmbedder] is a stand-in for EmbeddingGemma: it
/// hashes word stems, character trigrams and a small concept lexicon into a
/// fixed vector. It runs anywhere with no model download; swapping in a real
/// embedding model only means providing another [TextEmbedder].
library;

import 'dart:math' as math;

import 'record.dart';
import 'text.dart';

enum SearchMode { keyword, semantic, hybrid }

class ParsedQuery {
  ParsedQuery(this.raw, this.text, this.types, this.year);
  final String raw;

  /// Query text with facet words removed.
  final String text;
  final Set<MediaType> types;
  final String? year;

  List<String> get facetLabels => [
        for (final t in types) 'Type: ${t.label}',
        if (year != null) 'Year: $year',
      ];
}

class QueryParser {
  static const _typeWords = <String, MediaType>{
    'video': MediaType.video, 'videos': MediaType.video, 'film': MediaType.video,
    'films': MediaType.video, 'clip': MediaType.video, 'clips': MediaType.video, 'movie': MediaType.video,
    'photo': MediaType.image, 'photos': MediaType.image, 'picture': MediaType.image,
    'pictures': MediaType.image, 'image': MediaType.image, 'images': MediaType.image, 'pics': MediaType.image,
    'audio': MediaType.audio, 'recording': MediaType.audio, 'recordings': MediaType.audio,
    'podcast': MediaType.audio, 'podcasts': MediaType.audio,
    'book': MediaType.book, 'books': MediaType.book, 'ebook': MediaType.book, 'ebooks': MediaType.book,
    'pdf': MediaType.document, 'pdfs': MediaType.document, 'document': MediaType.document,
    'documents': MediaType.document, 'docs': MediaType.document, 'scan': MediaType.document, 'scans': MediaType.document,
  };

  static ParsedQuery parse(String raw) {
    final types = <MediaType>{};
    String? year;
    final kept = <String>[];
    for (final token in raw.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final lower = token.toLowerCase().replaceAll(RegExp(r'[?,.!]+$'), '');
      final explicit = RegExp(r'^(type|year):(.+)$').firstMatch(lower);
      if (explicit != null) {
        if (explicit.group(1) == 'year') {
          year = explicit.group(2);
        } else {
          final t = _typeWords[explicit.group(2)] ??
              MediaType.values.where((m) => m.name == explicit.group(2)).firstOrNull;
          if (t != null) types.add(t);
        }
        continue;
      }
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(lower)) {
        year = lower;
        continue;
      }
      final t = _typeWords[lower];
      if (t != null) {
        types.add(t);
        continue;
      }
      kept.add(token);
    }
    return ParsedQuery(raw, kept.join(' '), types, year);
  }
}

abstract class TextEmbedder {
  String get name;
  int get dimensions;
  List<double> embed(String text);
}

/// Feature-hashing embedder with a concept (synonym) lexicon.
class HashingEmbedder implements TextEmbedder {
  HashingEmbedder({this.dimensions = 512}) {
    for (var g = 0; g < _conceptGroups.length; g++) {
      for (final w in _conceptGroups[g]) {
        _concepts.putIfAbsent(TextTools.stem(w), () => []).add(g);
      }
    }
  }

  @override
  String get name => 'Hashing embedder + concept lexicon (prototype stand-in)';

  @override
  final int dimensions;

  final Map<String, List<int>> _concepts = {};

  static const _conceptGroups = [
    ['lease', 'tenancy', 'rental', 'rent', 'landlord', 'tenant', 'letting'],
    ['notice', 'termination', 'terminate', 'quit', 'vacate'],
    ['video', 'film', 'recording', 'clip', 'footage'],
    ['photo', 'picture', 'image', 'snapshot', 'photograph'],
    ['grandma', 'grandmother', 'nana', 'granny', 'grandparent'],
    ['grandpa', 'grandfather'],
    ['wedding', 'marriage', 'bride', 'groom'],
    ['naming', 'outdooring', 'christening', 'baptism'],
    ['lecture', 'class', 'lesson', 'course', 'seminar', 'tutorial'],
    ['invoice', 'bill', 'receipt', 'payment', 'statement'],
    ['electricity', 'power', 'ecg', 'utility', 'prepaid'],
    ['doctor', 'medical', 'hospital', 'clinic', 'health', 'prescription', 'medicine'],
    ['car', 'vehicle', 'auto', 'motor'],
    ['recipe', 'cooking', 'dish', 'meal', 'food', 'cook', 'jollof'],
    ['contract', 'agreement', 'deal', 'terms'],
    ['money', 'finance', 'bank', 'savings', 'loan', 'account'],
    ['school', 'education', 'university', 'college', 'student'],
    ['song', 'music', 'track', 'album', 'highlife'],
    ['book', 'novel', 'ebook', 'fiction'],
    ['child', 'kid', 'children', 'baby', 'son', 'daughter'],
    ['house', 'home', 'flat', 'apartment', 'property', 'land', 'plot'],
    ['job', 'work', 'employment', 'career', 'cv', 'resume', 'salary'],
    ['travel', 'trip', 'journey', 'holiday', 'vacation', 'flight'],
    ['insurance', 'policy', 'cover', 'premium'],
    ['algorithm', 'programming', 'code', 'software', 'data', 'computer'],
    ['farm', 'farming', 'crop', 'cocoa', 'harvest', 'agriculture'],
    ['tax', 'gra', 'revenue', 'vat'],
    ['passport', 'visa', 'id', 'identity', 'certificate', 'birth'],
  ];

  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      // h * 0x01000193 mod 2^32, written to stay exact on the web (53-bit ints).
      h = ((h * 0x193) + ((h << 24) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    return h;
  }

  @override
  List<double> embed(String text) {
    final v = List<double>.filled(dimensions, 0);
    void add(String feature, double weight) {
      final h = _fnv1a(feature);
      final sign = (h >> 31) & 1 == 1 ? -1.0 : 1.0;
      v[h % dimensions] += sign * weight;
    }

    final counts = <String, int>{};
    for (final t in TextTools.terms(text)) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    counts.forEach((term, n) {
      final w = 1 + math.log(n);
      add('w:$term', w);
      for (final g in _concepts[term] ?? const <int>[]) {
        add('c:$g', 1.4 * w);
      }
      if (term.length >= 4) {
        final padded = '<$term>';
        for (var i = 0; i + 3 <= padded.length; i++) {
          add('t:${padded.substring(i, i + 3)}', 0.25 * w);
        }
      }
    });
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }
}

class SearchHit {
  SearchHit(this.record, this.score, this.reasons, {this.passage});
  final CatalogueRecord record;
  final double score;
  final List<String> reasons;

  /// The best-matching sentence from the item's text, if any.
  final String? passage;
}

class SearchResult {
  SearchResult(this.query, this.hits, this.elapsed);
  final ParsedQuery query;
  final List<SearchHit> hits;
  final Duration elapsed;
}

class SearchEngine {
  SearchEngine({TextEmbedder? embedder}) : embedder = embedder ?? HashingEmbedder();

  final TextEmbedder embedder;

  static const _k1 = 1.2;
  static const _b = 0.75;
  static const _rrfK = 60;
  static const _maxTextTerms = 20000;

  // Slot-based index: removing a record leaves an empty slot (null), so
  // adding, editing or removing one record never rebuilds the whole index.
  final List<CatalogueRecord?> _docs = [];
  final List<int> _lengths = [];
  final List<List<double>?> _vectors = [];
  final List<Map<String, Set<String>>?> _termFields = []; // per slot: term -> fields it matched
  final Map<String, Map<int, double>> _postings = {};
  final Map<String, int> _slotOf = {};
  int _live = 0;
  int _totalLength = 0;

  double get _avgLength => _live == 0 ? 1 : _totalLength / _live;

  /// Number of records in the index.
  int get size => _live;

  void indexAll(Iterable<CatalogueRecord> records) {
    _docs.clear();
    _lengths.clear();
    _vectors.clear();
    _termFields.clear();
    _postings.clear();
    _slotOf.clear();
    _live = 0;
    _totalLength = 0;
    for (final r in records) {
      add(r);
    }
  }

  /// Adds or replaces one record.
  void add(CatalogueRecord r) {
    remove(r.id);
    final doc = _docs.length;
    _docs.add(r);
    _slotOf[r.id] = doc;
    final termFields = <String, Set<String>>{};
    var length = 0;
    void field(String name, String value, double weight, {int max = 1 << 30}) {
      var terms = TextTools.terms(value);
      if (terms.length > max) terms = terms.sublist(0, max);
      for (final t in terms) {
        final p = _postings.putIfAbsent(t, () => {});
        p[doc] = (p[doc] ?? 0) + weight;
        termFields.putIfAbsent(t, () => {}).add(name);
      }
      length += terms.length;
    }

    field('title', r.title, 3);
    field('creator', r.texts(Dc.creator).join(' '), 2);
    field('subject', [...r.texts(Dc.subject), ...r.classSuggestions.take(1).map((c) => c.label)].join(' '), 2);
    field('description', r.text(Dc.description), 1);
    field('publisher', r.text(Dc.publisher), 1);
    field('identifier', r.texts(Dc.identifier).join(' '), 1);
    field('text', r.textContent, 1, max: _maxTextTerms);
    length = math.max(1, length);
    _lengths.add(length);
    _termFields.add(termFields);
    _live++;
    _totalLength += length;

    final summaryText = [
      r.title,
      r.texts(Dc.creator).join(' '),
      r.texts(Dc.subject).join(' '),
      r.text(Dc.description),
      r.textContent.length > 3000 ? r.textContent.substring(0, 3000) : r.textContent,
    ].join('. ');
    _vectors.add(embedder.embed(summaryText));
  }

  /// Re-indexes a record after its fields changed.
  void update(CatalogueRecord r) => add(r);

  /// Removes a record. Returns false if it was not indexed.
  bool remove(String id) {
    final doc = _slotOf.remove(id);
    if (doc == null) return false;
    for (final t in _termFields[doc]!.keys) {
      final p = _postings[t];
      if (p == null) continue;
      p.remove(doc);
      if (p.isEmpty) _postings.remove(t);
    }
    _live--;
    _totalLength -= _lengths[doc];
    _docs[doc] = null;
    _vectors[doc] = null;
    _termFields[doc] = null;
    // Compact when more than half the slots are empty.
    if (_docs.length > 64 && _live * 2 < _docs.length) {
      indexAll(_docs.whereType<CatalogueRecord>().toList());
    }
    return true;
  }

  SearchResult search(String raw, {int limit = 20, SearchMode mode = SearchMode.hybrid}) {
    final watch = Stopwatch()..start();
    final q = QueryParser.parse(raw);
    bool allowed(CatalogueRecord r) =>
        (q.types.isEmpty || q.types.contains(r.mediaType)) &&
        (q.year == null || r.text(Dc.date).startsWith(q.year!) || r.addedAt.year.toString() == q.year);

    final candidates = <int>[
      for (var i = 0; i < _docs.length; i++)
        if (_docs[i] != null && allowed(_docs[i]!)) i,
    ];
    final terms = TextTools.terms(q.text).toSet().toList();

    if (terms.isEmpty) {
      final list = candidates.map((i) => _docs[i]!).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      final hits = [for (final r in list.take(limit)) SearchHit(r, 0, q.facetLabels)];
      return SearchResult(q, hits, watch.elapsed);
    }

    final keyword = mode == SearchMode.semantic ? <int, double>{} : _bm25(terms, candidates.toSet());
    final semantic = mode == SearchMode.keyword ? <int, double>{} : _cosine(q.text, candidates);

    final fused = <int, double>{};
    void fuse(Map<int, double> scores) {
      final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (var rank = 0; rank < ranked.length && rank < 100; rank++) {
        fused[ranked[rank].key] = (fused[ranked[rank].key] ?? 0) + 1 / (_rrfK + rank + 1);
      }
    }

    fuse(keyword);
    fuse(semantic);
    final ranked = fused.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final hits = <SearchHit>[];
    for (final e in ranked.take(limit)) {
      final doc = e.key;
      final reasons = <String>[];
      final fields = <String>{};
      for (final t in terms) {
        fields.addAll(_termFields[doc]![t] ?? const {});
      }
      if (fields.isNotEmpty) reasons.add('Matched ${fields.join(', ')}');
      if (!keyword.containsKey(doc) && semantic.containsKey(doc)) reasons.add('Similar meaning');
      reasons.addAll(q.facetLabels);
      // Passages only for the top results: they are the expensive part.
      final record = _docs[doc]!;
      final passage = hits.length < 3 ? bestPassage(record.textContent, q.text) : null;
      hits.add(SearchHit(record, e.value, reasons, passage: passage));
    }
    return SearchResult(q, hits, watch.elapsed);
  }

  Map<int, double> _bm25(List<String> terms, Set<int> allowed) {
    final n = _live;
    final scores = <int, double>{};
    for (final t in terms) {
      final postings = _postings[t];
      if (postings == null) continue;
      final idf = math.log(1 + (n - postings.length + 0.5) / (postings.length + 0.5));
      postings.forEach((doc, tf) {
        if (!allowed.contains(doc)) return;
        final norm = tf * (_k1 + 1) / (tf + _k1 * (1 - _b + _b * _lengths[doc] / _avgLength));
        scores[doc] = (scores[doc] ?? 0) + idf * norm;
      });
    }
    return scores;
  }

  Map<int, double> _cosine(String text, List<int> candidates, {double minScore = 0.12}) {
    final qv = embedder.embed(text);
    final scores = <int, double>{};
    for (final doc in candidates) {
      final dv = _vectors[doc]!;
      var dot = 0.0;
      for (var i = 0; i < qv.length; i++) {
        dot += qv[i] * dv[i];
      }
      if (dot >= minScore) scores[doc] = dot;
    }
    return scores;
  }

  /// Picks the sentence that best covers the query (terms and concepts).
  String? bestPassage(String text, String query, {int scan = 60000}) {
    if (text.isEmpty) return null;
    final qTerms = TextTools.terms(query).toSet();
    if (qTerms.isEmpty) return null;
    final qVec = embedder.embed(query);
    String? best;
    var bestScore = 0.0;
    for (final s in TextTools.sentences(text.length > scan ? text.substring(0, scan) : text)) {
      if (s.length > 400 || s.split(' ').length < 6) continue;
      final overlap = TextTools.terms(s).toSet().intersection(qTerms).length;
      if (overlap == 0) continue;
      final v = embedder.embed(s);
      var dot = 0.0;
      for (var i = 0; i < v.length; i++) {
        dot += v[i] * qVec[i];
      }
      final score = overlap + dot;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }
}
