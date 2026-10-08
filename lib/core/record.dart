/// The iPES record model.
///
/// One record describes one item of any media type. Descriptive values are
/// keyed by the 15 Dublin Core elements (ISO 15836); every value carries its
/// provenance and a confidence so the review screen can highlight weak fields.
/// MARC 21 and Dublin Core exports are generated from this model.
library;

/// The 15 elements of the Dublin Core Metadata Element Set.
class Dc {
  Dc._();
  static const title = 'title';
  static const creator = 'creator';
  static const subject = 'subject';
  static const description = 'description';
  static const publisher = 'publisher';
  static const contributor = 'contributor';
  static const date = 'date';
  static const type = 'type';
  static const format = 'format';
  static const identifier = 'identifier';
  static const source = 'source';
  static const language = 'language';
  static const relation = 'relation';
  static const coverage = 'coverage';
  static const rights = 'rights';

  static const all = [
    title, creator, subject, description, publisher, contributor, date, type,
    format, identifier, source, language, relation, coverage, rights,
  ];

  /// The core elements counted for metadata completeness (spec section 12).
  static const core = [title, creator, subject, date, type, format, identifier, language];

  static String label(String element) =>
      element.isEmpty ? element : element[0].toUpperCase() + element.substring(1);
}

enum MediaType { book, document, image, video, audio, other }

extension MediaTypeInfo on MediaType {
  String get label => switch (this) {
        MediaType.book => 'Book',
        MediaType.document => 'Document',
        MediaType.image => 'Image',
        MediaType.video => 'Video',
        MediaType.audio => 'Audio',
        MediaType.other => 'Other',
      };

  /// DCMI Type Vocabulary term for dc:type.
  String get dcmiType => switch (this) {
        MediaType.book => 'Text',
        MediaType.document => 'Text',
        MediaType.image => 'StillImage',
        MediaType.video => 'MovingImage',
        MediaType.audio => 'Sound',
        MediaType.other => 'Dataset',
      };
}

/// Where a value came from. Shown as a badge next to each field.
enum FieldSource { embedded, content, filename, rules, ai, lookup, user }

extension FieldSourceInfo on FieldSource {
  String get label => switch (this) {
        FieldSource.embedded => 'Embedded',
        FieldSource.content => 'Content',
        FieldSource.filename => 'File name',
        FieldSource.rules => 'Rules',
        FieldSource.ai => 'AI',
        FieldSource.lookup => 'Lookup',
        FieldSource.user => 'You',
      };
}

class FieldValue {
  const FieldValue(this.value, {this.source = FieldSource.user, this.confidence = 1.0});

  final String value;
  final FieldSource source;

  /// 0.0–1.0. Values below [CatalogueRecord.reviewThreshold] are highlighted.
  final double confidence;

  Map<String, Object?> toJson() =>
      {'v': value, 's': source.name, 'c': double.parse(confidence.toStringAsFixed(3))};

