/// MARC 21 bibliographic records: mapping from [CatalogueRecord], an
/// ISO 2709 writer and reader (".mrc"), and MARCXML (MARC 21 slim schema).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../record.dart';
import '../text.dart';

class Subfield {
  const Subfield(this.code, this.value);
  final String code;
  final String value;

  @override
  bool operator ==(Object other) => other is Subfield && other.code == code && other.value == value;
  @override
  int get hashCode => Object.hash(code, value);
  @override
  String toString() => '\$$code $value';
}

class MarcField {
  MarcField.controlfield(this.tag, String this.data)
      : ind1 = ' ',
        ind2 = ' ',
        subfields = const [];
  MarcField.datafield(this.tag, this.ind1, this.ind2, this.subfields) : data = null;

  final String tag;
  final String ind1;
  final String ind2;
  final String? data;
  final List<Subfield> subfields;

  bool get isControl => data != null;

  String? sub(String code) {
    for (final s in subfields) {
      if (s.code == code) return s.value;
    }
    return null;
  }

  @override
  String toString() => isControl
      ? '$tag    $data'
      : '$tag ${ind1.replaceAll(' ', '_')}${ind2.replaceAll(' ', '_')} ${subfields.join(' ')}';
}

class MarcRecord {
  MarcRecord(this.leader, this.fields);
  final String leader;
  final List<MarcField> fields;

  Iterable<MarcField> all(String tag) => fields.where((f) => f.tag == tag);
  MarcField? first(String tag) {
    for (final f in fields) {
      if (f.tag == tag) return f;
    }
    return null;
  }

  /// Human-readable "mnemonic" form, as shown in the Expert view.
  String toDisplay() => ['LDR  $leader', ...fields.map((f) => f.toString())].join('\n');
}

class Marc21 {
  Marc21._();

  static const fieldTerminator = 0x1E;
  static const subfieldDelimiter = 0x1F;
  static const recordTerminator = 0x1D;

  static final _orgPattern = RegExp(
    r'\b(Ltd|Limited|Inc|Company|Co\.|Commission|Authority|University|Ministry|Association|Bank|Press|Publishers?|Corporation|Council|Service|Church|School|Hospital|Institute|Agency|Foundation|Family)\b',
    caseSensitive: false,
  );

  static bool isOrganisation(String name) => _orgPattern.hasMatch(name);

