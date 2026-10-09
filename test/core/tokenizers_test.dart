// Checks the Dart tokenizers against token ids produced by the Python
// `tokenizers` library (tool/model_probe.py writes the fixtures in CI).
// Skipped when the fixtures are not present, e.g. on a developer machine.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/tokenizers.dart';

void main() {
  final fixtures = File('build/eval/tokenizer_fixtures.json');
  for (final slug in ['e5-small', 'embeddinggemma']) {
    final tokFile = File('build/models/$slug/tokenizer.json');
    final available = fixtures.existsSync() && tokFile.existsSync();
    test('$slug tokenizer matches the reference token ids', () {
      final tokenizer = Tokenizer.fromJsonString(tokFile.readAsStringSync());
      final cases = ((jsonDecode(fixtures.readAsStringSync()) as Map)[slug] as List).cast<Map>();
      final failures = <String>[];
      final watch = Stopwatch()..start();
      for (final c in cases) {
        final text = c['text'] as String;
        final want = (c['ids'] as List).cast<int>();
        final got = tokenizer.encode(text, maxLength: 512);
        if (!const ListEquality().equals(got, want)) {
          var i = 0;
          while (i < got.length && i < want.length && got[i] == want[i]) {
            i++;
          }
          final shown = text.length > 80 ? '${text.substring(0, 80)}…' : text;
          failures.add('"$shown": first difference at token $i: '
              'got ${got.skip(i).take(6).toList()}, want ${want.skip(i).take(6).toList()} '
              '(lengths ${got.length} vs ${want.length})');
        }
      }
      // ignore: avoid_print
      print('$slug: ${cases.length - failures.length}/${cases.length} exact, '
          '${(watch.elapsedMicroseconds / 1000 / cases.length).toStringAsFixed(2)} ms per text');
      expect(failures, isEmpty, reason: failures.take(12).join('\n'));
    }, skip: available ? false : 'tokenizer fixtures not generated (run tool/model_probe.py)');
  }
}

class ListEquality {
  const ListEquality();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
