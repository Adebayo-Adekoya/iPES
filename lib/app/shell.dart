/// Adaptive shell (spec section 4.1): Material 3 window size classes.
/// Compact (< 600 dp): bottom navigation, one pane.
/// Medium (600–839 dp): navigation rail, one pane.
/// Expanded (≥ 840 dp): navigation rail, list and record side by side.
library;

import 'package:flutter/material.dart';

import '../core/record.dart';
import 'controller.dart';
import 'screens/device_check.dart';
import 'screens/export_sheet.dart';
import 'screens/library_screen.dart';
import 'screens/record_view.dart';
import 'screens/review_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';

enum WindowSize { compact, medium, expanded }

WindowSize windowSizeOf(double width) => width < 600
    ? WindowSize.compact
    : width < 840
        ? WindowSize.medium
        : WindowSize.expanded;

class IpesApp extends StatelessWidget {
  const IpesApp({super.key, required this.controller});
  final LibraryController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'iPES',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AdaptiveShell(controller: controller),
      );
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key, required this.controller});
  final LibraryController controller;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int tab = 0;

  LibraryController get c => widget.controller;

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final report = await c.pickAndImport();
    if (!mounted) return;
    final parts = [
      if (report.added.isNotEmpty) '${report.added.length} drafted',
      if (report.duplicates.isNotEmpty) '${report.duplicates.length} already in your library',
    ];
    if (parts.isEmpty) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
      content: Text(parts.join(' · ')),
      action: report.added.isEmpty ? null : SnackBarAction(label: 'Review', onPressed: () => _go(2)),
    ));
  }

  /// Switches screens and clears messages from the previous one, so a
  /// snackbar never covers the new screen's actions.
  void _go(int i) {
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => tab = i);
  }

  void _openDeviceCheck() {
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DeviceCheckPage()));
  }

  void _open(CatalogueRecord r, WindowSize size) {
    if (size == WindowSize.expanded) {
      c.select(r.id);
      setState(() => tab = 0);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RecordPage(recordId: r.id, controller: c),
      ));
    }
  }

  Widget _body(WindowSize size) {
    switch (tab) {
      case 1:
        return SearchScreen(controller: c, onOpen: (r) => _open(r, size));
      case 2:
        return ReviewScreen(controller: c);
      default:
        final list = LibraryList(
          controller: c,
          selectedId: size == WindowSize.expanded ? c.selectedId : null,
          onOpen: (r) => _open(r, size),
          onReview: () => _go(2),
        );
        if (size != WindowSize.expanded) return list;
        final selected = c.selected ?? (c.visibleRecords.isNotEmpty ? c.visibleRecords.first : null);
        return Row(children: [
          SizedBox(width: 400, child: list),
          const VerticalDivider(width: 1, color: IpesColors.line),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: selected == null
                  ? const Center(child: Text('Select an item'))
                  : RecordView(key: ValueKey(selected.id), record: selected, controller: c),
            ),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final size = windowSizeOf(MediaQuery.sizeOf(context).width);
        if (c.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final drafts = c.drafts.length;
        final reviewIcon = Badge(
          isLabelVisible: drafts > 0,
          label: Text('$drafts'),
          child: const Icon(Icons.auto_awesome_outlined),
        );

        if (size == WindowSize.compact) {
          return Scaffold(
            key: const Key('layout-compact'),
            appBar: AppBar(
              title: Text(const ['iPES', 'Search', 'Review'][tab]),
              actions: [
                IconButton(
                  key: const Key('device-check'),
                  tooltip: 'Device check',
                  onPressed: _openDeviceCheck,
                  icon: const Icon(Icons.speed),
                ),
                if (tab == 0)
                  IconButton(
                    tooltip: 'Export library',
                    onPressed: () => showExportSheet(context, c, c.records),
                    icon: const Icon(Icons.ios_share),
                  ),
              ],
            ),
            body: SafeArea(child: _body(size)),
            floatingActionButton: tab == 0
                ? FloatingActionButton(
                    key: const Key('import-fab'),
                    tooltip: 'Add files',
                    onPressed: _import,
                    child: const Icon(Icons.add),
                  )
                : null,
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: _go,
              destinations: [
                const NavigationDestination(icon: Icon(Icons.local_library_outlined), label: 'Library'),
                const NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
                NavigationDestination(icon: reviewIcon, label: 'Review'),
              ],
            ),
          );
        }

        return Scaffold(
          key: Key(size == WindowSize.expanded ? 'layout-expanded' : 'layout-medium'),
          body: SafeArea(
            child: Row(children: [
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(children: [
                    FloatingActionButton(
                      key: const Key('import-fab'),
                      tooltip: 'Add files',
                      elevation: 0,
                      onPressed: _import,
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      key: const Key('device-check'),
                      tooltip: 'Device check',
                      color: Colors.white,
                      onPressed: _openDeviceCheck,
                      icon: const Icon(Icons.speed),
                    ),
                    IconButton(
                      tooltip: 'Export library',
                      color: Colors.white,
                      onPressed: () => showExportSheet(context, c, c.records),
                      icon: const Icon(Icons.ios_share),
                    ),
                  ]),
                ),
                destinations: [
                  const NavigationRailDestination(icon: Icon(Icons.local_library_outlined), label: Text('Library')),
                  const NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
                  NavigationRailDestination(icon: reviewIcon, label: const Text('Review')),
                ],
              ),
              Expanded(child: _body(size)),
            ]),
          ),
        );
      },
    );
  }
}