  /// "Chinua Achebe" -> "Achebe, Chinua". Already inverted names are kept.
  static String invertName(String name) {
    final n = name.trim();
    if (n.contains(',') || isOrganisation(n)) return n;
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.length > 4) return n;
    return '${parts.last}, ${parts.sublist(0, parts.length - 1).join(' ')}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static int _nonFiling(String title, String? lang) {
    if (lang != null && lang != 'eng') return 0;
    final m = RegExp(r'^(The |A |An )').firstMatch(title);
    return m == null ? 0 : m.group(0)!.length;
  }

  /// Maps a catalogue record to MARC 21. See spec section 5 for the mapping.
  static MarcRecord fromRecord(CatalogueRecord r, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final fields = <MarcField>[];
    final lang = r.text(Dc.language);
    final date = r.text(Dc.date);
    final year = RegExp(r'^\d{4}').firstMatch(date)?.group(0);

    fields.add(MarcField.controlfield('001', r.id));
    fields.add(MarcField.controlfield(
        '005', '${t.year}${_two(t.month)}${_two(t.day)}${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.0'));
    final a = r.addedAt;
    final f008 = StringBuffer()
      ..write('${_two(a.year % 100)}${_two(a.month)}${_two(a.day)}')
      ..write(year != null ? 's$year    ' : 'nuuuuuuuu')
      ..write('xx ')
      ..write('|' * 17)
      ..write(lang.length == 3 ? lang : 'und')
      ..write(' d');
    fields.add(MarcField.controlfield('008', f008.toString()));

    for (final id in r.texts(Dc.identifier)) {
      if (id.startsWith('ISBN ')) {
        fields.add(MarcField.datafield('020', ' ', ' ', [Subfield('a', id.substring(5))]));
      } else if (id.toLowerCase().startsWith('doi:')) {
        fields.add(MarcField.datafield('024', '7', ' ', [Subfield('a', id.substring(4)), const Subfield('2', 'doi')]));
      } else {
        fields.add(MarcField.datafield('024', '8', ' ', [Subfield('a', id)]));
      }
    }
    if (lang.length == 3) fields.add(MarcField.datafield('041', '0', ' ', [Subfield('a', lang)]));
    if (r.classNumber != null) {
      fields.add(MarcField.datafield('082', '0', '4', [Subfield('a', r.classNumber!), const Subfield('2', '23')]));
    }

    final creators = r.texts(Dc.creator);
    if (creators.isNotEmpty) {
      final c = creators.first;
      fields.add(isOrganisation(c)
          ? MarcField.datafield('110', '2', ' ', [Subfield('a', c)])
          : MarcField.datafield('100', '1', ' ', [Subfield('a', invertName(c))]));
    }

    final title = r.title;
    fields.add(MarcField.datafield('245', creators.isNotEmpty ? '1' : '0', '${_nonFiling(title, lang)}', [
      Subfield('a', title),
      if (creators.isNotEmpty) Subfield('c', creators.join(', ')),
    ]));

    final publisher = r.text(Dc.publisher);
    if (publisher.isNotEmpty || date.isNotEmpty) {
      fields.add(MarcField.datafield('264', ' ', '1', [
        if (publisher.isNotEmpty) Subfield('b', publisher),
        if (date.isNotEmpty) Subfield('c', date),
      ]));
    }

    fields.add(MarcField.datafield('300', ' ', ' ', [
      Subfield('a', r.pageCount != null ? '1 online resource (${r.pageCount} pages)' : '1 online resource'),
    ]));
    final (contentTerm, contentCode) = switch (r.mediaType) {
      MediaType.book || MediaType.document => ('text', 'txt'),
      MediaType.image => ('still image', 'sti'),
      MediaType.video => ('two-dimensional moving image', 'tdi'),
      MediaType.audio => ('spoken word', 'spw'),
      MediaType.other => ('computer dataset', 'cod'),
    };
    fields.add(MarcField.datafield('336', ' ', ' ',
        [Subfield('a', contentTerm), Subfield('b', contentCode), const Subfield('2', 'rdacontent')]));
    fields.add(MarcField.datafield('337', ' ', ' ',
        [const Subfield('a', 'computer'), const Subfield('b', 'c'), const Subfield('2', 'rdamedia')]));
    fields.add(MarcField.datafield('338', ' ', ' ',
        [const Subfield('a', 'online resource'), const Subfield('b', 'cr'), const Subfield('2', 'rdacarrier')]));

    final description = r.text(Dc.description);
    if (description.isNotEmpty) fields.add(MarcField.datafield('520', ' ', ' ', [Subfield('a', description)]));
    if (r.sha256.isNotEmpty) {
      fields.add(MarcField.datafield('590', ' ', ' ', [Subfield('a', 'SHA-256 checksum: ${r.sha256}')]));
    }
    for (final s in r.texts(Dc.subject)) {
      fields.add(MarcField.datafield('650', ' ', '4', [Subfield('a', s)]));
    }
    for (final c in [...creators.skip(1), ...r.texts(Dc.contributor)]) {
      fields.add(isOrganisation(c)
          ? MarcField.datafield('710', '2', ' ', [Subfield('a', c)])
          : MarcField.datafield('700', '1', ' ', [Subfield('a', invertName(c))]));
    }
    final format = r.text(Dc.format).split(';').first.trim();
    fields.add(MarcField.datafield('856', '4', ' ', [
      Subfield('f', r.fileName),
      if (format.isNotEmpty) Subfield('q', format),
    ]));

    final typeOfRecord = switch (r.mediaType) {
      MediaType.book || MediaType.document => 'a',
      MediaType.image => 'k',
      MediaType.video => 'g',
      // Musical sound recording when classed in music (78x) or tagged as music.
      MediaType.audio => (r.classNumber?.startsWith('78') ?? false) ||
              r.texts(Dc.subject).any((s) => TextTools.terms(s).any((t) => t == 'music' || t == 'song'))
          ? 'j'
          : 'i',
      MediaType.other => 'm',
    };
    // Lengths and base address are filled in by the ISO 2709 writer.
    return MarcRecord('00000n${typeOfRecord}m a2200000uc 4500', fields);
  }

  // -------------------------------------------------------------------------
  // ISO 2709.

  static Uint8List toIso2709(MarcRecord record) {
    final directory = BytesBuilder();
    final data = BytesBuilder();
    for (final f in record.fields) {
      final body = BytesBuilder();
      if (f.isControl) {
        body.add(utf8.encode(f.data!));
      } else {
        body.add(utf8.encode(f.ind1 + f.ind2));
        for (final s in f.subfields) {
          body.addByte(subfieldDelimiter);
          body.add(utf8.encode(s.code + s.value));
        }
      }
      body.addByte(fieldTerminator);
      final bytes = body.toBytes();
      if (bytes.length > 9999) throw ArgumentError('Field ${f.tag} exceeds 9999 bytes');
      directory.add(ascii.encode(f.tag + bytes.length.toString().padLeft(4, '0') +
          data.length.toString().padLeft(5, '0')));
      data.add(bytes);
    }
    directory.addByte(fieldTerminator);
    final baseAddress = 24 + directory.length;
    final total = baseAddress + data.length + 1;
    if (total > 99999) throw ArgumentError('Record exceeds 99999 bytes');
    final leader = total.toString().padLeft(5, '0') +
        record.leader.substring(5, 12) +
        baseAddress.toString().padLeft(5, '0') +
        record.leader.substring(17, 24);
    return (BytesBuilder()
          ..add(ascii.encode(leader))
          ..add(directory.toBytes())
          ..add(data.toBytes())
          ..addByte(recordTerminator))
        .toBytes();
  }

  /// Concatenates records into one .mrc file.
  static Uint8List collectionToIso2709(Iterable<MarcRecord> records) {
    final b = BytesBuilder();
    for (final r in records) {
      b.add(toIso2709(r));
    }
    return b.toBytes();
  }

  static List<MarcRecord> parseIso2709Collection(Uint8List bytes) {
    final out = <MarcRecord>[];
    var start = 0;
    while (start < bytes.length) {
      final len = int.parse(ascii.decode(bytes.sublist(start, start + 5)));
      out.add(parseIso2709(Uint8List.sublistView(bytes, start, start + len)));
      start += len;
    }
    return out;
  }

  static MarcRecord parseIso2709(Uint8List bytes) {
    if (bytes.length < 25) throw const FormatException('Too short for ISO 2709');
    final leader = ascii.decode(bytes.sublist(0, 24));
    final length = int.parse(leader.substring(0, 5));
    final base = int.parse(leader.substring(12, 17));
    if (length != bytes.length) throw FormatException('Leader length $length != ${bytes.length}');
    if (bytes.last != recordTerminator) throw const FormatException('Missing record terminator');
    if (bytes[base - 1] != fieldTerminator) throw const FormatException('Missing directory terminator');
    final fields = <MarcField>[];
    for (var p = 24; p < base - 1; p += 12) {
      final entry = ascii.decode(bytes.sublist(p, p + 12));
      final tag = entry.substring(0, 3);
      final flen = int.parse(entry.substring(3, 7));
      final fstart = int.parse(entry.substring(7, 12));
      final raw = bytes.sublist(base + fstart, base + fstart + flen);
      if (raw.last != fieldTerminator) throw FormatException('Field $tag not terminated');
      final body = raw.sublist(0, raw.length - 1);
      if (int.parse(tag) < 10) {
        fields.add(MarcField.controlfield(tag, utf8.decode(body)));
      } else {
        final ind1 = String.fromCharCode(body[0]);
        final ind2 = String.fromCharCode(body[1]);
        final subs = <Subfield>[];
        var i = 2;
        while (i < body.length) {
          if (body[i] != subfieldDelimiter) throw FormatException('Bad subfield in $tag');
          var j = i + 1;
          while (j < body.length && body[j] != subfieldDelimiter) {
            j++;
          }
          final s = utf8.decode(body.sublist(i + 1, j));
          subs.add(Subfield(s.substring(0, 1), s.substring(1)));
          i = j;
        }
        fields.add(MarcField.datafield(tag, ind1, ind2, subs));
      }
    }
    return MarcRecord(leader, fields);
  }

  // -------------------------------------------------------------------------
  // MARCXML (http://www.loc.gov/MARC21/slim).

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String toMarcXml(Iterable<MarcRecord> records) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<collection xmlns="http://www.loc.gov/MARC21/slim" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
          'xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">');
    for (final r in records) {
      // Write the leader as it would be in ISO 2709 (with real lengths).
      final leader = ascii.decode(toIso2709(r).sublist(0, 24));
      b
        ..writeln('  <record>')
        ..writeln('    <leader>${_esc(leader)}</leader>');
      for (final f in r.fields) {
        if (f.isControl) {
          b.writeln('    <controlfield tag="${f.tag}">${_esc(f.data!)}</controlfield>');
        } else {
          b.writeln('    <datafield tag="${f.tag}" ind1="${f.ind1}" ind2="${f.ind2}">');
          for (final s in f.subfields) {
            b.writeln('      <subfield code="${s.code}">${_esc(s.value)}</subfield>');
          }
          b.writeln('    </datafield>');
        }
      }
      b.writeln('  </record>');
    }
    b.writeln('</collection>');
    return b.toString();
  }
}
