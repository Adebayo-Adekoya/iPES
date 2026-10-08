/// Dublin Core export: OAI-DC XML (ISO 15836 elements) and JSON-LD (DCMI terms).
library;

import 'dart:convert';

import '../record.dart';

class DublinCore {
  DublinCore._();

  static const oaiDcNs = 'http://www.openarchives.org/OAI/2.0/oai_dc/';
  static const dcNs = 'http://purl.org/dc/elements/1.1/';

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static void _writeRecord(StringBuffer b, CatalogueRecord r, {String indent = ''}) {
    b.writeln('$indent<oai_dc:dc xmlns:oai_dc="$oaiDcNs" xmlns:dc="$dcNs" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="$oaiDcNs http://www.openarchives.org/OAI/2.0/oai_dc.xsd">');
    for (final e in Dc.all) {
      for (final v in r.all(e)) {
        b.writeln('$indent  <dc:$e>${_esc(v.value)}</dc:$e>');
      }
      if (e == Dc.subject && r.classNumber != null) {
        b.writeln('$indent  <dc:subject>DDC ${_esc(r.classNumber!)}</dc:subject>');
      }
    }
    b.writeln('$indent</oai_dc:dc>');
  }

  /// One record as a standalone OAI-DC document.
  static String toXml(CatalogueRecord r) {
    final b = StringBuffer()..writeln('<?xml version="1.0" encoding="UTF-8"?>');
    _writeRecord(b, r);
    return b.toString();
  }

  /// Several records wrapped in a simple container element.
  static String collectionToXml(Iterable<CatalogueRecord> records) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<records xmlns:oai_dc="$oaiDcNs" xmlns:dc="$dcNs">');
    for (final r in records) {
      _writeRecord(b, r, indent: '  ');
    }
    b.writeln('</records>');
    return b.toString();
  }

  static Map<String, Object?> toJsonLd(CatalogueRecord r) {
    final out = <String, Object?>{
      '@context': {'dcterms': 'http://purl.org/dc/terms/'},
      '@id': 'urn:ipes:${r.id}',
    };
    for (final e in Dc.all) {
      final vals = r.texts(e);
      if (vals.isEmpty) continue;
      out['dcterms:$e'] = vals.length == 1 ? vals.first : vals;
    }
    return out;
  }

  static String collectionToJsonLd(Iterable<CatalogueRecord> records) =>
      const JsonEncoder.withIndent('  ').convert({'@graph': [for (final r in records) toJsonLd(r)]});
}
