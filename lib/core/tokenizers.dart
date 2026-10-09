/// Tokenizers for the on-device search models, read from Hugging Face
/// tokenizer.json files. Pure Dart ports of the parts of the `tokenizers`
/// library these two models use, verified token-for-token against the
/// Python library in CI (test/core/tokenizers_test.dart).
///
/// - [UnigramTokenizer]: XLM-RoBERTa style (multilingual-E5-small):
///   SentencePiece precompiled normaliser, Metaspace, Unigram (Viterbi).
/// - [BpeTokenizer]: Gemma style (EmbeddingGemma): spaces to "▁", byte-level
///   fallback BPE with ranked merges.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';

abstract class Tokenizer {
  /// Token ids including the model's special tokens, truncated so the whole
  /// sequence (special tokens included) is at most [maxLength] long.
  List<int> encode(String text, {int maxLength});

  int get padId;

  /// Builds the right tokenizer for a tokenizer.json document.
  static Tokenizer fromJson(Map<String, dynamic> json) {
    final type = (json['model'] as Map)['type'];
    return switch (type) {
      'Unigram' => UnigramTokenizer.fromJson(json),
      'BPE' => BpeTokenizer.fromJson(json),
      _ => throw UnsupportedError('Tokenizer model "$type" is not supported'),
    };
  }

  static Tokenizer fromJsonString(String text) => fromJson(jsonDecode(text) as Map<String, dynamic>);
}

/// Special tokens added around the sequence by TemplateProcessing.
class _Template {
  _Template(this.prefix, this.suffix);
  final List<int> prefix;
  final List<int> suffix;

  factory _Template.fromJson(Map<String, dynamic>? post) {
    if (post == null || post['type'] != 'TemplateProcessing') return _Template([], []);
    final special = (post['special_tokens'] as Map).cast<String, dynamic>();
    final prefix = <int>[], suffix = <int>[];
    var seenSequence = false;
    for (final item in post['single'] as List) {
      final m = (item as Map).cast<String, dynamic>();
      if (m.containsKey('Sequence')) {
        seenSequence = true;
      } else if (m.containsKey('SpecialToken')) {
        final id = (m['SpecialToken'] as Map)['id'] as String;
        final ids = ((special[id] as Map)['ids'] as List).cast<int>();
        (seenSequence ? suffix : prefix).addAll(ids);
      }
    }
    return _Template(prefix, suffix);
  }

  List<int> apply(List<int> ids, int maxLength) {
    final room = math.max(0, maxLength - prefix.length - suffix.length);
    return [...prefix, ...(ids.length > room ? ids.sublist(0, room) : ids), ...suffix];
  }
}

// ---------------------------------------------------------------------------
// SentencePiece precompiled character map (Darts-clone double array trie).

class PrecompiledCharsMap {
  PrecompiledCharsMap(Uint8List blob) {
    final view = ByteData.sublistView(blob);
    final trieSize = view.getUint32(0, Endian.little);
    final units = trieSize ~/ 4;
    _array = Uint32List(units);
    for (var i = 0; i < units; i++) {
      _array[i] = view.getUint32(4 + i * 4, Endian.little);
    }
    _normalized = Uint8List.sublistView(blob, 4 + trieSize);
  }

  late final Uint32List _array;
  late final Uint8List _normalized;

  static bool _hasLeaf(int unit) => ((unit >> 8) & 1) == 1;
  static int _value(int unit) => unit & 0x7FFFFFFF;
  static int _label(int unit) => unit & 0x800000FF;
  static int _offset(int unit) => (unit >> 10) << ((unit & (1 << 9)) >> 6);

  /// Same as spm_precompiled's common_prefix_search: values of every
  /// prefix of [key] that is in the trie, shortest first.
  List<int> _prefixSearch(List<int> key) {
    var pos = 0;
    final results = <int>[];
    var unit = _array[pos];
    pos ^= _offset(unit);
    for (final c in key) {
      if (c == 0) break;
      pos ^= c;
      if (pos >= _array.length) return results;
      unit = _array[pos];
      if (_label(unit) != c) return results;
      pos ^= _offset(unit);
      if (_hasLeaf(unit)) results.add(_value(_array[pos]));
    }
    return results;
  }

  String? _transform(String chunk) {
    final results = _prefixSearch(utf8.encode(chunk));
    if (results.isEmpty) return null;
    final start = results.first;
    var end = start;
    while (end < _normalized.length && _normalized[end] != 0) {
      end++;
    }
    return utf8.decode(_normalized.sublist(start, end), allowMalformed: true);
  }

