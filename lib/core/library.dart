/// The library: holds records, runs import → catalogue → search → export,
/// and persists through a [LibraryStorage]. Pure Dart, no Flutter imports,
/// so the whole flow is testable headlessly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'cataloguer.dart';
import 'export/citation.dart';
import 'export/dublin_core.dart';
import 'export/marc21.dart';
import 'record.dart';
import 'search.dart';

abstract class LibraryStorage {
  Future<String?> load();
  Future<void> save(String json);
}

class MemoryStorage implements LibraryStorage {
  String? data;
  @override
  Future<String?> load() async => data;
  @override
  Future<void> save(String json) async => data = json;
}

class ImportOutcome {
  ImportOutcome(this.record, {this.duplicateOf});
  final CatalogueRecord record;

  /// Set when the same file (same SHA-256) is already in the library.
  final CatalogueRecord? duplicateOf;
  bool get isDuplicate => duplicateOf != null;
}

enum ExportFormat { marc21, marcXml, dublinCoreXml, dublinCoreJsonLd, iso690 }

extension ExportFormatInfo on ExportFormat {
  String get label => switch (this) {
        ExportFormat.marc21 => 'MARC 21 (ISO 2709, .mrc)',
        ExportFormat.marcXml => 'MARCXML (.xml)',
        ExportFormat.dublinCoreXml => 'Dublin Core XML (.xml)',
        ExportFormat.dublinCoreJsonLd => 'Dublin Core JSON-LD (.jsonld)',
        ExportFormat.iso690 => 'ISO 690 citations (.txt)',
      };
  String get extension => switch (this) {
        ExportFormat.marc21 => 'mrc',
        ExportFormat.marcXml => 'marc.xml',
        ExportFormat.dublinCoreXml => 'dc.xml',
        ExportFormat.dublinCoreJsonLd => 'jsonld',
        ExportFormat.iso690 => 'txt',
      };
  String get mimeType => switch (this) {
        ExportFormat.marc21 => 'application/marc',
        ExportFormat.marcXml => 'application/marcxml+xml',
        ExportFormat.dublinCoreXml => 'application/xml',
        ExportFormat.dublinCoreJsonLd => 'application/ld+json',
        ExportFormat.iso690 => 'text/plain',
      };
}

class Library {
  Library({LibraryStorage? storage, Cataloguer? cataloguer, SearchEngine? engine})
      : storage = storage ?? MemoryStorage(),
        cataloguer = cataloguer ?? Cataloguer(),
        engine = engine ?? SearchEngine();

  final LibraryStorage storage;
  final Cataloguer cataloguer;
  final SearchEngine engine;

  final List<CatalogueRecord> _records = [];
  bool _indexDirty = true;
  int _counter = 0;

  /// Newest first.
  List<CatalogueRecord> get records =>
      List.unmodifiable(List.of(_records)..sort((a, b) => b.addedAt.compareTo(a.addedAt)));

  List<CatalogueRecord> get drafts => records.where((r) => r.status == RecordStatus.draft).toList();

  CatalogueRecord? byId(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  String _nextId() =>
      'ipes${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';

  Future<void> load() async {
    final json = await storage.load();
    if (json == null || json.isEmpty) return;
    final data = jsonDecode(json) as Map<String, Object?>;
    _records
      ..clear()
      ..addAll([
        for (final r in (data['records'] as List? ?? const []))
          CatalogueRecord.fromJson((r as Map).cast<String, Object?>()),
      ]);
    _indexDirty = true;
  }

  Future<void> save() => storage.save(jsonEncode({
        'version': 1,
        'records': [for (final r in _records) r.toJson()],
      }));

  /// Imports a file and drafts its record. Duplicates (same content hash)
  /// are reported, not added twice.
  ImportOutcome importFile(ImportedFile file, {DateTime? now}) {
    final draft = cataloguer.draft(file, id: _nextId(), now: now);
    for (final r in _records) {
      if (r.sha256 == draft.sha256) return ImportOutcome(r, duplicateOf: r);
    }
    _records.add(draft);
    if (!_indexDirty) engine.add(draft);
    return ImportOutcome(draft);
  }

  /// Adds records that were built elsewhere (sample data, restore).
  void addAll(Iterable<CatalogueRecord> records) {
    final list = records.toList();
    _records.addAll(list);
    if (!_indexDirty) {
      for (final r in list) {
        engine.add(r);
      }
    }
  }

  void confirm(CatalogueRecord r) {
    r.confirm(); // status is not searchable, so the index is unchanged
  }

  /// Call after editing a record's fields so search sees the change.
  void updated(CatalogueRecord r) {
    if (!_indexDirty) engine.update(r);
  }

  void remove(String id) {
    _records.removeWhere((r) => r.id == id);
    if (!_indexDirty) engine.remove(id);
  }

  /// Builds the whole index once (after loading); later changes are applied
  /// one record at a time.
  void _ensureIndex() {
    if (!_indexDirty) return;
    engine.indexAll(_records);
    _indexDirty = false;
  }

  SearchResult search(String query, {int limit = 20, SearchMode mode = SearchMode.hybrid}) {
    _ensureIndex();
    return engine.search(query, limit: limit, mode: mode);
  }

  /// Serialises [records] in [format]. Text formats are UTF-8 encoded.
  Uint8List export(Iterable<CatalogueRecord> records, ExportFormat format, {DateTime? now}) {
    final list = records.toList();
    switch (format) {
      case ExportFormat.marc21:
        return Marc21.collectionToIso2709(list.map((r) => Marc21.fromRecord(r, now: now)));
      case ExportFormat.marcXml:
        return utf8.encode(Marc21.toMarcXml(list.map((r) => Marc21.fromRecord(r, now: now))));
      case ExportFormat.dublinCoreXml:
        return utf8.encode(DublinCore.collectionToXml(list));
      case ExportFormat.dublinCoreJsonLd:
        return utf8.encode(DublinCore.collectionToJsonLd(list));
      case ExportFormat.iso690:
        return utf8.encode(list.map(Iso690.reference).join('\n'));
    }
  }

  /// Collection statistics (ISO 2789-inspired), for the Reports module.
  Map<String, Object> stats() {
    final byType = <String, int>{};
    for (final r in _records) {
      byType[r.mediaType.label] = (byType[r.mediaType.label] ?? 0) + 1;
    }
    final completeness = _records.isEmpty
        ? 0.0
        : _records.map((r) => r.completeness).reduce((a, b) => a + b) / _records.length;
    return {
      'items': _records.length,
      'drafts': drafts.length,
      'byType': byType,
      'completeness': completeness,
      'bytes': _records.fold<int>(0, (a, r) => a + r.sizeBytes),
    };
  }
}
