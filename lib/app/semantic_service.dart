/// Manages the on-device search models: download, choice of model,
/// background indexing of the library, and ranking queries.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/record.dart';
import '../core/search.dart';
import '../core/semantic.dart';
import 'model_runtime.dart';

enum ModelState { notDownloaded, downloading, downloaded, error }

typedef ModelLoader = Future<EmbeddingModel> Function(ModelSpec spec, Directory dir);

class SemanticService extends ChangeNotifier {
  SemanticService({ModelLoader? loader, Future<Directory> Function()? baseDir})
      : _loader = loader ?? OnnxEmbeddingModel.load,
        _baseDir = baseDir ?? getApplicationDocumentsDirectory,
        enabled = !kIsWeb;

  /// No on-device models (tests, and the web build).
  SemanticService.disabled()
      : _loader = OnnxEmbeddingModel.load,
        _baseDir = getApplicationDocumentsDirectory,
        enabled = false;

  /// False where models cannot run; search then uses the built-in ranker.
  final bool enabled;

  final ModelLoader _loader;
  final Future<Directory> Function() _baseDir;

  final Map<String, ModelState> state = {for (final m in ModelSpec.all) m.id: ModelState.notDownloaded};
  final Map<String, double> progress = {};
  final Map<String, String> errors = {};

  /// null = the built-in ranker.
  String? activeId;
  EmbeddingModel? _model;
  Map<String, Float32List> _vectors = {};
  Map<String, String> _signatures = {};
  int indexed = 0;
  int toIndex = 0;
  bool indexing = false;
  int _indexGeneration = 0;

  ModelSpec? get active => ModelSpec.byId(activeId);
  bool get ready => _model != null && _vectors.isNotEmpty;

  Future<Directory> _dir(ModelSpec m) async => Directory('${(await _baseDir()).path}/models/${m.id}');
  Future<File> _settings() async => File('${(await _baseDir()).path}/models/settings.json');

  Future<void> start() async {
    if (!enabled) return;
    for (final m in ModelSpec.all) {
      if (await _isComplete(m)) state[m.id] = ModelState.downloaded;
    }
    try {
      final f = await _settings();
      if (await f.exists()) {
        final id = (jsonDecode(await f.readAsString()) as Map)['active'] as String?;
        if (ModelSpec.byId(id) != null && state[id] == ModelState.downloaded) activeId = id;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> _isComplete(ModelSpec m) async {
    final dir = await _dir(m);
    for (final f in m.files) {
      if (!await File('${dir.path}/${f.path}').exists()) return false;
    }
    return true;
  }

  /// Downloads every file of [m]. Files are written to a .part file and
  /// renamed when complete, so an interrupted download never looks finished.
  Future<void> download(ModelSpec m) async {
    if (state[m.id] == ModelState.downloading) return;
    state[m.id] = ModelState.downloading;
    errors.remove(m.id);
    progress[m.id] = 0;
    notifyListeners();
    final client = HttpClient();
    try {
      final dir = await _dir(m);
      final totalMb = m.downloadMb;
      var doneBytes = 0;
      for (final f in m.files) {
        final target = File('${dir.path}/${f.path}');
        if (await target.exists()) {
          doneBytes += await target.length();
          continue;
        }
        await target.parent.create(recursive: true);
        final part = File('${target.path}.part');
        final request = await client.getUrl(m.url(f));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('Download of ${f.path} failed (HTTP ${response.statusCode})');
        }
        final sink = part.openWrite();
        var lastNotify = DateTime.now();
        await for (final chunk in response) {
          sink.add(chunk);
          doneBytes += chunk.length;
          if (DateTime.now().difference(lastNotify).inMilliseconds > 250) {
            progress[m.id] = (doneBytes / 1e6 / totalMb).clamp(0.0, 1.0);
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
        await sink.close();
        await part.rename(target.path);
      }
      state[m.id] = ModelState.downloaded;
      progress[m.id] = 1;
    } catch (e) {
      state[m.id] = ModelState.error;
      errors[m.id] = '$e';
    } finally {
      client.close(force: true);
      notifyListeners();
    }
  }

  Future<void> delete(ModelSpec m) async {
    if (activeId == m.id) await choose(null, const []);
    final dir = await _dir(m);
    if (await dir.exists()) await dir.delete(recursive: true);
    state[m.id] = ModelState.notDownloaded;
    progress.remove(m.id);
    notifyListeners();
  }

  /// Switches the model used by search. Indexes [records] in the background.
  Future<void> choose(String? id, List<CatalogueRecord> records) async {
    _indexGeneration++;
    await _model?.close();
    _model = null;
    _vectors = {};
    _signatures = {};
    activeId = id;
    indexing = false;
    try {
      final f = await _settings();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'active': id}));
    } catch (_) {}
    notifyListeners();
    if (id != null) await _activate(records);
  }

  /// Call when the library changes so new or edited items get vectors.
  Future<void> sync(List<CatalogueRecord> records) async {
    if (!enabled) return;
    if (_model == null) {
      if (activeId != null) await _activate(records);
      return;
    }
    await _indexMissing(records);
  }

  /// The loaded model in use, if any.
  EmbeddingModel? get activeModel => _model;

  /// A model for the Device check: the one in use if it is [m], otherwise a
  /// fresh instance the caller must close.
  Future<EmbeddingModel?> loadForTest(ModelSpec m) async {
    if (state[m.id] != ModelState.downloaded) return null;
    if (_model != null && activeId == m.id) return _model;
    return _loader(m, await _dir(m));
  }

  Future<void> _activate(List<CatalogueRecord> records) async {
    final spec = active;
    if (spec == null || state[spec.id] != ModelState.downloaded) return;
    final generation = _indexGeneration;
    try {
      final model = await _loader(spec, await _dir(spec));
      if (generation != _indexGeneration) {
        await model.close();
        return;
      }
      _model = model;
      await _loadVectors(spec);
      await _indexMissing(records);
    } catch (e) {
      errors[spec.id] = 'Could not load the model: $e';
      notifyListeners();
    }
  }

  Future<File> _vectorFile(ModelSpec m) async => File('${(await _dir(m)).path}/vectors.json');

  Future<void> _loadVectors(ModelSpec m) async {
    try {
      final f = await _vectorFile(m);
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final e in data.entries) {
        final v = e.value as Map;
        _signatures[e.key] = v['s'] as String;
        _vectors[e.key] = Float32List.fromList((v['v'] as List).cast<num>().map((x) => x.toDouble()).toList());
      }
    } catch (_) {
      _vectors = {};
      _signatures = {};
    }
  }

