import 'package:flutter/material.dart';

import '../../core/semantic.dart';
import '../controller.dart';
import '../semantic_service.dart';
import '../theme.dart';

/// Choose the model that powers smart search: the built-in ranker or an
/// on-device model downloaded once from Hugging Face.
class SearchModelsPage extends StatelessWidget {
  const SearchModelsPage({super.key, required this.controller});
  final LibraryController controller;

  SemanticService get s => controller.semantic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search model')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Smart search combines keyword matching with a model that understands meaning. '
              'Models run on this device: your files and searches never leave it. '
              'A model is downloaded once; indexing your library runs in the background.',
              style: TextStyle(color: IpesColors.muted),
            ),
            if (!s.enabled) ...[
              const SizedBox(height: 12),
              const Text('On-device models run in the Android and iOS apps.',
                  style: TextStyle(color: IpesColors.warnInk)),
            ],
            const SizedBox(height: 16),
            _option(
              context,
              key: const Key('model-builtin'),
              title: 'Built-in',
              subtitle: 'Lightweight word-and-concept matcher. No download.',
              selected: s.activeId == null,
              trailing: s.activeId == null
                  ? const Chip(label: Text('In use'))
                  : OutlinedButton(onPressed: () => s.choose(null, controller.records), child: const Text('Use')),
            ),
            for (final m in ModelSpec.all) ...[
              const SizedBox(height: 12),
              _modelCard(context, m),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modelCard(BuildContext context, ModelSpec m) {
    final state = s.state[m.id]!;
    final inUse = s.activeId == m.id;
    final Widget action;
    switch (state) {
      case ModelState.notDownloaded:
      case ModelState.error:
        action = FilledButton(
          key: Key('download-${m.id}'),
          onPressed: s.enabled ? () => s.download(m) : null,
          child: Text('Download ${m.downloadMb.round()} MB'),
        );
      case ModelState.downloading:
        action = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5));
      case ModelState.downloaded:
        action = inUse
            ? const Chip(label: Text('In use'))
            : FilledButton(
                key: Key('use-${m.id}'),
                onPressed: () => s.choose(m.id, controller.records),
                child: const Text('Use'),
              );
    }
    return _option(
      context,
      key: Key('model-${m.id}'),
      title: m.name,
      subtitle: '${m.note}\nLicence: ${m.licence} (${m.licenceUrl})',
      selected: inUse,
      trailing: action,
      footer: [
        if (state == ModelState.downloading) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: s.progress[m.id]),
          const SizedBox(height: 4),
          Text('${((s.progress[m.id] ?? 0) * m.downloadMb).round()} of ${m.downloadMb.round()} MB',
              style: const TextStyle(fontSize: 12, color: IpesColors.muted)),
        ],
        if (inUse) ...[
          const SizedBox(height: 10),
          Text(s.statusLine, style: const TextStyle(fontSize: 13)),
          if (s.indexing && s.toIndex > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: s.indexed / s.toIndex),
          ],
        ],
        if (s.errors[m.id] != null) ...[
          const SizedBox(height: 8),
          Text(s.errors[m.id]!, style: const TextStyle(fontSize: 12, color: IpesColors.warnInk)),
        ],
        if (state == ModelState.downloaded)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => s.delete(m), child: const Text('Delete download')),
          ),
      ],
    );
  }

  Widget _option(BuildContext context,
      {required Key key,
      required String title,
      required String subtitle,
      required bool selected,
      required Widget trailing,
      List<Widget> footer = const []}) {
    return Card(
      key: key,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? IpesColors.ink : IpesColors.line, width: selected ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              trailing,
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(subtitle, style: const TextStyle(fontSize: 13, color: IpesColors.muted)),
          ...footer,
        ]),
      ),
    );
  }
}