  /// Applies the map grapheme by grapheme, as the tokenizers library does.
  String normalize(String text) {
    final out = StringBuffer();
    for (final grapheme in text.characters) {
      if (utf8.encode(grapheme).length < 6) {
        final whole = _transform(grapheme);
        if (whole != null) {
          out.write(whole);
          continue;
        }
      }
      for (final rune in grapheme.runes) {
        final ch = String.fromCharCode(rune);
        out.write(_transform(ch) ?? ch);
      }
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------------------
// Unigram (XLM-RoBERTa / multilingual-E5).

class UnigramTokenizer implements Tokenizer {
  UnigramTokenizer._(this._ids, this._scores, this._unkId, this._minScore, this._maxPieceRunes, this._charsMap,
      this._collapseSpaces, this._template, this.padId);

  factory UnigramTokenizer.fromJson(Map<String, dynamic> json) {
    final model = (json['model'] as Map).cast<String, dynamic>();
    final vocab = model['vocab'] as List;
    final ids = <String, int>{};
    final scores = Float64List(vocab.length);
    var minScore = double.infinity;
    var maxRunes = 1;
    for (var i = 0; i < vocab.length; i++) {
      final entry = vocab[i] as List;
      final piece = entry[0] as String;
      final score = (entry[1] as num).toDouble();
      ids.putIfAbsent(piece, () => i);
      scores[i] = score;
      if (score < minScore) minScore = score;
      final runes = piece.runes.length;
      if (runes > maxRunes) maxRunes = runes;
    }
    PrecompiledCharsMap? charsMap;
    var collapse = false;
    final norm = json['normalizer'] as Map?;
    final normalizers = norm == null
        ? const []
        : (norm['type'] == 'Sequence' ? norm['normalizers'] as List : [norm]);
    for (final n in normalizers) {
      final m = (n as Map).cast<String, dynamic>();
      if (m['type'] == 'Precompiled' && m['precompiled_charsmap'] != null) {
        charsMap = PrecompiledCharsMap(base64.decode(m['precompiled_charsmap'] as String));
      } else if (m['type'] == 'Replace') {
        collapse = true; // " {2,}" -> " "
      }
    }
    final pad = ids['<pad>'] ?? 1;
    return UnigramTokenizer._(ids, scores, model['unk_id'] as int? ?? 0, minScore, maxRunes, charsMap, collapse,
        _Template.fromJson((json['post_processor'] as Map?)?.cast<String, dynamic>()), pad);
  }

  final Map<String, int> _ids;
  final Float64List _scores;
  final int _unkId;
  final double _minScore;
  final int _maxPieceRunes;
  final PrecompiledCharsMap? _charsMap;
  final bool _collapseSpaces;
  final _Template _template;

  @override
  final int padId;

  static const _unkPenalty = 10.0;

  String _normalize(String text) {
    var s = _charsMap?.normalize(text) ?? text;
    if (_collapseSpaces) s = s.replaceAll(RegExp(r' {2,}'), ' ');
    return s;
  }

  /// Metaspace (replacement "▁", add_prefix_space): spaces become "▁", a
  /// leading "▁" is added, and the text is split before each "▁".
  List<String> _preTokenize(String text) {
    if (text.isEmpty) return const [];
    var s = text.replaceAll(' ', '▁');
    if (!s.startsWith('▁')) s = '▁$s';
    final pieces = <String>[];
    var start = 0;
    for (var i = 1; i < s.length; i++) {
      if (s.codeUnitAt(i) == 0x2581) {
        pieces.add(s.substring(start, i));
        start = i;
      }
    }
    pieces.add(s.substring(start));
    return pieces;
  }

  /// Viterbi segmentation of one piece; unknown runs are fused into one unk.
  List<int> _encodePiece(String piece) {
    final runes = piece.runes.toList();
    final n = runes.length;
    final bestScore = Float64List(n + 1);
    final startAt = Int32List(n + 1)..fillRange(0, n + 1, -1);
    final idAt = Int32List(n + 1);
    startAt[0] = 0;
    final unkScore = _minScore - _unkPenalty;
    for (var s = 0; s < n; s++) {
      if (startAt[s] < 0 && s != 0) continue;
      final base = bestScore[s];
      var hasSingle = false;
      final maxLen = math.min(_maxPieceRunes, n - s);
      for (var len = 1; len <= maxLen; len++) {
        final id = _ids[String.fromCharCodes(runes, s, s + len)];
        if (id == null) continue;
        final e = s + len;
        final cand = base + _scores[id];
        if (startAt[e] < 0 || cand > bestScore[e]) {
          bestScore[e] = cand;
          startAt[e] = s;
          idAt[e] = id;
        }
        if (len == 1) hasSingle = true;
      }
      if (!hasSingle) {
        final e = s + 1;
        final cand = base + unkScore;
        if (startAt[e] < 0 || cand > bestScore[e]) {
          bestScore[e] = cand;
          startAt[e] = s;
          idAt[e] = _unkId;
        }
      }
    }
    final out = <int>[];
    var e = n;
    var inUnk = false;
    while (e > 0) {
      final s = startAt[e];
      final id = idAt[e];
      if (id == _unkId) {
        if (!inUnk) out.add(_unkId);
        inUnk = true;
      } else {
        inUnk = false;
        out.add(id);
      }
      e = s;
    }
    return out.reversed.toList();
  }

  @override
  List<int> encode(String text, {int maxLength = 512}) {
    final budget = maxLength - _template.prefix.length - _template.suffix.length;
    final ids = <int>[];
    for (final piece in _preTokenize(_normalize(text))) {
      ids.addAll(_encodePiece(piece));
      if (ids.length >= budget) break;
    }
    return _template.apply(ids, maxLength);
  }
}

// ---------------------------------------------------------------------------
// Byte-fallback BPE (Gemma / EmbeddingGemma).

class _Merge {
  _Merge(this.pos, this.rank, this.newId);
  final int pos;
  final int rank;
  final int newId;
}

class BpeTokenizer implements Tokenizer {
  BpeTokenizer._(this._vocab, this._merges, this._byteIds, this._unkId, this._template, this.padId);

  factory BpeTokenizer.fromJson(Map<String, dynamic> json) {
    final model = (json['model'] as Map).cast<String, dynamic>();
    final vocab = (model['vocab'] as Map).map((k, v) => MapEntry(k as String, v as int));
    final merges = <int, int>{};
    final list = model['merges'] as List;
    for (var rank = 0; rank < list.length; rank++) {
      final m = list[rank];
      final String a, b;
      if (m is List) {
        a = m[0] as String;
        b = m[1] as String;
      } else {
        final s = m as String;
        final sp = s.indexOf(' ');
        a = s.substring(0, sp);
        b = s.substring(sp + 1);
      }
      final ia = vocab[a], ib = vocab[b], inew = vocab[a + b];
      if (ia == null || ib == null || inew == null) continue;
      merges.putIfAbsent(_key(ia, ib), () => rank * _idSpace + inew);
    }
    final byteIds = Int32List(256);
    for (var b = 0; b < 256; b++) {
      byteIds[b] = vocab['<0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}>'] ?? -1;
    }
    final unk = vocab[model['unk_token'] as String? ?? '<unk>'] ?? 0;
    return BpeTokenizer._(vocab, merges, byteIds, unk,
        _Template.fromJson((json['post_processor'] as Map?)?.cast<String, dynamic>()), vocab['<pad>'] ?? 0);
  }

  static const _idSpace = 1 << 20; // larger than any vocabulary here
  static int _key(int a, int b) => a * _idSpace + b;

  final Map<String, int> _vocab;
  final Map<int, int> _merges; // (a,b) -> rank * _idSpace + newId
  final Int32List _byteIds;
  final int _unkId;
  final _Template _template;

  @override
  final int padId;

  @override
  List<int> encode(String text, {int maxLength = 2048}) {
    // Only the first tokens are kept, so very long text is cut well past
    // the point that can affect them.
    final limit = maxLength * 12;
    final s = (text.length > limit ? text.substring(0, limit) : text).replaceAll(' ', '▁');
    return _template.apply(_bpe(s), maxLength);
  }

  List<int> _bpe(String word) {
    // Initial symbols: characters, or their UTF-8 bytes when not in vocab.
    final ids = <int>[];
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      final id = _vocab[ch];
      if (id != null) {
        ids.add(id);
        continue;
      }
      final bytes = utf8.encode(ch);
      final fallback = [for (final b in bytes) _byteIds[b]];
      if (fallback.every((x) => x >= 0)) {
        ids.addAll(fallback);
      } else if (ids.isEmpty || ids.last != _unkId) {
        ids.add(_unkId);
      }
    }
    final n = ids.length;
    if (n < 2) return ids;
    final prev = Int32List(n), next = Int32List(n);
    final alive = List<bool>.filled(n, true);
    for (var i = 0; i < n; i++) {
      prev[i] = i - 1;
      next[i] = i + 1 < n ? i + 1 : -1;
    }
    final queue = HeapPriorityQueue<_Merge>((x, y) => x.rank != y.rank ? x.rank - y.rank : x.pos - y.pos);
    void consider(int left) {
      final right = next[left];
      if (right < 0) return;
      final m = _merges[_key(ids[left], ids[right])];
      if (m != null) queue.add(_Merge(left, m ~/ _idSpace, m % _idSpace));
    }

    for (var i = 0; i < n - 1; i++) {
      consider(i);
    }
    while (queue.isNotEmpty) {
      final top = queue.removeFirst();
      if (!alive[top.pos]) continue;
      final right = next[top.pos];
      if (right < 0) continue;
      final m = _merges[_key(ids[top.pos], ids[right])];
      if (m == null || m % _idSpace != top.newId) continue;
      ids[top.pos] = top.newId;
      alive[right] = false;
      final after = next[right];
      next[top.pos] = after;
      if (after >= 0) prev[after] = top.pos;
      if (prev[top.pos] >= 0) consider(prev[top.pos]);
      consider(top.pos);
    }
    return [for (var i = 0; i < n; i++) if (alive[i]) ids[i]];
  }
}
