/// Builders for small but structurally valid files (EPUB, PDF, MP3 tags,
/// JPEG EXIF, MP4 header). Used for the demo library, tests and evaluation,
/// so the cataloguer is exercised on real file formats, not mocks.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class EpubBuilder {
  static Uint8List build({
    required String title,
    List<String> creators = const [],
    String? date,
    String language = 'en',
    String? publisher,
    String? isbn,
    List<String> subjects = const [],
    String? description,
    required List<String> chapters,
  }) {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final opf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">')
      ..writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">')
      ..writeln('    <dc:identifier id="uid">${isbn != null ? 'urn:isbn:$isbn' : 'urn:uuid:${title.hashCode.toRadixString(16)}'}</dc:identifier>')
      ..writeln('    <dc:title>${esc(title)}</dc:title>');
    for (final c in creators) {
      opf.writeln('    <dc:creator>${esc(c)}</dc:creator>');
    }
    if (date != null) opf.writeln('    <dc:date>$date</dc:date>');
    opf.writeln('    <dc:language>$language</dc:language>');
    if (publisher != null) opf.writeln('    <dc:publisher>${esc(publisher)}</dc:publisher>');
    for (final s in subjects) {
      opf.writeln('    <dc:subject>${esc(s)}</dc:subject>');
    }
    if (description != null) opf.writeln('    <dc:description>${esc(description)}</dc:description>');
    opf
      ..writeln('  </metadata>')
      ..writeln('  <manifest>');
    for (var i = 0; i < chapters.length; i++) {
      opf.writeln('    <item id="c$i" href="text/ch$i.xhtml" media-type="application/xhtml+xml"/>');
    }
    opf
      ..writeln('  </manifest>')
      ..writeln('  <spine>');
    for (var i = 0; i < chapters.length; i++) {
      opf.writeln('    <itemref idref="c$i"/>');
    }
    opf
      ..writeln('  </spine>')
      ..writeln('</package>');

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('mimetype', 'application/epub+zip');
    add('META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
    add('OEBPS/content.opf', opf.toString());
    for (var i = 0; i < chapters.length; i++) {
      add('OEBPS/text/ch$i.xhtml',
          '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter ${i + 1}</title></head>'
          '<body><h1>Chapter ${i + 1}</h1>${chapters[i].split('\n\n').map((p) => '<p>${esc(p)}</p>').join()}</body></html>');
    }
    return ZipEncoder().encodeBytes(archive);
  }
}

