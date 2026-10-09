/// Runs a search model with ONNX Runtime on the device.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../core/semantic.dart';
import '../core/tokenizers.dart';

class OnnxEmbeddingModel implements EmbeddingModel {
  OnnxEmbeddingModel._(this.spec, this._session, this._tokenizer, this._needsTokenTypes, this._hasSentenceOutput);

  /// Loads a downloaded model from [dir] (the folder holding its files).
  static Future<OnnxEmbeddingModel> load(ModelSpec spec, Directory dir) async {
    final tokenizerText = await File('${dir.path}/tokenizer.json').readAsString();
    // Parsing a 20 MB tokenizer is slow; do it off the UI thread.
    final tokenizer = await Isolate.run(() => Tokenizer.fromJsonString(tokenizerText));
    final cores = Platform.numberOfProcessors;
    final session = await OnnxRuntime().createSession(
      '${dir.path}/${spec.onnxPath}',
      options: OrtSessionOptions(intraOpNumThreads: cores >= 8 ? 4 : (cores >= 4 ? 2 : 1)),
    );
    return OnnxEmbeddingModel._(
      spec,
      session,
      tokenizer,
      session.inputNames.contains('token_type_ids'),
      session.outputNames.contains('sentence_embedding'),
    );
  }

  @override
  final ModelSpec spec;
  final OrtSession _session;
  final Tokenizer _tokenizer;
  final bool _needsTokenTypes;
  final bool _hasSentenceOutput;

  @override
  Future<Float32List> embed(String text) async {
    final ids = _tokenizer.encode(text, maxLength: spec.maxTokens);
    final n = ids.length;
    final inputs = <String, OrtValue>{
      'input_ids': await OrtValue.fromList(Int64List.fromList(ids), [1, n]),
      'attention_mask': await OrtValue.fromList(Int64List(n)..fillRange(0, n, 1), [1, n]),
      if (_needsTokenTypes) 'token_type_ids': await OrtValue.fromList(Int64List(n), [1, n]),
    };
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run(inputs);
      final List<double> vector;
      if (_hasSentenceOutput && spec.pooling == Pooling.sentenceEmbedding) {
        vector = (await outputs['sentence_embedding']!.asFlattenedList()).cast<num>().map((x) => x.toDouble()).toList();
      } else {
        // Mean of the token vectors (every token is real: no padding).
        final hidden = outputs['last_hidden_state'] ?? outputs.values.first;
        final flat = (await hidden.asFlattenedList()).cast<num>();
        final dims = flat.length ~/ n;
        final sum = List<double>.filled(dims, 0);
        for (var t = 0; t < n; t++) {
          for (var d = 0; d < dims; d++) {
            sum[d] += flat[t * dims + d].toDouble();
          }
        }
        vector = [for (final x in sum) x / n];
      }
      return normalize(vector);
    } finally {
      for (final v in inputs.values) {
        await v.dispose();
      }
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  @override
  Future<void> close() => _session.close();
}
