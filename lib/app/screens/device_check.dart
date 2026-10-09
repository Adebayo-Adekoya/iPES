import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/benchmark.dart';
import '../../core/semantic.dart';
import '../semantic_service.dart';
import '../shell.dart';
import '../startup.dart';
import '../theme.dart';

typedef Stage = List<Map<String, Object?>> Function(int arg);

/// Runs a stage. In the app this is Flutter's `compute`, which uses a
/// background isolate so the screen stays responsive.
typedef StageRunner = Future<List<Map<String, Object?>>> Function(Stage stage, int arg);

Future<List<Map<String, Object?>>> runInBackground(Stage stage, int arg) => compute(stage, arg);

/// Measures this device against the spec's performance targets (section 10).
class DeviceCheckPage extends StatefulWidget {
  const DeviceCheckPage({super.key, this.runner = runInBackground, this.searchItems = 20000, this.semantic});
  final StageRunner runner;
  final int searchItems;

  /// When given, downloaded search models are tested too.
  final SemanticService? semantic;

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage> {
  String? running;
  List<BenchmarkRow> rows = [];
  String? error;

  Map<String, String> _device(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return {
      'Platform': kIsWeb ? 'web (${defaultTargetPlatform.name})' : defaultTargetPlatform.name,
      'Build': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'Screen': '${size.width.round()} × ${size.height.round()} dp at ${mq.devicePixelRatio.toStringAsFixed(1)}x '
          '(${windowSizeOf(size.width).name})',
    };
  }

  List<BenchmarkRow> _startupRows() => [
        if (Startup.firstFrameMs != null)
          BenchmarkRow('Start to first frame (this launch)', '${Startup.firstFrameMs!.round()} ms', '≤ 1.5 s',
              Startup.firstFrameMs! <= 1500),
        if (Startup.libraryReadyMs != null)
          BenchmarkRow(
            Startup.firstLaunch
                ? 'Start to library shown (first launch, builds the sample library)'
                : 'Start to library shown',
            '${Startup.libraryReadyMs!.round()} ms',
            '≤ 1.5 s',
            Startup.firstLaunch ? null : Startup.libraryReadyMs! <= 1500,
          ),
      ];

  Future<void> _run() async {
    setState(() {
      rows = _startupRows();
      error = null;
      running = 'Cataloguing 38 sample files…';
    });
    try {
      final cat = await widget.runner(benchmarkCataloguing, 3);
      if (!mounted) return;
      setState(() {
        rows = [...rows, ...cat.map(BenchmarkRow.fromJson)];
        running = 'Searching ${widget.searchItems} records… (about a minute on older phones)';
      });
      final search = await widget.runner(benchmarkSearch, widget.searchItems);
      if (!mounted) return;
      setState(() => rows = [...rows, ...search.map(BenchmarkRow.fromJson)]);
      await _runModels();
      if (!mounted) return;
      setState(() => running = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'The check stopped: $e';
        running = null;
      });
    }
  }

