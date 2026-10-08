/// ISBN handling per ISO 2108: normalisation, check-digit validation,
/// ISBN-10 to ISBN-13 conversion and discovery of ISBNs in free text.
library;

class Isbn {
  Isbn._();

  /// Removes hyphens, spaces and an optional "ISBN" prefix; upper-cases X.
  static String normalize(String raw) {
    var s = raw.trim().toUpperCase();
    s = s.replaceFirst(RegExp(r'^ISBN(-1[03])?:?\s*'), '');
    return s.replaceAll(RegExp(r'[\s\-]'), '');
  }

  static bool isValid(String raw) {
    final s = normalize(raw);
    if (s.length == 10) return isValid10(s);
    if (s.length == 13) return isValid13(s);
    return false;
  }

  static bool isValid10(String raw) {
    final s = normalize(raw);
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(s)) return false;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final c = s[i];
      final v = c == 'X' ? 10 : int.parse(c);
      sum += v * (10 - i);
    }
    return sum % 11 == 0;
  }

  static bool isValid13(String raw) {
    final s = normalize(raw);
    if (!RegExp(r'^97[89]\d{10}$').hasMatch(s)) return false;
    return _check13(s.substring(0, 12)) == s[12];
  }

  static String _check13(String first12) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(first12[i]) * (i.isEven ? 1 : 3);
    }
    return ((10 - sum % 10) % 10).toString();
  }

  /// Converts a valid ISBN-10 or ISBN-13 to ISBN-13. Returns null if invalid.
  static String? toIsbn13(String raw) {
    final s = normalize(raw);
    if (s.length == 13) return isValid13(s) ? s : null;
    if (s.length == 10 && isValid10(s)) {
      final core = '978${s.substring(0, 9)}';
      return core + _check13(core);
    }
    return null;
  }

  /// Finds valid ISBNs in [text], returned as ISBN-13, in order of appearance.
  static List<String> findAll(String text) {
    final out = <String>[];
    final re = RegExp(r'(?:ISBN(?:-1[03])?:?\s*)?((?:97[89][\s\-]?)?(?:\d[\s\-]?){9}[\dXx])');
    for (final m in re.allMatches(text)) {
      final candidate = m.group(1)!;
      final isbn13 = toIsbn13(candidate);
      if (isbn13 != null && !out.contains(isbn13)) out.add(isbn13);
    }
    return out;
  }
}
