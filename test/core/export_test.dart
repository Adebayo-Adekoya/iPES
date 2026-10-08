import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/cataloguer.dart';
import 'package:ipes/core/export/citation.dart';
import 'package:ipes/core/export/dublin_core.dart';
import 'package:ipes/core/export/marc21.dart';
import 'package:ipes/core/library.dart';
import 'package:ipes/core/record.dart';
import 'package:ipes/core/sample/corpus.dart';
import 'package:xml/xml.dart';

void main() {
  final cataloguer = Cataloguer();
  final records = [
    for (final s in SampleCorpus.curated())
      cataloguer.draft(ImportedFile(s.fileName, s.bytes), id: s.key, now: DateTime(2026, 10, 8)),
  ];
  CatalogueRecord byKey(String k) => records.firstWhere((r) => r.id == k);
  final now = DateTime(2026, 10, 8, 12, 0, 0);

  group('MARC 21 / ISO 2709', () {
    test('every record round-trips through ISO 2709 without loss', () {
      for (final r in records) {
        final marc = Marc21.fromRecord(r, now: now);
        final bytes = Marc21.toIso2709(marc);
        final back = Marc21.parseIso2709(bytes);
        expect(back.fields.length, marc.fields.length, reason: r.id);
        for (var i = 0; i < marc.fields.length; i++) {
          final a = marc.fields[i];
          final b = back.fields[i];
          expect(b.tag, a.tag);
          expect(b.data, a.data);
          expect(b.ind1, a.ind1);
          expect(b.ind2, a.ind2);
          expect(b.subfields, a.subfields, reason: '${r.id} ${a.tag}');
        }
      }
    });

    test('leader carries real record length and base address', () {
      final bytes = Marc21.toIso2709(Marc21.fromRecord(byKey('contes'), now: now));
      final leader = ascii.decode(bytes.sublist(0, 24));
      expect(int.parse(leader.substring(0, 5)), bytes.length);
      expect(leader.substring(5, 10), 'nam a');
      expect(leader.substring(20), '4500');
      expect(bytes[int.parse(leader.substring(12, 17)) - 1], Marc21.fieldTerminator);
      expect(bytes.last, Marc21.recordTerminator);
    });

    test('a collection of records parses back', () {
      final all = records.map((r) => Marc21.fromRecord(r, now: now)).toList();
      final parsed = Marc21.parseIso2709Collection(Marc21.collectionToIso2709(all));
      expect(parsed.length, all.length);
    });

    test('field mapping', () {
      final m = Marc21.fromRecord(byKey('dsbook'), now: now);
      expect(m.first('020')!.sub('a'), '9789988012342');
      expect(m.first('100')!.sub('a'), 'Asante, Kwame');
      expect(m.first('245')!.sub('a'), 'Data Structures in Practice');
      expect(m.first('082')!.sub('a'), '005');
      expect(m.first('264')!.sub('b'), 'Accra Tech Press');
      expect(m.first('008')!.data, hasLength(40));
      expect(m.leader[6], 'a');

      final souls = Marc21.fromRecord(byKey('souls'), now: now);
      expect(souls.first('245')!.ind2, '4', reason: 'skip "The " when filing');
      final lease = Marc21.fromRecord(byKey('lease'), now: now);
      expect(lease.first('110')!.sub('a'), 'Mensah Properties Ltd.');
      expect(Marc21.fromRecord(byKey('wedding'), now: now).leader[6], 'g');
      expect(Marc21.fromRecord(byKey('song'), now: now).leader[6], 'j');
      expect(Marc21.fromRecord(byKey('paper'), now: now).first('024')!.sub('2'), 'doi');
    });

    test('MARCXML is well formed and matches the slim schema structure', () {
      final xml = Marc21.toMarcXml(records.map((r) => Marc21.fromRecord(r, now: now)));
      final doc = XmlDocument.parse(xml);
      final root = doc.rootElement;
      expect(root.name.local, 'collection');
      expect(root.namespaceUri, 'http://www.loc.gov/MARC21/slim');
      final recs = root.findElements('record').toList();
      expect(recs.length, records.length);
      for (final rec in recs) {
        expect(rec.findElements('leader').single.innerText, hasLength(24));
        for (final df in rec.findElements('datafield')) {
          expect(df.getAttribute('tag'), matches(RegExp(r'^\d{3}$')));
          expect(df.getAttribute('ind1'), hasLength(1));
          expect(df.findElements('subfield'), isNotEmpty);
        }
      }
    });
  });

  group('Dublin Core', () {
    test('OAI-DC XML is well formed with dc: elements only', () {
      for (final r in records) {
        final doc = XmlDocument.parse(DublinCore.toXml(r));
        final dc = doc.rootElement;
        expect(dc.name.local, 'dc');
        expect(dc.namespaceUri, DublinCore.oaiDcNs);
        for (final e in dc.childElements) {
          expect(e.namespaceUri, DublinCore.dcNs);
          expect(Dc.all, contains(e.name.local));
        }
        expect(dc.findElements('title', namespaceUri: DublinCore.dcNs), isNotEmpty);
      }
    });

    test('JSON-LD decodes', () {
      final decoded = jsonDecode(DublinCore.collectionToJsonLd(records)) as Map<String, dynamic>;
      expect((decoded['@graph'] as List).length, records.length);
    });
  });

  group('ISO 690', () {
    test('book with publisher and year', () {
      expect(Iso690.reference(byKey('pride')), 'AUSTEN, Jane. Pride and Prejudice [e-book]. Project Gutenberg, 1813.');
    });
    test('two creators and ISBN', () {
      final s = Iso690.reference(byKey('folktales'));
      expect(s, startsWith('BARKER, William H. and SINCLAIR, Cecilia. West African Folk-Tales [e-book].'));
    });
    test('organisation as creator and DOI', () {
      expect(Iso690.reference(byKey('lease')), startsWith('Mensah Properties Ltd. Tenancy Agreement'));
      expect(Iso690.reference(byKey('paper')), endsWith('DOI 10.5555/ipes.2024.017.'));
    });
  });

  test('Library.export produces every format', () {
    final lib = Library()..addAll(records);
    for (final f in ExportFormat.values) {
      expect(lib.export(lib.records, f, now: now), isNotEmpty, reason: f.name);
    }
  });
}
