import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/benchmark.dart';

void main() {
  test('cataloguing stage reports a typical file and the 20-page PDF target', () {
    final rows = benchmarkCataloguing(1).map(BenchmarkRow.fromJson).toList();
    expect(rows, hasLength(2));
    expect(rows.last.metric, contains('20-page PDF'));
    expect(rows.last.met, isNotNull);
  });

  test('search stage reports latency; targets apply only at 20,000 items', () {
    final rows = benchmarkSearch(500).map(BenchmarkRow.fromJson).toList();
    expect(rows.map((r) => r.metric), contains('Keyword search p95, 500 items'));
    expect(rows.first.met, isNull, reason: 'a smaller index is not the spec test');
  });

  test('text summary lists device and every row', () {
    final text = benchmarkText(
      const [BenchmarkRow('Keyword search p95, 20,000 items', '12 ms', '≤ 150 ms', true)],
      {'Platform': 'android'},
    );
    expect(text, contains('Platform: android'));
    expect(text, contains('Keyword search p95, 20,000 items: 12 ms (target ≤ 150 ms, met)'));
  });
}