class PdfBuilder {
  /// A PDF 1.4 file with Helvetica text. [pages] is a list of page texts.
  static Uint8List build({
    String? title,
    String? author,
    String? subject,
    String? keywords,
    String? creationDate, // "2025-03-01" or "2025"
    required List<String> pages,
    bool compress = true,
  }) {
    final out = BytesBuilder();
    final offsets = <int>[];
    void raw(String s) => out.add(latin1.encode(s));
    void obj(int n, String body) {
      offsets.add(out.length);
      raw('$n 0 obj\n$body\nendobj\n');
    }

    String lit(String s) {
      final ascii = s.replaceAll(RegExp(r'[^\x20-\x7E\u00A0-\u00FF]'), '?');
      return '(${ascii.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)')})';
    }

    raw('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    final pageCount = pages.length;
    final firstPage = 4;
    final kids = [for (var i = 0; i < pageCount; i++) '${firstPage + i * 2} 0 R'].join(' ');
    obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
    obj(2, '<< /Type /Pages /Kids [$kids] /Count $pageCount >>');
    obj(3, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    for (var i = 0; i < pageCount; i++) {
      final pageObj = firstPage + i * 2;
      obj(pageObj,
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${pageObj + 1} 0 R >>');
      final content = StringBuffer('BT /F1 11 Tf 14 TL 56 790 Td\n');
      for (final line in _wrap(pages[i], 88)) {
        content.writeln('${lit(line)} Tj T*');
      }
      content.write('ET');
      final data = latin1.encode(content.toString().replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));
      offsets.add(out.length);
      if (compress) {
        final z = ZLibEncoder().encodeBytes(data);
        raw('${pageObj + 1} 0 obj\n<< /Length ${z.length} /Filter /FlateDecode >>\nstream\n');
        out.add(z);
      } else {
        raw('${pageObj + 1} 0 obj\n<< /Length ${data.length} >>\nstream\n');
        out.add(data);
      }
      raw('\nendstream\nendobj\n');
    }
    final infoObj = firstPage + pageCount * 2;
    final info = StringBuffer('<< /Producer (iPES sample builder)');
    if (title != null) info.write(' /Title ${_pdfText(title, lit)}');
    if (author != null) info.write(' /Author ${_pdfText(author, lit)}');
    if (subject != null) info.write(' /Subject ${lit(subject)}');
    if (keywords != null) info.write(' /Keywords ${lit(keywords)}');
    if (creationDate != null) info.write(' /CreationDate (D:${creationDate.replaceAll('-', '')}000000Z)');
    info.write(' >>');
    obj(infoObj, info.toString());

    final xref = out.length;
    raw('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      raw('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    raw('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info $infoObj 0 R >>\nstartxref\n$xref\n%%EOF\n');
    return out.toBytes();
  }

  /// Non-Latin-1 text is written as UTF-16BE hex with a BOM, as PDF requires.
  static String _pdfText(String s, String Function(String) lit) {
    if (RegExp(r'^[\x20-\x7E\u00A0-\u00FF]*$').hasMatch(s)) return lit(s);
    final b = StringBuffer('<FEFF');
    for (final unit in s.codeUnits) {
      b.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    b.write('>');
    return b.toString();
  }

  static List<String> _wrap(String text, int width) {
    final lines = <String>[];
    for (final para in text.split('\n')) {
      var line = '';
      for (final word in para.split(' ')) {
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          lines.add(line);
          line = word;
        }
      }
      lines.add(line);
    }
    return lines;
  }
}

class Mp3Builder {
  /// ID3v2.4 tag (UTF-8 text frames) followed by a few silent MPEG frames.
  static Uint8List build({String? title, String? artist, String? album, String? year, String? genre, String? language}) {
    final frames = BytesBuilder();
    void frame(String id, String? value) {
      if (value == null) return;
      final body = [3, ...utf8.encode(value)];
      frames
        ..add(ascii.encode(id))
        ..add(_synchsafe(body.length))
        ..add([0, 0])
        ..add(body);
    }

    frame('TIT2', title);
    frame('TPE1', artist);
    frame('TALB', album);
    frame('TDRC', year);
    frame('TCON', genre);
    frame('TLAN', language);
    final f = frames.toBytes();
    final silent = List<int>.generate(417 * 4, (i) => i % 417 == 0 ? 0xFF : (i % 417 == 1 ? 0xFB : 0));
    return (BytesBuilder()
          ..add(ascii.encode('ID3'))
          ..add([4, 0, 0])
          ..add(_synchsafe(f.length))
          ..add(f)
          ..add(silent))
        .toBytes();
  }

  static List<int> _synchsafe(int n) => [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];
}

class JpegBuilder {
  /// A JPEG-shaped byte sequence with an EXIF APP1 segment holding
  /// DateTimeOriginal. Enough for metadata extraction, not for display.
  static Uint8List build({String? dateTimeOriginal}) {
    final exif = BytesBuilder()
      ..add(ascii.encode('Exif'))
      ..add([0, 0])
      ..add(ascii.encode('II*'))
      ..add([0, 8, 0, 0, 0]);
    if (dateTimeOriginal != null) exif.add([...ascii.encode(dateTimeOriginal), 0]);
    exif.add(List<int>.filled(64, 0));
    final payload = exif.toBytes();
    final len = payload.length + 2;
    return (BytesBuilder()
          ..add([0xFF, 0xD8, 0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF])
          ..add(payload)
          ..add(List<int>.generate(512, (i) => (i * 37) & 0xFF))
          ..add([0xFF, 0xD9]))
        .toBytes();
  }
}

class Mp4Builder {
  /// [seed] makes each sample file unique (identical bytes would be
  /// treated as duplicates by the library).
  static Uint8List build({int seed = 0}) => Uint8List.fromList([
        0, 0, 0, 24, ...ascii.encode('ftypisom'), 0, 0, 2, 0, ...ascii.encode('isomiso2'),
        ...List<int>.generate(1024, (i) => (i * 13 + seed * 7919) & 0xFF),
        seed & 0xFF, (seed >> 8) & 0xFF,
      ]);
}
