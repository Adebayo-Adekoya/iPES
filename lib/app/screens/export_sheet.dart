import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/library.dart';
import '../../core/record.dart';
import '../controller.dart';
import '../theme.dart';

Future<void> showExportSheet(BuildContext context, LibraryController c, List<CatalogueRecord> records) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: ExportSheet(controller: c, records: records),
    ),
  );
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.controller, required this.records});
  final LibraryController controller;
  final List<CatalogueRecord> records;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportFormat format = ExportFormat.marcXml;

  String _preview() {
    final bytes = widget.controller.export(widget.records, format);
    if (format == ExportFormat.marc21) {
      // Show the binary record with its control characters made visible.
      final s = latin1.decode(bytes.length > 1600 ? bytes.sublist(0, 1600) : bytes, allowInvalid: true);
      return s.replaceAll('\u001e', '␞').replaceAll('\u001f', '‡').replaceAll('\u001d', '␝');
    }
    final s = utf8.decode(bytes, allowMalformed: true);
    return s.length > 4000 ? '${s.substring(0, 4000)}\n…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.records.length;
    final preview = _preview();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n == 1 ? 'Export record' : 'Export $n records',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ExportFormat.values)
            ChoiceChip(
              key: Key('format-${f.name}'),
              label: Text(f.label),
              selected: f == format,
              onSelected: (_) => setState(() => format = f),
            ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: IpesColors.ink, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
              child: SelectableText(preview,
                  key: const Key('export-preview'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFE8EDF5))),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: format == ExportFormat.marc21
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(
                          text: utf8.decode(widget.controller.export(widget.records, format))));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
              child: const Text('Copy'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('save-export'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final result = await widget.controller.saveExport(widget.records, format);
                if (result != null) messenger.showSnackBar(SnackBar(content: Text(result)));
              },
              child: const Text('Save file'),
            ),
          ),
        ]),
      ]),
    );
  }
}
