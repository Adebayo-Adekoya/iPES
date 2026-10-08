import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/classifier.dart';
import 'package:ipes/core/extractors.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/builders.dart';
import 'package:ipes/core/sample/corpus.dart';

void main() {
  final items = {for (final s in SampleCorpus.curated()) s.key: s};
  final cataloguer = Cataloguer();
  CatalogueRecord draft(String key) =>
      cataloguer.draft(ImportedFile(items[key]!.fileName, items[key]!.bytes), id: key);

  group('Extractors', () {
    test('EPUB package metadata and spine text', () {
      final ex = EpubExtractor.extract(items['cookbook']!.bytes);
      expect(ex.title, 'Ghanaian Kitchen: Everyday Recipes');
      expect(ex.creators, ['Efua Mensah']);
      expect(ex.date, '2020');
      expect(ex.publisher, 'Tema Home Books');
      expect(ex.identifiers.single, 'urn:isbn:9789988025670');
      expect(ex.text, contains('kelewele'));
    });

    test('PDF Info dictionary, page count and Flate-compressed text', () {
      final ex = PdfExtractor.extract(items['lease']!.bytes);
      expect(ex.title, 'Tenancy Agreement - Flat 3B, East Legon');
      expect(ex.creators, ['Mensah Properties Ltd.']);
      expect(ex.date, '2025-03-01');
      expect(ex.pageCount, 2);
      expect(ex.text.replaceAll(RegExp(r'\s+'), ' '), contains('three months written notice'));
    });

    test('PDF with UTF-16 title and uncompressed text', () {
      final bytes = PdfBuilder.build(title: 'Réunion — Ɛkɔm', author: 'Àdá', pages: ['Plain text page'], compress: false);
      final ex = PdfExtractor.extract(bytes);
      expect(ex.title, 'Réunion — Ɛkɔm');
      expect(ex.creators.single, 'Àdá');
      expect(ex.text, contains('Plain text page'));
    });

    test('ID3v2.4 tags', () {
      final ex = Id3Extractor.extract(items['song']!.bytes);
      expect(ex.title, 'Sweet Mother Accra');
      expect(ex.creators, ['Kwesi Ampah Band']);
      expect(ex.date, '2019');
      expect(ex.subjects, contains('Highlife'));
    });

    test('EXIF capture date', () {
      expect(ImageExtractor.extract(items['xmas']!.bytes).date, '2019-12-25');
    });

    test('file name rules', () {
      final a = FileNameExtractor.parse('Chinua Achebe - Things Fall Apart (1958).pdf');
      expect(a.creator, 'Chinua Achebe');
      expect(a.title, 'Things Fall Apart');
      expect(a.date, '1958');
      final b = FileNameExtractor.parse('IMG_20191225_143000.jpg');
      expect(b.isCameraName, isTrue);
      expect(b.date, '2019-12-25');
      expect(b.title, isNull);
      expect(FileNameExtractor.parse('groundnut_soup.txt').title, 'Groundnut Soup');
    });
  });

  group('Cataloguer', () {
    test('drafts a complete record from an EPUB', () {
      final r = draft('dsbook');
      expect(r.mediaType, MediaType.book);
      expect(r.title, 'Data Structures in Practice');
      expect(r.texts(Dc.creator), ['Kwame Asante']);
      expect(r.text(Dc.identifier), 'ISBN 9789988012342');
      expect(r.text(Dc.language), 'eng');
      expect(r.text(Dc.type), 'Text');
      expect(r.first(Dc.title)!.source, FieldSource.embedded);
      expect(r.sha256, hasLength(64));
      expect(r.classNumber, '005');
      expect(r.module, 'Books');
    });

    test('ignores a junk embedded PDF title and uses the first line', () {
      final r = draft('deed');
      expect(r.title, 'Deed of Assignment - Plot 14, Kasoa');
      expect(r.first(Dc.title)!.source, FieldSource.content);
      expect(r.weakFields, contains(Dc.title));
    });

    test('finds an ISBN-10 in PDF text and treats the PDF as a book', () {
      final r = draft('algonotes');
      expect(r.text(Dc.identifier), 'ISBN 9780306406157');
      expect(r.mediaType, MediaType.book);
    });

    test('finds a DOI in text', () {
      expect(draft('paper').texts(Dc.identifier), contains('doi:10.5555/ipes.2024.017'));
    });

    test('camera photo: date from EXIF, placeholder title flagged for review', () {
      final r = draft('xmas');
      expect(r.mediaType, MediaType.image);
      expect(r.text(Dc.date), '2019-12-25');
      expect(r.weakFields, contains(Dc.title));
    });

    test('text notes: title from heading, creator from "By" line, language guessed', () {
      final r = draft('jollof');
      expect(r.title, 'Jollof Rice (Ghana style)');
      expect(r.texts(Dc.creator), ['Auntie Esi']);
      expect(r.text(Dc.language), 'eng');
      expect(r.text(Dc.description), isNotEmpty);
    });
  });

  group('Classifier', () {
    final classifier = Classifier();
    test('suggests private law for a lease', () {
      final r = classifier.classify(title: 'Tenancy agreement', text: 'The landlord and tenant agree the rent and notice.');
      expect(r.suggestions.first.number, '346');
      expect(r.suggestions.length, lessThanOrEqualTo(3));
    });
    test('suggests cooking for recipes', () {
      expect(classifier.classify(title: 'Jollof rice recipe').suggestions.first.number, '641');
    });
    test('English fiction goes to 823', () {
      final r = classifier.classify(title: 'A novel', text: 'This novel is a work of fiction.', language: 'eng');
      expect(r.suggestions.first.number, '823');
    });
    test('returns no suggestion when nothing matches', () {
      expect(classifier.classify(title: 'xyzzy').suggestions, isEmpty);
    });
  });

  group('Library', () {
    test('reports duplicates by content hash', () {
      final lib = Library();
      final f = ImportedFile(items['lease']!.fileName, items['lease']!.bytes);
      expect(lib.importFile(f).isDuplicate, isFalse);
      expect(lib.importFile(ImportedFile('copy.pdf', items['lease']!.bytes)).isDuplicate, isTrue);
      expect(lib.records, hasLength(1));
    });

    test('saves and loads every field', () async {
      final storage = MemoryStorage();
      final lib = Library(storage: storage);
      for (final s in items.values) {
        lib.importFile(ImportedFile(s.fileName, s.bytes));
      }
      lib.confirm(lib.records.first);
      await lib.save();
      final again = Library(storage: storage);
      await again.load();
      expect(again.records.length, lib.records.length);
      for (final r in lib.records) {
        final s = again.byId(r.id)!;
        expect(s.toJson(), r.toJson());
      }
    });

    test('collection statistics', () {
      final lib = Library();
      for (final s in items.values) {
        lib.importFile(ImportedFile(s.fileName, s.bytes));
      }
      final stats = lib.stats();
      expect(stats['items'], items.length);
      expect((stats['completeness'] as double), greaterThan(0.3));
    });
  });
}
