/// Text utilities shared by cataloguing, classification and search:
/// tokenising, a light English stemmer, stop words and language guessing.
library;

class TextTools {
  TextTools._();

  static final _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}]+)?", unicode: true);

  /// Lower-cased word tokens, apostrophe suffixes removed.
  static List<String> words(String text) => [
        for (final m in _word.allMatches(text.toLowerCase()))
          m.group(0)!.replaceAll(RegExp(r"['’].*$"), ''),
      ];

  /// Content tokens: stop words removed, light stemming applied.
  static List<String> terms(String text) => [
        for (final w in words(text))
          if (w.length > 1 && !stopWords.contains(w)) stem(w),
      ];

  /// A deliberately light suffix-stripping stemmer (English). It conflates
  /// plurals and common verb forms, which is what matters for search recall.
  static String stem(String w) {
    if (w.length <= 3 || RegExp(r'^\d+$').hasMatch(w)) return w;
    if (w.endsWith('ies') && w.length > 4) return '${w.substring(0, w.length - 3)}y';
    if (w.endsWith('sses')) return w.substring(0, w.length - 2);
    if (w.endsWith('ing') && w.length > 5) return _undouble(w.substring(0, w.length - 3));
    if (w.endsWith('ed') && w.length > 4) return _undouble(w.substring(0, w.length - 2));
    if (w.endsWith('es') && w.length > 4 && RegExp(r'(ch|sh|x|z)es$').hasMatch(w)) {
      return w.substring(0, w.length - 2);
    }
    if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static String _undouble(String w) {
    if (w.length > 2 && w[w.length - 1] == w[w.length - 2] && !'lsz'.contains(w[w.length - 1])) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static const stopWords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'by', 'for',
    'with', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'it',
    'its', 'this', 'that', 'these', 'those', 'my', 'me', 'i', 'we', 'our', 'you',
    'your', 'he', 'she', 'his', 'her', 'they', 'their', 'them', 'what', 'which',
    'who', 'whom', 'where', 'when', 'how', 'do', 'does', 'did', 'about', 'say',
    'says', 'any', 'all', 'some', 'no', 'not', 'can', 'will', 'would', 'should',
    'into', 'than', 'then', 'there', 'so', 'if', 'up', 'out', 'has', 'have', 'had',
    'find', 'show', 'get', 'le', 'la', 'les', 'de', 'des', 'et', 'un', 'une', 'du',
  };

  static const _languageMarkers = {
    'eng': {'the', 'and', 'of', 'to', 'is', 'in', 'that', 'it', 'was', 'with', 'for', 'this'},
    'fre': {'le', 'la', 'les', 'et', 'des', 'est', 'une', 'dans', 'que', 'pour', 'pas', 'sur'},
    'spa': {'el', 'los', 'las', 'y', 'es', 'una', 'que', 'por', 'para', 'con', 'del', 'como'},
    'ger': {'der', 'die', 'das', 'und', 'ist', 'nicht', 'mit', 'ein', 'eine', 'auf', 'für', 'dem'},
    'por': {'os', 'as', 'não', 'uma', 'com', 'para', 'que', 'em', 'dos', 'das', 'mais', 'ao'},
  };

  static const languageNames = {
    'eng': 'English',
    'fre': 'French',
    'spa': 'Spanish',
    'ger': 'German',
    'por': 'Portuguese',
  };

  /// Guesses the language (ISO 639-2/B code, as used by MARC 21) from
  /// function-word frequency. Returns null when the text is too short or
  /// no language clearly wins. The confidence is the winner's share.
  static ({String code, double confidence})? guessLanguage(String text) {
    final ws = words(text.length > 20000 ? text.substring(0, 20000) : text);
    if (ws.length < 20) return null;
    final scores = <String, int>{};
    for (final w in ws) {
      for (final e in _languageMarkers.entries) {
        if (e.value.contains(w)) scores[e.key] = (scores[e.key] ?? 0) + 1;
      }
    }
    if (scores.isEmpty) return null;
    final total = scores.values.fold<int>(0, (a, b) => a + b);
    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value < 5) return null;
    return (code: best.key, confidence: best.value / total);
  }

  /// Splits text into sentences (for summaries and passage answers).
  static List<String> sentences(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9“"(])'))
      .map((s) => s.trim())
      .where((s) => s.length > 2)
      .toList();

  /// Title-cases a phrase taken from a file name.
  static String titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 3 && _smallWords.contains(w.toLowerCase())
          ? w.toLowerCase()
          : w[0].toUpperCase() + w.substring(1))
      .join(' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());

  static const _smallWords = {'a', 'an', 'the', 'of', 'and', 'or', 'in', 'on', 'at', 'to', 'for', 'by'};
}
