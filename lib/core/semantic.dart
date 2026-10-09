/// On-device search models: what they are, what text they see, and how
/// their vectors are ranked and scored. Pure Dart; the ONNX Runtime part
/// lives in lib/app/model_runtime.dart behind [EmbeddingModel].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'cataloguer.dart';
import 'library.dart';
import 'record.dart';
import 'sample/corpus.dart';
import 'search.dart';

enum Pooling { mean, sentenceEmbedding }

class ModelFile {
  const ModelFile(this.path, this.approxMb);
  final String path;
  final double approxMb;
}

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.repo,
    required this.files,
    required this.onnxPath,
    required this.queryTemplate,
    required this.docTemplate,
    required this.pooling,
    required this.licence,
    required this.licenceUrl,
    required this.note,
    this.maxTokens = 512,
  });

  final String id;
  final String name;
  final String repo;
  final List<ModelFile> files;
  final String onnxPath;
  final String queryTemplate; // {q}
  final String docTemplate; // {title}, {text}
  final Pooling pooling;
  final String licence;
  final String licenceUrl;
  final String note;

  /// Input length used on the phone (tokens, special tokens included).
  final int maxTokens;

  double get downloadMb => files.fold(0, (a, f) => a + f.approxMb);

  Uri url(ModelFile f) => Uri.parse('https://huggingface.co/$repo/resolve/main/${f.path}');

  String query(String q) => queryTemplate.replaceAll('{q}', q);
  String document(String title, String text) =>
      docTemplate.replaceAll('{title}', title).replaceAll('{text}', text);

  static const e5Small = ModelSpec(
    id: 'e5-small',
    name: 'multilingual-E5-small',
    repo: 'Xenova/multilingual-e5-small',
    files: [ModelFile('onnx/model_quantized.onnx', 118.3), ModelFile('tokenizer.json', 17.1)],
    onnxPath: 'onnx/model_quantized.onnx',
    queryTemplate: 'query: {q}',
    docTemplate: 'passage: {title}. {text}',
    pooling: Pooling.mean,
    licence: 'MIT',
    licenceUrl: 'https://huggingface.co/intfloat/multilingual-e5-small',
    note: '118M parameters · 384 dimensions · about 100 languages',
  );

  static const embeddingGemma = ModelSpec(
    id: 'embeddinggemma',
    name: 'EmbeddingGemma 300M',
    repo: 'onnx-community/embeddinggemma-300m-ONNX',
    files: [
      ModelFile('onnx/model_quantized.onnx', 0.6),
      ModelFile('onnx/model_quantized.onnx_data', 308.9),
      ModelFile('tokenizer.json', 20.3),
    ],
    onnxPath: 'onnx/model_quantized.onnx',
    queryTemplate: 'task: search result | query: {q}',
    docTemplate: 'title: {title} | text: {text}',
    pooling: Pooling.sentenceEmbedding,
    licence: 'Gemma Terms of Use',
    licenceUrl: 'https://ai.google.dev/gemma/terms',
    note: '308M parameters · 768 dimensions · 100+ languages',
  );

  static const all = [e5Small, embeddingGemma];

  static ModelSpec? byId(String? id) => all.where((m) => m.id == id).firstOrNull;
}

abstract class EmbeddingModel {
  ModelSpec get spec;

  /// Unit-length vectors, one per text.
  Future<Float32List> embed(String text);
  Future<void> close();
}

/// The text a model sees for a record: title plus creators, subjects,
/// description and the start of the body text.
({String title, String text}) documentFields(CatalogueRecord r) => (
      title: r.title,
      text: [
        r.texts(Dc.creator).join(', '),
        r.texts(Dc.subject).join('; '),
        r.text(Dc.description),
        r.textContent.length > 6000 ? r.textContent.substring(0, 6000) : r.textContent,
      ].where((s) => s.trim().isNotEmpty).join('\n'),
    );