  /// Tests each downloaded search model: load time, agreement with the
  /// reference vectors computed in CI, speed, and search quality on the
  /// sample library with the judged queries.
  Future<void> _runModels() async {
    final s = widget.semantic;
    if (s == null || !s.enabled) return;
    Map<String, dynamic> reference = {};
    try {
      reference = jsonDecode(await rootBundle.loadString('assets/model_reference.json')) as Map<String, dynamic>;
    } catch (_) {}
    for (final spec in ModelSpec.all) {
      if (!mounted) return;
      if (s.state[spec.id] != ModelState.downloaded) {
        setState(() => rows = [
              ...rows,
              BenchmarkRow('${spec.name}: not downloaded (Search › Search model)', '—', '—', null),
            ]);
        continue;
      }
      setState(() => running = 'Loading ${spec.name}…');
      final loadWatch = Stopwatch()..start();
      final model = await s.loadForTest(spec);
      if (model == null) continue;
      final loadMs = loadWatch.elapsedMicroseconds / 1000;
      final owned = !identical(model, s.activeModel);
      try {
        var minCos = 1.0;
        final ref = reference[spec.id] as Map<String, dynamic>?;
        if (ref != null) {
          final texts = (ref['texts'] as List).cast<String>();
          final vectors = ref['vectors'] as List;
          for (var i = 0; i < texts.length; i++) {
            final v = await model.embed(texts[i]);
            final want = Float32List.fromList((vectors[i] as List).cast<num>().map((x) => x.toDouble()).toList());
            final c = dot(v, want);
            if (c < minCos) minCos = c;
          }
        }
        final (quality, timings) = await evaluateModelOnSamples(model, progress: (p) {
          if (mounted) setState(() => running = '${spec.name}: $p');
        });
        final item = ModelTimings.median(timings.itemMs);
        final query = ModelTimings.median(timings.queryMs);
        String ms(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(2)} s' : '${v.round()} ms';
        String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
        if (!mounted) return;
        setState(() => rows = [
              ...rows,
              BenchmarkRow('${spec.name}: load model', ms(loadMs), '—', null),
              if (ref != null)
                BenchmarkRow('${spec.name}: matches reference (lowest cosine of 6)', minCos.toStringAsFixed(4), '≥ 0.99',
                    minCos >= 0.99),
              BenchmarkRow('${spec.name}: embed one item (median of 38)', ms(item), '—', null),
              BenchmarkRow('${spec.name}: embed one query (median of 38)', ms(query), '—', null),
              BenchmarkRow('${spec.name}: index 1,000 items (estimate)', ms(item * 1000), '—', null),
              BenchmarkRow('${spec.name}: search quality nDCG@10', quality.ndcg.toStringAsFixed(3), '≥ 0.90 (proposed)',
                  quality.ndcg >= 0.90),
              BenchmarkRow('${spec.name}: different-wording queries nDCG@10', quality.ndcgMeaning.toStringAsFixed(3),
                  '≥ 0.85 (proposed)', quality.ndcgMeaning >= 0.85),
              BenchmarkRow('${spec.name}: known item in top 3', pct(quality.top3), '≥ 90%', quality.top3 >= 0.9),
              BenchmarkRow('${spec.name}: lift over keyword search', pct(quality.lift), '≥ 15%', quality.lift >= 0.15),
            ]);
      } catch (e) {
        if (mounted) setState(() => rows = [...rows, BenchmarkRow('${spec.name}: test failed — $e', '—', '—', false)]);
      } finally {
        if (owned) await model.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device(context);
    final done = running == null && rows.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Device check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Measures this phone or tablet against the iPES performance targets. '
            'Close other apps first. Nothing leaves the device.',
            style: TextStyle(color: IpesColors.muted),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in device.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 13)),
                  ),
                if (!kReleaseMode)
                  const Text('This is not a release build, so timings will be slower than real use.',
                      style: TextStyle(fontSize: 13, color: IpesColors.warnInk)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('run-device-check'),
            onPressed: running == null ? _run : null,
            icon: const Icon(Icons.speed),
            label: Text(rows.isEmpty ? 'Run device check' : 'Run again'),
          ),
          if (running != null) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(running!, style: const TextStyle(color: IpesColors.muted)),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                for (final r in rows)
                  Padding(
                    key: Key('row-${r.metric}'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.metric, style: const TextStyle(fontSize: 14)),
                          Text('Target ${r.target}', style: const TextStyle(fontSize: 12, color: IpesColors.muted)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(r.measured,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                        _StatusChip(r.met),
                      ]),
                    ]),
                  ),
              ]),
            ),
          ],
          if (done) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('copy-results'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: benchmarkText(rows, device)));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Results copied — paste them into your message')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy results'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.met);
  final bool? met;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (met) {
      true => ('Met', const Color(0xFFD8F0EC), IpesColors.good),
      false => ('Not met', IpesColors.warn, IpesColors.warnInk),
      null => ('Info', const Color(0xFFE2E8F3), IpesColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
