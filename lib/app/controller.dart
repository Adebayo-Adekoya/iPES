/// App state: wraps the pure-Dart [Library] for the widget tree.
library;

import 'package:flutter/foundation.dart';

import '../core/cataloguer.dart';
import '../core/library.dart';
import '../core/record.dart';
import '../core/sample/corpus.dart';
import '../core/search.dart';
import 'services.dart';
import 'startup.dart';

class ImportReport {
  ImportReport(this.added, this.duplicates);
  final List<CatalogueRecord> added;
  final List<String> duplicates;
}

class LibraryController extends ChangeNotifier {
  LibraryController({required this.library, required this.files});

  final Library library;
  final FileService files;

  bool loading = true;
  String? selectedId;
  String moduleFilter = 'All';

  List<CatalogueRecord> get records => library.records;
  List<CatalogueRecord> get drafts => library.drafts;

  List<CatalogueRecord> get visibleRecords => moduleFilter == 'All'
      ? records
      : records.where((r) => r.module == moduleFilter).toList();

  List<String> get modules => [
        'All',
        ...({for (final r in records) r.module ?? 'Documents'}.toList()..sort()),
      ];

  CatalogueRecord? get selected => selectedId == null ? null : library.byId(selectedId!);

  /// Loads the saved library; seeds the sample library on first run so
  /// there is something to explore.
  Future<void> start({bool seedSamples = true}) async {
    await library.load();
    if (library.records.isEmpty && seedSamples) {
      Startup.firstLaunch = true;
      final base = DateTime.now().subtract(const Duration(days: 40));
      final samples = SampleCorpus.curated();
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final outcome = library.importFile(ImportedFile(s.fileName, s.bytes),
            now: base.add(Duration(days: i)));
        // Leave three drafts so the review flow can be tried straight away.
        if (i < samples.length - 3) library.confirm(outcome.record);
      }
      await library.save();
    }
    loading = false;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void setModuleFilter(String m) {
    moduleFilter = m;
    notifyListeners();
  }

  Future<ImportReport> importFiles(List<ImportedFile> picked) async {
    final added = <CatalogueRecord>[];
    final dupes = <String>[];
    for (final f in picked) {
      final outcome = library.importFile(f);
      if (outcome.isDuplicate) {
        dupes.add(f.name);
      } else {
        added.add(outcome.record);
      }
    }
    await library.save();
    notifyListeners();
    return ImportReport(added, dupes);
  }

  Future<ImportReport> pickAndImport() async => importFiles(await files.pickFiles());

  Future<void> confirm(CatalogueRecord r) async {
    library.confirm(r);
    await library.save();
    notifyListeners();
  }

  Future<void> setField(CatalogueRecord r, String element, String value) async {
    final parts = element == Dc.subject || element == Dc.creator
        ? value.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : [value.trim()].where((s) => s.isNotEmpty).toList();
    r.set(element, [for (final p in parts) FieldValue(p)]);
    library.updated(r);
    await library.save();
    notifyListeners();
  }

  Future<void> setClass(CatalogueRecord r, String? number) async {
    r.classNumber = number;
    library.updated(r);
    await library.save();
    notifyListeners();
  }

  Future<void> remove(CatalogueRecord r) async {
    library.remove(r.id);
    if (selectedId == r.id) selectedId = null;
    await library.save();
    notifyListeners();
  }

  SearchResult search(String q, {SearchMode mode = SearchMode.hybrid}) => library.search(q, mode: mode);

  Uint8List export(List<CatalogueRecord> records, ExportFormat format) => library.export(records, format);

  Future<String?> saveExport(List<CatalogueRecord> records, ExportFormat format) {
    final name = records.length == 1
        ? '${records.first.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.${format.extension}'
        : 'ipes_library.${format.extension}';
    return files.saveFile(name, export(records, format), format.mimeType);
  }
}