/// A short signature of the text a record's vector was made from, so a
/// stored vector is recomputed when the record changes.
String documentSignature(CatalogueRecord r) {
  final f = documentFields(r);
  var h = 0x811c9dc5;
  for (final c in '${f.title}\u0000${f.text}'.codeUnits) {
    h ^= c;
    h = ((h * 0x193) + ((h << 24) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

Float32List normalize(List<double> v) {
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  final out = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = n == 0 ? 0 : v[i] / n;
  }
  return out;
}

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// Record ids ordered by similarity to [query], best first.
List<String> rankBySimilarity(Float32List query, Map<String, Float32List> vectors, {int top = 20}) {
  final scored = [for (final e in vectors.entries) MapEntry(e.key, dot(query, e.value))]
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in scored.take(top)) e.key];
}

double ndcgAt(List<String> ranked, Map<String, int> rel, [int k = 10]) {
  double dcg(List<int> gains) {
    var s = 0.0;
    for (var i = 0; i < gains.length && i < k; i++) {
      s += (math.pow(2, gains[i]) - 1) / (math.log(i + 2) / math.ln2);
    }
    return s;
  }

  final ideal = dcg(rel.values.toList()..sort((a, b) => b.compareTo(a)));
  return ideal == 0 ? 0 : dcg([for (final k in ranked) rel[k] ?? 0]) / ideal;
}

class ModelQuality {
  ModelQuality(this.ndcg, this.ndcgMeaning, this.top3, this.keywordNdcg);
  final double ndcg;
  final double ndcgMeaning;
  final double top3;
  final double keywordNdcg;
  double get lift => keywordNdcg == 0 ? 0 : (ndcg - keywordNdcg) / keywordNdcg;
}

class ModelTimings {
  final List<double> itemMs = [];
  final List<double> queryMs = [];
  double loadMs = 0;

  static double median(List<double> xs) {
    if (xs.isEmpty) return 0;
    final s = List.of(xs)..sort();
    return s[s.length ~/ 2];
  }
}

/// Embeds the 38 sample items and the judged queries with [model] and scores
/// hybrid search exactly as the app ranks it. Used by the Device check.
Future<(ModelQuality, ModelTimings)> evaluateModelOnSamples(EmbeddingModel model,
    {void Function(String)? progress}) async {
  final timings = ModelTimings();
  final lib = Library();
  final keyOf = <String, String>{};
  for (final s in SampleCorpus.curated()) {
    final r = lib.importFile(ImportedFile(s.fileName, s.bytes)).record;
    keyOf[r.id] = s.key;
  }
  final vectors = <String, Float32List>{};
  var done = 0;
  for (final r in lib.records) {
    final f = documentFields(r);
    final sw = Stopwatch()..start();
    vectors[r.id] = await model.embed(model.spec.document(f.title, f.text));
    timings.itemMs.add(sw.elapsedMicroseconds / 1000);
    progress?.call('Embedding sample items… ${++done}/${lib.records.length}');
  }
  var ndcg = 0.0, meaning = 0.0, meaningCount = 0, top3 = 0.0, keyword = 0.0;
  for (final q in SampleCorpus.queries) {
    final parsed = QueryParser.parse(q.query);
    final sw = Stopwatch()..start();
    final qv = await model.embed(model.spec.query(parsed.text.isEmpty ? q.query : parsed.text));
    timings.queryMs.add(sw.elapsedMicroseconds / 1000);
    final ranking = rankBySimilarity(qv, vectors);
    List<String> keys(SearchMode mode, List<String>? sem) => lib
        .search(q.query, mode: mode, limit: 10, semanticRanking: sem)
        .hits
        .map((h) => keyOf[h.record.id]!)
        .toList();
    final hybrid = keys(SearchMode.hybrid, ranking);
    final n = ndcgAt(hybrid, q.relevance);
    ndcg += n;
    if (q.kind == 'meaning') {
      meaning += n;
      meaningCount++;
    }
    if (hybrid.take(3).any((k) => q.relevance[k] == 2)) top3++;
    keyword += ndcgAt(keys(SearchMode.keyword, null), q.relevance);
  }
  final n = SampleCorpus.queries.length;
  return (
    ModelQuality(ndcg / n, meaningCount == 0 ? 0 : meaning / meaningCount, top3 / n, keyword / n),
    timings,
  );
}