  factory FieldValue.fromJson(Map<String, Object?> j) => FieldValue(
        j['v'] as String,
        source: FieldSource.values.firstWhere((s) => s.name == j['s'],
            orElse: () => FieldSource.user),
        confidence: (j['c'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  bool operator ==(Object other) =>
      other is FieldValue &&
      other.value == value &&
      other.source == source &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(value, source, confidence);

  @override
  String toString() => '$value (${source.name}, ${confidence.toStringAsFixed(2)})';
}

enum RecordStatus { draft, confirmed }

/// A suggested classification (Dewey Decimal) with its score.
class ClassSuggestion {
  const ClassSuggestion(this.number, this.label, this.confidence);
  final String number;
  final String label;
  final double confidence;

  Map<String, Object?> toJson() => {'n': number, 'l': label, 'c': confidence};
  factory ClassSuggestion.fromJson(Map<String, Object?> j) =>
      ClassSuggestion(j['n'] as String, j['l'] as String, (j['c'] as num).toDouble());
}

class CatalogueRecord {
  CatalogueRecord({
    required this.id,
    required this.mediaType,
    Map<String, List<FieldValue>>? values,
    this.classNumber,
    List<ClassSuggestion>? classSuggestions,
    this.status = RecordStatus.draft,
    required this.fileName,
    this.sizeBytes = 0,
    this.sha256 = '',
    this.pageCount,
    this.textContent = '',
    DateTime? addedAt,
    this.module,
  })  : values = values ?? {},
        classSuggestions = classSuggestions ?? [],
        addedAt = addedAt ?? DateTime.now();

  static const reviewThreshold = 0.7;

  final String id;
  MediaType mediaType;
  final Map<String, List<FieldValue>> values;

  /// Accepted Dewey number, e.g. "346.043" or "823".
  String? classNumber;
  final List<ClassSuggestion> classSuggestions;
  RecordStatus status;

  // Item-level (IFLA LRM "Item") data: the user's actual copy.
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final int? pageCount;
  final DateTime addedAt;

  /// Extracted full text (OCR/transcript in the full product). Used for search
  /// and passage answers; never exported.
  String textContent;

  /// The module (standard or custom) the item belongs to, e.g. "Books".
  String? module;

  List<FieldValue> all(String element) => values[element] ?? const [];
  FieldValue? first(String element) {
    final list = values[element];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  String text(String element) => first(element)?.value ?? '';
  List<String> texts(String element) => all(element).map((v) => v.value).toList();

  String get title => text(Dc.title).isEmpty ? fileName : text(Dc.title);

  void set(String element, List<FieldValue> list) {
    if (list.isEmpty) {
      values.remove(element);
    } else {
      values[element] = List.of(list);
    }
  }

  void setOne(String element, FieldValue? v) => set(element, v == null ? [] : [v]);

  /// Fields that need the user's attention before confirming.
  List<String> get weakFields => [
        for (final e in Dc.all)
          if (all(e).any((v) => v.confidence < reviewThreshold)) e,
      ];

  /// Share of core Dublin Core elements that have a value (0–1).
  double get completeness =>
      Dc.core.where((e) => all(e).isNotEmpty).length / Dc.core.length;

  /// Marks every value as confirmed by the user, keeping its original source.
  void confirm() {
    status = RecordStatus.confirmed;
  }

  Map<String, Object?> toJson({int maxText = 50000}) => {
        'id': id,
        'media': mediaType.name,
        'values': {
          for (final e in values.entries) e.key: [for (final v in e.value) v.toJson()],
        },
        'class': classNumber,
        'classSuggestions': [for (final c in classSuggestions) c.toJson()],
        'status': status.name,
        'file': fileName,
        'size': sizeBytes,
        'sha256': sha256,
        'pages': pageCount,
        'text': textContent.length > maxText ? textContent.substring(0, maxText) : textContent,
        'added': addedAt.toIso8601String(),
        'module': module,
      };

  factory CatalogueRecord.fromJson(Map<String, Object?> j) {
    final rawValues = (j['values'] as Map?) ?? const {};
    return CatalogueRecord(
      id: j['id'] as String,
      mediaType: MediaType.values.firstWhere((m) => m.name == j['media'],
          orElse: () => MediaType.other),
      values: {
        for (final e in rawValues.entries)
          e.key as String: [
            for (final v in (e.value as List)) FieldValue.fromJson((v as Map).cast<String, Object?>()),
          ],
      },
      classNumber: j['class'] as String?,
      classSuggestions: [
        for (final c in (j['classSuggestions'] as List? ?? const []))
          ClassSuggestion.fromJson((c as Map).cast<String, Object?>()),
      ],
      status: RecordStatus.values.firstWhere((s) => s.name == j['status'],
          orElse: () => RecordStatus.draft),
      fileName: j['file'] as String? ?? '',
      sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
      sha256: j['sha256'] as String? ?? '',
      pageCount: (j['pages'] as num?)?.toInt(),
      textContent: j['text'] as String? ?? '',
      addedAt: DateTime.tryParse(j['added'] as String? ?? ''),
      module: j['module'] as String?,
    );
  }
}
