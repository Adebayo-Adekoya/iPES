/// Metadata and text extractors used by the cataloguer.
///
/// Each extractor is tolerant: malformed input yields an empty result rather
/// than an exception, because users import whatever is on their phone.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Metadata found inside a file, before it is merged into a record.
class Extracted {
  String? title;
  final List<String> creators = [];
  String? publisher;
  String? date;
  String? language;
  final List<String> subjects = [];
  String? description;
  final List<String> identifiers = [];
  String text = '';
  int? pageCount;

  bool get isEmpty =>
      title == null && creators.isEmpty && date == null && text.isEmpty && identifiers.isEmpty;
}

String _utf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

String _latin1(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

final _entity = RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp|rsquo|lsquo|ldquo|rdquo|mdash|ndash|hellip);');

/// Strips HTML/XHTML tags and decodes common entities.
String stripMarkup(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</h[1-6]>|</div>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
      case 'rsquo':
      case 'lsquo':
        return "'";
      case 'ldquo':
      case 'rdquo':
        return '"';
      case 'nbsp':
        return ' ';
      case 'mdash':
        return '—';
      case 'ndash':
        return '–';
      case 'hellip':
        return '…';
    }
    final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return code == null ? ' ' : String.fromCharCode(code);
  });
  return s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n').trim();
}

// ---------------------------------------------------------------------------
// EPUB (OPF package metadata, which is Dublin Core).

class EpubExtractor {
  static Extracted extract(Uint8List bytes, {int maxText = 400000}) {
    final out = Extracted();
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? read(String path) {
        final f = archive.findFile(path);
        return f == null ? null : _utf8(f.content);
      }

      final container = read('META-INF/container.xml');
      if (container == null) return out;
      final rootPath = XmlDocument.parse(container)
          .descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.name.local == 'rootfile')
          .getAttribute('full-path');
      if (rootPath == null) return out;
      final opfText = read(rootPath);
      if (opfText == null) return out;
      final opf = XmlDocument.parse(opfText);
      final baseDir = rootPath.contains('/') ? rootPath.substring(0, rootPath.lastIndexOf('/') + 1) : '';

