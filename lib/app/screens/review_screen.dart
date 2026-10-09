import 'package:flutter/material.dart';

import '../../core/record.dart';
import '../controller.dart';
import '../theme.dart';

/// Reviews AI/rules-drafted records one at a time (spec section 8, step 5).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.controller});
  final LibraryController controller;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const editable = [Dc.title, Dc.creator, Dc.date, Dc.subject, Dc.publisher, Dc.language, Dc.description];

  final Map<String, TextEditingController> _edit = {};
  String? _forId;
  final Set<String> _skipped = {};

  List<CatalogueRecord> get _queue =>
      widget.controller.drafts.where((r) => !_skipped.contains(r.id)).toList();

  void _load(CatalogueRecord r) {
    if (_forId == r.id) return;
    _forId = r.id;
    for (final c in _edit.values) {
      c.dispose();
    }
    _edit.clear();
    for (final e in editable) {
      _edit[e] = TextEditingController(text: r.texts(e).join('; '));
    }
  }

  @override
  void dispose() {
    for (final c in _edit.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _accept(CatalogueRecord r) async {
    final c = widget.controller;
    for (final e in editable) {
      final now = _edit[e]!.text.trim();
      if (now != r.texts(e).join('; ')) await c.setField(r, e, now);
    }
    await c.confirm(r);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Saved “${r.title}”')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final queue = _queue;
        if (queue.isEmpty) {
          // Scrollable so the message never overflows at large text sizes.
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.task_alt, size: 48, color: IpesColors.good),
                const SizedBox(height: 12),
                Text(_skipped.isEmpty ? 'Nothing to review' : 'All done except what you skipped',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('New items are drafted on your device and wait here for you to check.',
                    textAlign: TextAlign.center, style: TextStyle(color: IpesColors.muted)),
                if (_skipped.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_skipped.clear),
                    child: Text('Review ${_skipped.length} skipped ${_skipped.length == 1 ? 'item' : 'items'}'),
                  ),
              ]),
            ),
          );
        }
        final r = queue.first;
        _load(r);
        final total = widget.controller.drafts.length;
        return Column(children: [
          Expanded(
            child: ListView(
          key: const Key('review-list'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [
              Expanded(
                child: Text('Review draft',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('${total - queue.length + 1} of $total', style: monoStyle),
            ]),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: MediaTile(r, width: 40, height: 52),
                title: Text(r.fileName, style: monoStyle),
                subtitle: Text(
                    'Drafted on this device · ${r.textContent.isEmpty ? 'metadata only' : '${r.textContent.length} characters of text read'}'),
              ),
            ),
            const SizedBox(height: 12),
            for (final e in editable) _field(r, e),
            const SizedBox(height: 4),
            const Row(children: [
              SizedBox(width: 12, height: 12, child: ColoredBox(color: IpesColors.warn)),
              SizedBox(width: 8),
              Expanded(
                child: Text('Highlighted fields are below 0.70 confidence — please check.',
                    style: TextStyle(fontSize: 12, color: IpesColors.muted)),
              ),
            ]),
            if (r.classSuggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Suggested Dewey class · tap to accept', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in r.classSuggestions)
                  FilterChip(
                    label: Text('${s.number} ${s.label} · ${(s.confidence * 100).round()}%'),
                    selected: r.classNumber == s.number,
                    onSelected: (on) => widget.controller.setClass(r, on ? s.number : null),
                  ),
              ]),
            ],
          ],
            ),
          ),
          // Fixed action bar: always reachable, even with the keyboard up.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: IpesColors.line)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _skipped.add(r.id)),
                  child: const Text('Skip for now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('accept-draft'),
                  onPressed: () => _accept(r),
                  child: const Text('Accept & save'),
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _field(CatalogueRecord r, String e) {
    final values = r.all(e);
    final weak = values.any((v) => v.confidence < CatalogueRecord.reviewThreshold);
    final hint = values.isEmpty
        ? 'Not found — add it if you know it'
        : '${values.first.source.label} · ${values.first.confidence.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: Key('field-$e'),
        controller: _edit[e],
        minLines: 1,
        maxLines: e == Dc.description ? 4 : 1,
        decoration: InputDecoration(
          labelText: e == Dc.language ? 'Language (ISO 639-2 code)' : Dc.label(e),
          helperText: (e == Dc.subject || e == Dc.creator) ? '$hint · separate with ;' : hint,
          filled: true,
          fillColor: weak ? IpesColors.warn : Colors.white,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