  Future<void> _saveVectors(ModelSpec m) async {
    final f = await _vectorFile(m);
    await f.writeAsString(jsonEncode({
      for (final e in _vectors.entries) e.key: {'s': _signatures[e.key], 'v': e.value},
    }));
  }

  Future<void> _indexMissing(List<CatalogueRecord> records) async {
    final model = _model;
    final spec = active;
    if (model == null || spec == null || indexing) return;
    final generation = _indexGeneration;
    final ids = {for (final r in records) r.id};
    _vectors.removeWhere((id, _) => !ids.contains(id));
    final todo = [for (final r in records) if (_signatures[r.id] != documentSignature(r)) r];
    toIndex = records.length;
    indexed = records.length - todo.length;
    if (todo.isEmpty) {
      notifyListeners();
      return;
    }
    indexing = true;
    notifyListeners();
    var sinceSave = 0;
    for (final r in todo) {
      if (generation != _indexGeneration) return;
      final f = documentFields(r);
      try {
        _vectors[r.id] = await model.embed(spec.document(f.title, f.text));
        _signatures[r.id] = documentSignature(r);
      } catch (e) {
        errors[spec.id] = 'Indexing stopped: $e';
        break;
      }
      indexed++;
      if (++sinceSave >= 10) {
        sinceSave = 0;
        await _saveVectors(spec);
      }
      notifyListeners();
    }
    indexing = false;
    await _saveVectors(spec);
    notifyListeners();
  }

  /// Record ids ranked by the active model, or null to use the built-in ranker.
  Future<List<String>?> rank(String rawQuery) async {
    final model = _model;
    final spec = active;
    if (model == null || spec == null || _vectors.isEmpty) return null;
    final text = QueryParser.parse(rawQuery).text;
    if (text.trim().isEmpty) return null;
    final q = await model.embed(spec.query(text));
    return rankBySimilarity(q, _vectors);
  }

  String get statusLine {
    final spec = active;
    if (spec == null) return 'Built-in search';
    if (_model == null) return '${spec.name} · loading…';
    if (indexing) return '${spec.name} · indexing $indexed of $toIndex';
    return '${spec.name} · $indexed items indexed';
  }
}
