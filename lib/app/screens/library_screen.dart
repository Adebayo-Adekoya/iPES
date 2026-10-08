import 'package:flutter/material.dart';

import '../../core/record.dart';
import '../controller.dart';
import '../theme.dart';

class LibraryList extends StatelessWidget {
  const LibraryList({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onReview,
    this.selectedId,
  });

  final LibraryController controller;
  final void Function(CatalogueRecord) onOpen;
  final VoidCallback onReview;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final items = c.visibleRecords;
    final drafts = c.drafts.length;
    return CustomScrollView(
      key: const Key('library-list'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverList.list(children: [
            Text('My Library',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: IpesColors.ink)),
            const SizedBox(height: 2),
            Text('${c.records.length} items · nothing leaves this device',
                style: const TextStyle(color: IpesColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final m in c.modules)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m),
                      selected: c.moduleFilter == m,
                      onSelected: (_) => c.setModuleFilter(m),
                    ),
                  ),
              ]),
            ),
            if (drafts > 0) ...[
              const SizedBox(height: 12),
              Material(
                color: IpesColors.ink,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: const Key('review-banner'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: onReview,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: IpesColors.accent, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.auto_awesome, color: IpesColors.ink),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$drafts ${drafts == 1 ? 'record' : 'records'} ready to review',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const Text('Drafted on your device · nothing uploaded',
                              style: TextStyle(color: Color(0xFFC9D3E3), fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ]),
        ),
        if (items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No items yet. Tap + to add files.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = items[i];
                final selected = r.id == selectedId;
                final year = RegExp(r'^\d{4}').firstMatch(r.text(Dc.date))?.group(0);
                final by = [
                  if (r.texts(Dc.creator).isNotEmpty) r.texts(Dc.creator).first,
                  if (year != null) year,
                  if (r.texts(Dc.creator).isEmpty && year == null) r.mediaType.label,
                ].join(' · ');
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: selected ? IpesColors.ink : IpesColors.line, width: selected ? 2 : 1),
                  ),
                  child: ListTile(
                    key: Key('library-item-${r.id}'),
                    onTap: () => onOpen(r),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: MediaTile(r),
                    title: Text(r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: IpesColors.ink)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(by, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (r.classNumber != null) Text(r.classNumber!, style: monoStyle),
                    ]),
                    trailing: r.status == RecordStatus.draft
                        ? const Icon(Icons.auto_awesome, color: IpesColors.warnInk, size: 18)
                        : null,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
