import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/citation.dart';
import '../../core/export/marc21.dart';
import '../../core/record.dart';
import '../controller.dart';
import '../theme.dart';
import 'export_sheet.dart';

/// One record: Simple (Dublin Core) and Expert (MARC 21) views, class
/// suggestions, cite and export. Used as a page on phones and as the
/// right-hand pane on tablets.
class RecordView extends StatefulWidget {
  const RecordView({super.key, required this.record, required this.controller});
  final CatalogueRecord record;
  final LibraryController controller;

  @override
  State<RecordView> createState() => _RecordViewState();
}

class _RecordViewState extends State<RecordView> {
  bool marc = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final c = widget.controller;
    return ListView(
      key: ValueKey('record-${r.id}'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MediaTile(r, width: 84, height: 112),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      key: const Key('record-title'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700, color: IpesColors.ink)),
                  const SizedBox(height: 4),
                  if (r.texts(Dc.creator).isNotEmpty)
                    Text(r.texts(Dc.creator).join(', '), style: const TextStyle(color: IpesColors.muted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (r.classNumber != null) CallNumber(r.classNumber!),
                    if (r.status == RecordStatus.draft)
                      const Chip(label: Text('Draft'), visualDensity: VisualDensity.compact),
                  ]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            key: const Key('cite-button'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: Iso690.reference(r)));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ISO 690 citation copied')));
            },
            icon: const Icon(Icons.format_quote),
            label: const Text('Cite'),
          ),
          OutlinedButton.icon(
            key: const Key('export-button'),
            onPressed: () => showExportSheet(context, c, [r]),
            icon: const Icon(Icons.ios_share),
            label: const Text('Export'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove from library?'),
                  content: const Text('The record is deleted. Your original file is not touched.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                  ],
                ),
              );
              if (ok == true) {
                await c.remove(r);
                if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ]),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Dublin Core', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(value: true, label: Text('MARC 21', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {marc},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => marc = s.first),
        ),
        const SizedBox(height: 12),
        if (!marc) _simple(r) else _marc(r),
        const SizedBox(height: 20),
        if (r.classSuggestions.isNotEmpty) ...[
          const Text('Dewey class · tap to choose', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in r.classSuggestions)
              ChoiceChip(
                label: Text('${s.number} ${s.label}'),
                selected: r.classNumber == s.number,
                onSelected: (on) => c.setClass(r, on ? s.number : null),
              ),
          ]),
          const SizedBox(height: 20),
        ],
        _itemDetails(r),
      ],
    );
  }

  Widget _simple(CatalogueRecord r) => Card(
        child: Column(children: [
          for (final e in Dc.all)
            for (final v in r.all(e))
              ListTile(
                dense: true,
                title: Text(e == Dc.language ? languageName(v.value) : v.value,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: IpesColors.ink)),
                leading: SizedBox(
                    width: 84,
                    child: Text(Dc.label(e), style: const TextStyle(fontSize: 12, color: IpesColors.muted))),
                trailing: SourceBadge(v),
                tileColor: v.confidence < CatalogueRecord.reviewThreshold ? IpesColors.warn : null,
              ),
        ]),
      );

  Widget _marc(CatalogueRecord r) => Container(
        key: const Key('marc-view'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: IpesColors.ink, borderRadius: BorderRadius.circular(14)),
        child: SelectableText(
          Marc21.fromRecord(r).toDisplay(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.6, color: Color(0xFFE8EDF5)),
        ),
      );

  Widget _itemDetails(CatalogueRecord r) {
    final kb = r.sizeBytes / 1024;
    final size = kb > 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your copy', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('${r.fileName} · $size${r.pageCount != null ? ' · ${r.pageCount} pages' : ''}',
          style: const TextStyle(color: IpesColors.muted)),
      if (r.sha256.isNotEmpty) Text('SHA-256 ${r.sha256.substring(0, 16)}…', style: monoStyle),
    ]);
  }
}

class RecordPage extends StatelessWidget {
  const RecordPage({super.key, required this.recordId, required this.controller});
  final String recordId;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final r = controller.library.byId(recordId);
          return Scaffold(
            appBar: AppBar(),
            body: r == null
                ? const Center(child: Text('This item was removed.'))
                : RecordView(record: r, controller: controller),
          );
        },
      );
}
