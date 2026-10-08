/// Auto-classification: suggests Dewey Decimal classes and subject terms.
///
/// The prototype uses a keyword lexicon per class (the "rules" tier that the
/// spec says must work on every phone). The full product adds embedding
/// nearest-neighbour matching and an on-device LLM to choose between close
/// candidates. Labels follow the freely available DDC summaries; the full
/// schedules are licensed by OCLC.
library;

import 'record.dart';
import 'text.dart';

class DeweyClass {
  const DeweyClass(this.number, this.label, this.keywords);
  final String number;
  final String label;
  final List<String> keywords;
}

class ClassificationResult {
  const ClassificationResult(this.suggestions, this.subjects);
  final List<ClassSuggestion> suggestions;

  /// Subject terms (controlled by this lexicon) found in the item.
  final List<String> subjects;
}

class Classifier {
  Classifier({List<DeweyClass>? classes}) : classes = classes ?? defaultClasses {
    for (final c in this.classes) {
      for (final k in c.keywords) {
        final t = TextTools.terms(k);
        if (t.isEmpty) continue;
        final bucket = _index.putIfAbsent(t.join(' '), () => []);
        if (!bucket.contains(c)) bucket.add(c);
      }
    }
  }

  final List<DeweyClass> classes;
  final Map<String, List<DeweyClass>> _index = {};

