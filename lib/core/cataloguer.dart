/// Auto-cataloguing: turns an imported file into a draft record.
///
/// Pipeline (spec section 8): extract embedded metadata and text, detect
/// identifiers, guess language, apply file-name rules, classify, then score
/// every field so weak values are highlighted for review. This is the rules
/// tier that runs on every device; the optional on-device LLM tier plugs in
/// through [DraftEnhancer].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'classifier.dart';
import 'extractors.dart';
import 'isbn.dart';
import 'record.dart';
import 'text.dart';

class ImportedFile {
  const ImportedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Hook for the optional LLM tier (Gemma via LiteRT-LM in the full product).
abstract class DraftEnhancer {
  Future<void> enhance(CatalogueRecord draft);
}

class Cataloguer {
  Cataloguer({Classifier? classifier}) : classifier = classifier ?? Classifier();

  final Classifier classifier;

  static const _book = {'epub', 'mobi', 'azw3', 'fb2'};
  static const _image = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'tif', 'tiff', 'bmp'};
  static const _video = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', 'm4v'};
  static const _audio = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'flac', 'opus', 'amr'};

  static const mimeTypes = {
    'epub': 'application/epub+zip',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'html': 'text/html',
    'htm': 'text/html',
    'csv': 'text/csv',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
  };

  static MediaType detectMediaType(String fileName, Uint8List bytes) {
    final ext = FileNameExtractor.extension(fileName);
    if (_book.contains(ext)) return MediaType.book;
    if (_image.contains(ext)) return MediaType.image;
    if (_video.contains(ext)) return MediaType.video;
    if (_audio.contains(ext)) return MediaType.audio;
    if (ext.isEmpty && bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50) return MediaType.document;
    return MediaType.document;
  }

  static String moduleFor(MediaType t) => switch (t) {
        MediaType.book => 'Books',
        MediaType.document => 'Documents',
        MediaType.image => 'Photos',
        MediaType.video => 'Videos',
        MediaType.audio => 'Audio',
        MediaType.other => 'Documents',
      };

  CatalogueRecord draft(ImportedFile file, {required String id, DateTime? now}) {
    final ext = FileNameExtractor.extension(file.name);
    var media = detectMediaType(file.name, file.bytes);

    // 1. Extract.
    Extracted ex;
    var embeddedSource = FieldSource.embedded;
    if (ext == 'epub') {
      ex = EpubExtractor.extract(file.bytes);
    } else if (ext == 'pdf') {
      ex = PdfExtractor.extract(file.bytes);
    } else if (ext == 'mp3') {
      ex = Id3Extractor.extract(file.bytes);
    } else if (media == MediaType.image) {
      ex = ImageExtractor.extract(file.bytes);
    } else if (const {'txt', 'md', 'html', 'htm', 'csv'}.contains(ext)) {
      ex = _textFile(file, ext);
      embeddedSource = FieldSource.content;
    } else {
      ex = Extracted();
    }
    final fromName = FileNameExtractor.parse(file.name);
    final text = ex.text;

    final record = CatalogueRecord(
      id: id,
      mediaType: media,
      fileName: file.name,
      sizeBytes: file.bytes.length,
      sha256: crypto.sha256.convert(file.bytes).toString(),
      pageCount: ex.pageCount,
      textContent: text,
      addedAt: now,
    );

    // 2. Identifiers (ISBN from metadata first, then text).
    final identifiers = <FieldValue>[];
    for (final raw in ex.identifiers) {
      final isbn = Isbn.toIsbn13(raw.replaceFirst(RegExp(r'^urn:isbn:', caseSensitive: false), ''));
      if (isbn != null) {
        identifiers.add(FieldValue('ISBN $isbn', source: embeddedSource, confidence: 0.97));
      } else if (RegExp(r'^(urn:uuid:|uuid:)', caseSensitive: false).hasMatch(raw)) {
        continue; // EPUB package UUIDs are not useful identifiers for people.
      } else if (raw.isNotEmpty) {
        identifiers.add(FieldValue(raw, source: embeddedSource, confidence: 0.8));
      }
    }
    if (!identifiers.any((v) => v.value.startsWith('ISBN'))) {
      final head = text.length > 20000 ? text.substring(0, 20000) : text;
      final found = Isbn.findAll(head);
      if (found.isNotEmpty) {
        identifiers.insert(0, FieldValue('ISBN ${found.first}', source: FieldSource.content, confidence: 0.92));
      }
      final doi = RegExp(r'\b(10\.\d{4,9}/[^\s"<>,;]+)').firstMatch(head);
      if (doi != null) {
        identifiers.add(FieldValue('doi:${doi.group(1)!.replaceAll(RegExp(r'[.)]+$'), '')}',
            source: FieldSource.content, confidence: 0.9));
      }
    }
    record.set(Dc.identifier, identifiers);
    // A PDF that carries an ISBN is a book, not just a document.
    if (media == MediaType.document && identifiers.any((v) => v.value.startsWith('ISBN'))) {
      media = MediaType.book;
      record.mediaType = media;
    }

    // 3. Title.
    if (ex.title != null && ex.title!.isNotEmpty && !_isJunkTitle(ex.title!)) {
      record.setOne(Dc.title, FieldValue(ex.title!, source: embeddedSource,
          confidence: embeddedSource == FieldSource.embedded ? 0.95 : 0.72));
    } else if (fromName.creator != null && fromName.title != null) {
      // "Author - Title (Year)" is a deliberate naming pattern: trust it.
      record.setOne(Dc.title, FieldValue(fromName.title!, source: FieldSource.filename, confidence: 0.75));
    } else if (_firstLineTitle(text) != null) {
      record.setOne(Dc.title, FieldValue(_firstLineTitle(text)!, source: FieldSource.content, confidence: 0.68));
    } else if (fromName.title != null && fromName.title!.isNotEmpty) {
      record.setOne(Dc.title, FieldValue(fromName.title!, source: FieldSource.filename,
          confidence: fromName.creator != null ? 0.75 : 0.55));
    } else {
      final when = ex.date ?? fromName.date;
      record.setOne(Dc.title, FieldValue(
          '${media.label}${when != null ? ' from $when' : ''}',
          source: FieldSource.rules, confidence: 0.4));
    }

    // 4. Creators.
    if (ex.creators.isNotEmpty) {
      record.set(Dc.creator, [
        for (final c in ex.creators)
          FieldValue(c, source: embeddedSource, confidence: embeddedSource == FieldSource.embedded ? 0.92 : 0.65),
      ]);
    } else if (fromName.creator != null) {
      record.setOne(Dc.creator, FieldValue(fromName.creator!, source: FieldSource.filename, confidence: 0.7));
    } else {
      final by = RegExp(r'^\s*(?:[Bb]y|[Aa]uthor:)\s+([A-Z][\w.\-’]+(?:[ \t]+[A-Z][\w.\-’]+){1,3})', multiLine: true)
          .firstMatch(text.length > 1500 ? text.substring(0, 1500) : text);
      if (by != null) record.setOne(Dc.creator, FieldValue(by.group(1)!, source: FieldSource.content, confidence: 0.6));
    }

    // 5. Date.
    if (ex.date != null && ex.date!.isNotEmpty) {
      record.setOne(Dc.date, FieldValue(_normaliseDate(ex.date!), source: embeddedSource,
          confidence: media == MediaType.image ? 0.9 : 0.88));
    } else if (fromName.date != null) {
      record.setOne(Dc.date, FieldValue(fromName.date!, source: FieldSource.filename,
          confidence: fromName.isCameraName ? 0.8 : 0.6));
    } else {
      final d = _dateInText(text);
      if (d != null) record.setOne(Dc.date, FieldValue(d, source: FieldSource.content, confidence: 0.6));
    }

    // 6. Publisher.
    if (ex.publisher != null && ex.publisher!.isNotEmpty) {
      record.setOne(Dc.publisher, FieldValue(ex.publisher!, source: embeddedSource, confidence: 0.9));
    }

    // 7. Language.
    final embeddedLang = _languageCode(ex.language);
    final guess = TextTools.guessLanguage(text);
    if (embeddedLang != null) {
      record.setOne(Dc.language, FieldValue(embeddedLang, source: embeddedSource, confidence: 0.95));
    } else if (guess != null) {
      record.setOne(Dc.language, FieldValue(guess.code, source: FieldSource.rules,
          confidence: (0.5 + guess.confidence / 2).clamp(0.0, 0.97).toDouble()));
    }

    // 8. Description: embedded, else a two-sentence extractive summary.
    if (ex.description != null && ex.description!.isNotEmpty) {
      record.setOne(Dc.description, FieldValue(ex.description!, source: embeddedSource, confidence: 0.9));
    } else if (text.trim().isNotEmpty) {
      final summary = _summary(text, record.title);
      if (summary.isNotEmpty) {
        record.setOne(Dc.description, FieldValue(summary, source: FieldSource.rules, confidence: 0.6));
      }
    }

    // 9. Type and format.
    record.setOne(Dc.type, FieldValue(media.dcmiType, source: FieldSource.rules, confidence: 0.99));
    final mime = mimeTypes[ext];
    if (mime != null) {
      final extent = ex.pageCount != null ? '; ${ex.pageCount} pages' : '';
      record.setOne(Dc.format, FieldValue('$mime$extent', source: FieldSource.rules, confidence: 0.99));
    }

    // 10. Classification and subjects.
    final result = classifier.classify(
      title: record.title,
      description: record.text(Dc.description),
      subjects: ex.subjects,
      text: text,
      language: record.text(Dc.language),
    );
    record.classSuggestions
      ..clear()
      ..addAll(result.suggestions);
    final subjects = <FieldValue>[
      for (final s in ex.subjects) FieldValue(s, source: embeddedSource, confidence: 0.88),
    ];
    for (final s in result.subjects) {
      if (subjects.length >= 5) break;
      if (subjects.any((v) => v.value.toLowerCase() == s.toLowerCase())) continue;
      subjects.add(FieldValue(s, source: FieldSource.rules, confidence: 0.62));
    }
    record.set(Dc.subject, subjects);
    if (result.suggestions.isNotEmpty && result.suggestions.first.confidence >= 0.5) {
      record.classNumber = result.suggestions.first.number;
    }

    record.module = moduleFor(media);
    return record;
  }

  Extracted _textFile(ImportedFile file, String ext) {
    final out = Extracted();
    var s = String.fromCharCodes(file.bytes);
    try {
      s = const Utf8Codec(allowMalformed: true).decode(file.bytes);
    } catch (_) {}
    if (ext == 'html' || ext == 'htm') {
      final t = RegExp(r'<title>([\s\S]*?)</title>', caseSensitive: false).firstMatch(s);
      if (t != null) out.title = stripMarkup(t.group(1)!);
      s = stripMarkup(s);
    }
    out.text = s;
    if (out.title == null) {
      for (final line in s.split('\n')) {
        final l = line.trim();
        if (l.isEmpty) continue;
        final heading = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(l);
        if (heading != null) {
          out.title = heading.group(1)!.trim();
        } else if (l.length <= 120 && !l.endsWith('.')) {
          out.title = l;
        }
        break;
      }
    }
    return out;
  }

  /// A short first line of the text that reads like a heading.
  static String? _firstLineTitle(String text) {
    for (final line in text.split('\n')) {
      final l = line.trim().replaceFirst(RegExp(r'^#{1,3}\s+'), '');
      if (l.isEmpty) continue;
      final words = l.split(RegExp(r'\s+')).length;
      if (l.length >= 4 && l.length <= 120 && words <= 14 && !l.endsWith('.') && !l.contains('. ') &&
          RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(l)) {
        return l;
      }
      return null;
    }
    return null;
  }

  static bool _isJunkTitle(String t) {
    final s = t.trim().toLowerCase();
    return s.isEmpty ||
        s == 'untitled' ||
        s.startsWith('microsoft word - ') ||
        RegExp(r'^[\w\-]+\.(docx?|pdf|indd|tex)$').hasMatch(s) ||
        RegExp(r'^(document|scan|img)[\s_\-]*\d*$').hasMatch(s);
  }

  static String _normaliseDate(String raw) {
    final iso = RegExp(r'^((?:1[5-9]|20)\d{2})(?:-(\d{2}))?(?:-(\d{2}))?').firstMatch(raw.trim());
    if (iso != null) return [iso.group(1), iso.group(2), iso.group(3)].whereType<String>().join('-');
    final year = RegExp(r'\b((?:1[5-9]|20)\d{2})\b').firstMatch(raw);
    return year?.group(1) ?? raw.trim();
  }

  static const _months = {
    'january': '01', 'february': '02', 'march': '03', 'april': '04', 'may': '05', 'june': '06',
    'july': '07', 'august': '08', 'september': '09', 'october': '10', 'november': '11', 'december': '12',
  };

  static String? _dateInText(String text) {
    final head = text.length > 4000 ? text.substring(0, 4000) : text;
    final iso = RegExp(r'\b((?:19|20)\d{2})-(\d{2})-(\d{2})\b').firstMatch(head);
    if (iso != null) return iso.group(0);
    final long = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(January|February|March|April|May|June|July|August|September|October|November|December),?\s+((?:19|20)\d{2})\b',
      caseSensitive: false,
    ).firstMatch(head);
    if (long != null) {
      final m = _months[long.group(2)!.toLowerCase()]!;
      return '${long.group(3)}-$m-${long.group(1)!.padLeft(2, '0')}';
    }
    final copy = RegExp(r'(?:©|\(c\)|copyright)\s*((?:19|20)\d{2})', caseSensitive: false).firstMatch(head);
    return copy?.group(1);
  }

  static String? _languageCode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim().toLowerCase();
    const map = {
      'en': 'eng', 'eng': 'eng', 'english': 'eng',
      'fr': 'fre', 'fra': 'fre', 'fre': 'fre', 'french': 'fre',
      'es': 'spa', 'spa': 'spa', 'spanish': 'spa',
      'de': 'ger', 'deu': 'ger', 'ger': 'ger', 'german': 'ger',
      'pt': 'por', 'por': 'por', 'portuguese': 'por',
      'tw': 'twi', 'twi': 'twi', 'ak': 'aka', 'aka': 'aka',
      'ee': 'ewe', 'ewe': 'ewe', 'ha': 'hau', 'hau': 'hau', 'yo': 'yor', 'yor': 'yor', 'sw': 'swa', 'swa': 'swa',
    };
    return map[s.split(RegExp(r'[-_]')).first] ?? (s.length == 3 ? s : null);
  }

  static String _summary(String text, String title) {
    // Drop heading lines and the title itself so the summary starts with prose.
    final body = text
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#') && l.trim() != title.trim())
        .join('\n');
    final sentences = TextTools.sentences(body)
        .where((s) => s.split(' ').length >= 5 && s.trim() != title.trim())
        .take(2)
        .toList();
    var out = sentences.join(' ');
    if (out.length > 320) out = '${out.substring(0, 317).trimRight()}…';
    return out;
  }
}
