import 'package:flutter_test/flutter_test.dart';
import 'package:ipes/core/isbn.dart';
import 'package:ipes/core/text.dart';

void main() {
  group('ISBN (ISO 2108)', () {
    test('validates ISBN-10 and ISBN-13 check digits', () {
      expect(Isbn.isValid('0-306-40615-2'), isTrue);
      expect(Isbn.isValid('0-306-40615-3'), isFalse);
      expect(Isbn.isValid('978-0-306-40615-7'), isTrue);
      expect(Isbn.isValid('9780306406158'), isFalse);
      expect(Isbn.isValid('ISBN 978-9988-01234-2'), isTrue);
      expect(Isbn.isValid('080442957X'), isTrue);
    });

    test('converts ISBN-10 to ISBN-13', () {
      expect(Isbn.toIsbn13('0306406152'), '9780306406157');
      expect(Isbn.toIsbn13('0306406153'), isNull);
    });

    test('finds ISBNs in free text, de-duplicated, as ISBN-13', () {
      const text = 'First printing. ISBN 0-306-40615-2. Also 978-0-306-40615-7 and 1234567890.';
      expect(Isbn.findAll(text), ['9780306406157']);
    });
  });

  group('Text tools', () {
    test('stems plurals and verb forms', () {
      expect(TextTools.stem('leases'), 'lease');
      expect(TextTools.stem('stories'), 'story');
      expect(TextTools.stem('cooking'), 'cook');
      expect(TextTools.stem('planned'), 'plan');
      expect(TextTools.stem('class'), 'class');
    });

    test('drops stop words', () {
      expect(TextTools.terms('What does my lease say about the notice?'), ['lease', 'notice']);
    });

    test('guesses English and French', () {
      const en = 'The tenant and the landlord agree that the rent is paid in advance for each month of the year, '
          'and that this agreement is valid for two years with notice to the other party.';
      const fr = "La réunion a eu lieu à l'école et les parents ont discuté des frais de transport, de la cantine "
          'et de la fête de fin d année. Le bureau va écrire au directeur pour une date et pour les enfants.';
      expect(TextTools.guessLanguage(en)?.code, 'eng');
      expect(TextTools.guessLanguage(fr)?.code, 'fre');
      expect(TextTools.guessLanguage('Too short'), isNull);
    });
  });
}