  /// Scores classes from title (weight 3), subjects/description (2) and body
  /// text (1, capped per term). Returns up to [top] suggestions.
  ClassificationResult classify({
    required String title,
    String description = '',
    List<String> subjects = const [],
    String text = '',
    String? language,
    int top = 3,
  }) {
    final scores = <DeweyClass, double>{};
    final hits = <String, int>{};

    void addFrom(String s, double weight, {int cap = 1 << 30}) {
      final terms = TextTools.terms(s);
      final counts = <String, int>{};
      for (var i = 0; i < terms.length; i++) {
        for (final n in const [2, 1]) {
          if (i + n > terms.length) continue;
          final key = terms.sublist(i, i + n).join(' ');
          if (_index.containsKey(key)) counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      for (final e in counts.entries) {
        final c = e.value > cap ? cap : e.value;
        hits[e.key] = (hits[e.key] ?? 0) + c;
        for (final cls in _index[e.key]!) {
          scores[cls] = (scores[cls] ?? 0) + weight * c * (e.key.contains(' ') ? 1.5 : 1);
        }
      }
    }

    addFrom(title, 3);
    addFrom(subjects.join('. '), 2);
    addFrom(description, 2);
    addFrom(text.length > 60000 ? text.substring(0, 60000) : text, 1, cap: 4);

    // Fiction in English goes to 823 (English fiction) rather than 800.
    final lit = scores.keys.where((c) => c.number == '800').toList();
    if (lit.isNotEmpty && language == 'eng' && (hits.containsKey('novel') || hits.containsKey('fiction'))) {
      final eng = classes.firstWhere((c) => c.number == '823', orElse: () => lit.first);
      scores[eng] = (scores[eng] ?? 0) + scores[lit.first]! + 0.5;
    }

    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = ranked.fold<double>(0, (a, e) => a + e.value);
    final suggestions = [
      for (final e in ranked.take(top))
        ClassSuggestion(e.key.number, e.key.label, total == 0 ? 0 : e.value / total),
    ];

    final subjectTerms = (hits.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((e) => TextTools.titleCase(_surface[e.key] ?? e.key))
        .toList();
    return ClassificationResult(suggestions, subjectTerms);
  }

  late final Map<String, String> _surface = {
    for (final c in classes)
      for (final k in c.keywords) TextTools.terms(k).join(' '): k,
  };

  static const defaultClasses = <DeweyClass>[
    DeweyClass('005', 'Computer programming, programs, data', [
      'programming', 'software', 'algorithm', 'data structures', 'computer', 'code',
      'database', 'flutter', 'python', 'java', 'hash table', 'compiler',
    ]),
    DeweyClass('020', 'Library and information sciences', [
      'library', 'cataloguing', 'cataloging', 'metadata', 'marc', 'dublin core', 'archive',
    ]),
    DeweyClass('150', 'Psychology', ['psychology', 'mind', 'emotion', 'behaviour', 'behavior', 'memory']),
    DeweyClass('170', 'Ethics', ['ethics', 'morality', 'virtue']),
    DeweyClass('200', 'Religion', ['religion', 'god', 'faith', 'prayer', 'church', 'mosque', 'bible', 'quran', 'sermon']),
    DeweyClass('320', 'Political science', ['politics', 'government', 'election', 'parliament', 'democracy', 'constitution']),
    DeweyClass('330', 'Economics', ['economics', 'economy', 'market', 'inflation', 'trade', 'income']),
    DeweyClass('332', 'Financial economics', [
      'bank', 'loan', 'mortgage', 'investment', 'savings', 'interest rate', 'pension', 'insurance', 'statement',
    ]),
    DeweyClass('346', 'Private law (contracts, property)', [
      'lease', 'tenancy', 'tenant', 'landlord', 'rent', 'contract', 'agreement', 'deed',
      'property', 'will', 'title deed', 'notice period',
    ]),
    DeweyClass('336', 'Public finance (taxes)', ['tax', 'taxes', 'revenue authority', 'tax return', 'vat']),
    DeweyClass('363', 'Utilities and public services', ['electricity', 'water bill', 'utility', 'bill', 'invoice', 'receipt']),
    DeweyClass('370', 'Education', [
      'education', 'school', 'lecture', 'course', 'student', 'exam', 'teacher', 'university', 'syllabus', 'transcript',
    ]),
    DeweyClass('392', 'Customs of life cycle and domestic life', [
      'ceremony', 'wedding', 'naming ceremony', 'funeral', 'birthday', 'outdooring', 'marriage', 'family',
    ]),
    DeweyClass('398', 'Folklore', ['folklore', 'folktale', 'proverb', 'legend', 'myth', 'ananse']),
    DeweyClass('400', 'Language', ['grammar', 'vocabulary', 'dictionary', 'language learning', 'pronunciation']),
    DeweyClass('510', 'Mathematics', ['mathematics', 'algebra', 'calculus', 'geometry', 'statistics', 'equation']),
    DeweyClass('530', 'Physics', ['physics', 'energy', 'force', 'quantum', 'motion']),
    DeweyClass('570', 'Biology', ['biology', 'cell', 'gene', 'evolution', 'species', 'ecology']),
    DeweyClass('610', 'Medicine and health', [
      'health', 'medicine', 'medical', 'doctor', 'hospital', 'prescription', 'vaccine', 'diagnosis', 'clinic', 'malaria',
    ]),
    DeweyClass('630', 'Agriculture', ['farm', 'farming', 'crop', 'cocoa', 'harvest', 'livestock', 'soil']),
    DeweyClass('641', 'Food and drink (cooking)', [
      'recipe', 'cooking', 'cook', 'food', 'kitchen', 'jollof', 'soup', 'bake', 'ingredient', 'dish',
    ]),
    DeweyClass('650', 'Management and business', ['business', 'management', 'marketing', 'startup', 'strategy', 'sales']),
    DeweyClass('700', 'Arts', ['art', 'painting', 'design', 'sculpture', 'drawing']),
    DeweyClass('770', 'Photography', ['photograph', 'photo', 'camera', 'portrait']),
    DeweyClass('780', 'Music', ['music', 'song', 'album', 'guitar', 'highlife', 'concert', 'melody']),
    DeweyClass('790', 'Sports and recreation', ['football', 'sport', 'game', 'match', 'athletics', 'recreation']),
    DeweyClass('800', 'Literature', ['novel', 'fiction', 'poetry', 'poem', 'story', 'short stories', 'drama', 'play']),
    DeweyClass('823', 'English fiction', []),
    DeweyClass('910', 'Geography and travel', ['travel', 'geography', 'map', 'journey', 'tourism', 'trip']),
    DeweyClass('960', 'History of Africa', [
      'africa', 'ghana', 'nigeria', 'kenya', 'colonial', 'independence', 'igbo', 'ashanti', 'west africa',
    ]),
    DeweyClass('900', 'History', ['history', 'war', 'empire', 'revolution', 'century']),
  ];
}