      Iterable<XmlElement> dc(String local) => opf.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == local && (e.name.prefix == 'dc' || e.namespaceUri == 'http://purl.org/dc/elements/1.1/'));

      String? firstText(String local) {
        final e = dc(local);
        return e.isEmpty ? null : _clean(e.first.innerText);
      }

      out.title = firstText('title');
      out.creators.addAll(dc('creator').map((e) => _clean(e.innerText)).where((s) => s.isNotEmpty));
      out.publisher = firstText('publisher');
      out.date = firstText('date');
      out.language = firstText('language');
      out.description = firstText('description');
      out.subjects.addAll(dc('subject').map((e) => _clean(e.innerText)).where((s) => s.isNotEmpty));
      out.identifiers.addAll(dc('identifier').map((e) => _clean(e.innerText)).where((s) => s.isNotEmpty));
      if (out.description != null) out.description = stripMarkup(out.description!);

      // Spine order text, for search and summaries.
      final manifest = <String, String>{};
      for (final item in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id != null && href != null) manifest[id] = href;
      }
      final buffer = StringBuffer();
      for (final ref in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'itemref')) {
        final href = manifest[ref.getAttribute('idref')];
        if (href == null) continue;
        final html = read(baseDir + Uri.decodeComponent(href));
        if (html == null) continue;
        buffer.writeln(stripMarkup(html));
        if (buffer.length > maxText) break;
      }
      out.text = buffer.toString();
    } catch (_) {
      // Not a valid EPUB: return what we have.
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// PDF: Info dictionary, XMP packet, page count and text from Flate streams.

class PdfExtractor {
  static Extracted extract(Uint8List bytes, {int maxText = 400000}) {
    final out = Extracted();
    final limit = bytes.length > 30 * 1024 * 1024 ? 30 * 1024 * 1024 : bytes.length;
    final raw = _latin1(Uint8List.sublistView(bytes, 0, limit));
    if (!raw.startsWith('%PDF')) return out;

    String? info(String key) {
      final m = RegExp('/$key\\s*(\\((?:\\\\.|[^\\\\)])*\\)|<[0-9A-Fa-f\\s]*>)').firstMatch(raw);
      if (m == null) return null;
      final v = _clean(decodePdfString(m.group(1)!));
      return v.isEmpty ? null : v;
    }

    out.title = info('Title');
    final author = info('Author');
    if (author != null) out.creators.add(author);
    out.description = info('Subject');
    final keywords = info('Keywords');
    if (keywords != null) {
      out.subjects.addAll(keywords.split(RegExp(r'[;,]')).map(_clean).where((s) => s.isNotEmpty));
    }
    final created = info('CreationDate');
    if (created != null) {
      final m = RegExp(r'(?:D:)?(\d{4})(\d{2})?(\d{2})?').firstMatch(created);
      if (m != null) {
        out.date = [m.group(1), m.group(2), m.group(3)].whereType<String>().join('-');
      }
    }

    // XMP (often uncompressed); fills gaps left by the Info dictionary.
    final xmpTitle = RegExp(r'<dc:title>[\s\S]*?<rdf:li[^>]*>([\s\S]*?)</rdf:li>').firstMatch(raw);
    if (out.title == null && xmpTitle != null) out.title = _clean(stripMarkup(xmpTitle.group(1)!));
    final xmpCreator = RegExp(r'<dc:creator>[\s\S]*?<rdf:li[^>]*>([\s\S]*?)</rdf:li>').firstMatch(raw);
    if (out.creators.isEmpty && xmpCreator != null) out.creators.add(_clean(stripMarkup(xmpCreator.group(1)!)));

    // Page count: the largest /Count in a /Pages node, else count /Page objects.
    var pages = 0;
    for (final m in RegExp(r'/Type\s*/Pages[^>]*?/Count\s+(\d+)|/Count\s+(\d+)[^>]*?/Type\s*/Pages').allMatches(raw)) {
      final n = int.tryParse(m.group(1) ?? m.group(2) ?? '') ?? 0;
      if (n > pages) pages = n;
    }
    if (pages == 0) pages = RegExp(r'/Type\s*/Page(?![s\w])').allMatches(raw).length;
    if (pages > 0) out.pageCount = pages;

    out.text = _text(bytes, raw, maxText);
    return out;
  }

  static String _text(Uint8List bytes, String raw, int maxText) {
    final buffer = StringBuffer();
    final streamRe = RegExp(r'stream\r?\n');
    var from = 0;
    while (buffer.length < maxText) {
      final it = streamRe.allMatches(raw, from).iterator;
      if (!it.moveNext()) break;
      final m = it.current;
      final start = m.end;
      final end = raw.indexOf('endstream', start);
      if (end < 0) break;
      final dictStart = math.max(0, m.start - 400);
      final dict = raw.substring(dictStart, m.start);
      final lastDict = dict.substring(dict.lastIndexOf('<<') < 0 ? 0 : dict.lastIndexOf('<<'));
      from = end + 9;
      if (RegExp(r'/Subtype\s*/Image|/Type\s*/XObject|/Type\s*/XRef|/Type\s*/Metadata').hasMatch(lastDict)) {
        continue;
      }
      List<int> data = Uint8List.sublistView(bytes, start, end);
      if (lastDict.contains('/FlateDecode')) {
        try {
          data = const ZLibDecoder().decodeBytes(data);
        } catch (_) {
          continue;
        }
      } else if (RegExp(r'/Filter').hasMatch(lastDict)) {
        continue; // Other filters (DCT, LZW…) are not text we can read here.
      }
      final content = _latin1(data);
      if (!content.contains('Tj') && !content.contains('TJ')) continue;
      buffer.write(_textOps(content));
    }
    final text = buffer.toString();
    return text.length > maxText ? text.substring(0, maxText) : text;
  }

  /// Reads text-showing operators (Tj, TJ, ', ") from a content stream.
  static String _textOps(String content) {
    final out = StringBuffer();
    final re = RegExp(r"(\((?:\\.|[^\\)])*\))\s*(?:Tj|'|\x22)|\[((?:[^\]\\]|\\.)*)\]\s*TJ|(T\*|Td|TD|ET)");
    for (final m in re.allMatches(content)) {
      if (m.group(1) != null) {
        out.write(decodePdfString(m.group(1)!));
      } else if (m.group(2) != null) {
        for (final s in RegExp(r'\((?:\\.|[^\\)])*\)|(-?\d+(?:\.\d+)?)').allMatches(m.group(2)!)) {
          if (s.group(1) != null) {
            final kern = double.tryParse(s.group(1)!) ?? 0;
            if (kern < -200) out.write(' ');
          } else {
            out.write(decodePdfString(s.group(0)!));
          }
        }
      } else {
        out.write('\n'); // line move or end of text block
      }
    }
    final s = out.toString();
    // Discard glyph-coded runs that are not readable text.
    final printable = RegExp(r'[\x20-\x7E\u00A0-\u024F\n]').allMatches(s).length;
    return s.isEmpty || printable / s.length < 0.85 ? '' : '$s\n';
  }

  /// Decodes a PDF literal "(...)" or hex "<...>" string, including UTF-16BE.
  static String decodePdfString(String token) {
    final codes = <int>[];
    if (token.startsWith('<')) {
      final hex = token.substring(1, token.length - 1).replaceAll(RegExp(r'\s'), '');
      final padded = hex.length.isOdd ? '${hex}0' : hex;
      for (var i = 0; i + 1 < padded.length; i += 2) {
        codes.add(int.parse(padded.substring(i, i + 2), radix: 16));
      }
    } else {
      final s = token.substring(1, token.length - 1);
      for (var i = 0; i < s.length; i++) {
        final c = s[i];
        if (c != r'\' || i + 1 >= s.length) {
          codes.add(s.codeUnitAt(i) & 0xFF);
          continue;
        }
        final n = s[++i];
        switch (n) {
          case 'n':
            codes.add(10);
          case 'r':
            codes.add(13);
          case 't':
            codes.add(9);
          case 'b':
            codes.add(8);
          case 'f':
            codes.add(12);
          case '\n':
          case '\r':
            break; // line continuation
          default:
            if (RegExp(r'[0-7]').hasMatch(n)) {
              var oct = n;
              while (oct.length < 3 && i + 1 < s.length && RegExp(r'[0-7]').hasMatch(s[i + 1])) {
                oct += s[++i];
              }
              codes.add(int.parse(oct, radix: 8) & 0xFF);
            } else {
              codes.add(n.codeUnitAt(0) & 0xFF);
            }
        }
      }
    }
    if (codes.length >= 2 && codes[0] == 0xFE && codes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < codes.length; i += 2) {
        units.add((codes[i] << 8) | codes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return latin1.decode(codes, allowInvalid: true);
  }
}

// ---------------------------------------------------------------------------
// MP3 ID3v2.3 / 2.4 text frames.

class Id3Extractor {
  static Extracted extract(Uint8List b) {
    final out = Extracted();
    if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return out; // "ID3"
    final version = b[3];
    int synchsafe(int o) => (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];
    final tagEnd = math.min(10 + synchsafe(6), b.length);
    var p = 10;
    while (p + 10 <= tagEnd) {
      final id = String.fromCharCodes(b.sublist(p, p + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
      final size = version >= 4
          ? synchsafe(p + 4)
          : (b[p + 4] << 24) | (b[p + 5] << 16) | (b[p + 6] << 8) | b[p + 7];
      final start = p + 10;
      final end = start + size;
      if (size <= 0 || end > tagEnd) break;
      if (id.startsWith('T')) {
        final v = _decodeText(b.sublist(start, end));
        switch (id) {
          case 'TIT2':
            out.title = v;
          case 'TPE1':
            out.creators.add(v);
          case 'TALB':
            out.subjects.add(v);
          case 'TYER':
          case 'TDRC':
            out.date = v;
          case 'TCON':
            out.subjects.add(v.replaceAll(RegExp(r'^\(\d+\)'), ''));
          case 'TLAN':
            out.language = v;
          case 'TPUB':
            out.publisher = v;
        }
      }
      p = end;
    }
    return out;
  }

  static String _decodeText(List<int> data) {
    if (data.isEmpty) return '';
    final enc = data[0];
    var body = data.sublist(1);
    String s;
    switch (enc) {
      case 1:
      case 2:
        var bigEndian = enc == 2;
        if (body.length >= 2 && body[0] == 0xFF && body[1] == 0xFE) {
          bigEndian = false;
          body = body.sublist(2);
        } else if (body.length >= 2 && body[0] == 0xFE && body[1] == 0xFF) {
          bigEndian = true;
          body = body.sublist(2);
        }
        final units = <int>[];
        for (var i = 0; i + 1 < body.length; i += 2) {
          units.add(bigEndian ? (body[i] << 8) | body[i + 1] : body[i] | (body[i + 1] << 8));
        }
        s = String.fromCharCodes(units);
      case 3:
        s = _utf8(body);
      default:
        s = _latin1(body);
    }
    return _clean(s.replaceAll('\u0000', ' '));
  }
}

// ---------------------------------------------------------------------------
// Photos: EXIF capture date found in the first part of the file.

class ImageExtractor {
  static Extracted extract(Uint8List bytes) {
    final out = Extracted();
    final head = _latin1(Uint8List.sublistView(bytes, 0, math.min(bytes.length, 131072)));
    final m = RegExp(r'((?:19|20)\d{2}):(\d{2}):(\d{2}) \d{2}:\d{2}:\d{2}').firstMatch(head);
    if (m != null) out.date = '${m.group(1)}-${m.group(2)}-${m.group(3)}';
    return out;
  }
}

// ---------------------------------------------------------------------------
// File names: "Author - Title (Year)", camera names, dates.

class FileNameInfo {
  String? title;
  String? creator;
  String? date;
  bool isCameraName = false;
}

class FileNameExtractor {
  static String stem(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static String extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  static FileNameInfo parse(String fileName) {
    final info = FileNameInfo();
    final s = stem(fileName);

    final camera = RegExp(
      r'^(IMG|VID|PXL|DSC|DSCN|DCIM|MVIMG|Screenshot|WhatsApp Image|WhatsApp Video|AUD|REC|scan|Scan)[_\- ]*((?:19|20)\d{2})[\-_]?(\d{2})[\-_]?(\d{2})',
      caseSensitive: false,
    ).firstMatch(s);
    if (camera != null) {
      info.isCameraName = true;
      info.date = '${camera.group(2)}-${camera.group(3)}-${camera.group(4)}';
      return info;
    }
    if (RegExp(r'^(IMG|VID|PXL|DSC|DSCN|scan|Scan|AUD|REC)[_\- ]*\d+$', caseSensitive: false).hasMatch(s)) {
      info.isCameraName = true;
      return info;
    }

    var clean = s.replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final year = RegExp(r'[\(\[]((?:19|20)\d{2})[\)\]]').firstMatch(clean) ??
        RegExp(r'\b((?:19|20)\d{2})\b').firstMatch(clean);
    if (year != null) info.date = year.group(1);
    clean = clean.replaceAll(RegExp(r'\s*[\(\[](?:19|20)\d{2}[\)\]]\s*'), ' ').trim();

    final dash = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(clean);
    if (dash != null) {
      final left = dash.group(1)!.trim();
      final right = dash.group(2)!.trim();
      // "Author - Title" when the left part looks like a name (2–4 words, no digits).
      if (RegExp(r'^[^\d]+$').hasMatch(left) && left.split(' ').length <= 4) {
        info.creator = left;
        info.title = right;
      } else {
        info.title = clean;
      }
    } else {
      info.title = clean.replaceAll(RegExp(r'(?<=\w)\.(?=\w)'), ' ');
    }
    if (info.title != null && info.title == info.title!.toLowerCase()) {
      info.title = info.title!.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    }
    return info;
  }
}
