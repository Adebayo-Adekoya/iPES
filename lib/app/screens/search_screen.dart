import 'package:flutter/material.dart';

import '../../core/record.dart';
import '../../core/search.dart';
import '../controller.dart';
import '../theme.dart';
import 'search_models.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller, required this.onOpen});
  final LibraryController controller;
  final void Function(CatalogueRecord) onOpen;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  SearchResult? _result;
  SearchMode _mode = SearchMode.hybrid;

  static const _examples = [
    'what does my lease say about notice',
    'videos from 2024',
    'cooking',
    'power bill',
  ];

  bool _busy = false;

  Future<void> _run([String? q]) async {
    if (q != null) _query.text = q;
    final text = _query.text.trim();
    if (text.isEmpty) {
      setState(() => _result = null);
      return;
    }
    setState(() => _busy = true);
    final result = await widget.controller.smartSearch(text, mode: _mode);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final best = result?.hits.where((h) => h.passage != null).firstOrNull;
    return ListView(
      key: const Key('search-list'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        TextField(
          key: const Key('search-field'),
          controller: _query,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Ask your library anything…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
                tooltip: 'Search', onPressed: _run, icon: const Icon(Icons.arrow_forward)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<SearchMode>(
          segments: const [
            ButtonSegment(value: SearchMode.hybrid, label: Text('Smart', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(value: SearchMode.keyword, label: Text('Keywords', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            _mode = s.first;
            _run();
          },
        ),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: widget.controller.semantic,
          builder: (context, _) => Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('search-model-button'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SearchModelsPage(controller: widget.controller),
              )),
              icon: const Icon(Icons.memory, size: 18),
              label: Text(widget.controller.semantic.statusLine),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 4),
        if (result == null) ...[
          const Text('Try', style: TextStyle(color: IpesColors.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _examples) ActionChip(label: Text(e), onPressed: () => _run(e)),
          ]),
        ] else ...[
          if (result.query.facetLabels.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Understood as', style: TextStyle(fontSize: 12, color: IpesColors.muted)),
              for (final f in result.query.facetLabels)
                Chip(label: Text(f), visualDensity: VisualDensity.compact),
            ]),
          const SizedBox(height: 8),
          if (best != null) _passageCard(best),
          const SizedBox(height: 12),
          Text('${result.hits.length} results · ${result.elapsed.inMicroseconds / 1000} ms on this device',
              key: const Key('result-count'), style: const TextStyle(fontSize: 12, color: IpesColors.muted)),
          const SizedBox(height: 8),
          for (final h in result.hits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  key: Key('hit-${h.record.id}'),
                  onTap: () => widget.onOpen(h.record),
                  leading: MediaTile(h.record, width: 40, height: 48),
                  title: Text(h.record.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(h.reasons.isEmpty ? h.record.mediaType.label : h.reasons.join(' · ')),
                ),
              ),
            ),
          if (result.hits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matches. Try fewer or different words.', textAlign: TextAlign.center),
            ),
        ],
      ],
    );
  }

  Widget _passageCard(SearchHit h) => Container(
        key: const Key('best-passage'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: IpesColors.ink, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BEST PASSAGE · ON-DEVICE',
              style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: IpesColors.accent)),
          const SizedBox(height: 8),
          Text('“${h.passage}”', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => widget.onOpen(h.record),
            style: TextButton.styleFrom(foregroundColor: Colors.white, padding: EdgeInsets.zero),
            child: Text('${h.record.title} ›'),
          ),
        ]),
      );
}
