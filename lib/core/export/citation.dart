/// ISO 690 bibliographic references (author–title style).
///
/// Pattern used: CREATOR(S). Title [medium]. Publisher, Year. Identifier.
/// Surnames are upper-cased, a common ISO 690 presentation. Up to three
/// creators are listed; more become "et al.".
library;

import '../record.dart';
import 'marc21.dart';

class Iso690 {
  Iso690._();

  static String _creator(String name) {
    if (Marc21.isOrganisation(name)) return name;
    final inverted = Marc21.invertName(name);
    final comma = inverted.indexOf(',');
    if (comma < 0) return inverted.toUpperCase();
    return '${inverted.substring(0, comma).toUpperCase()}${inverted.substring(comma)}';
  }

  static String _medium(CatalogueRecord r) {
    final format = r.text(Dc.format).toLowerCase();
    return switch (r.mediaType) {
      MediaType.book => format.contains('epub') ? '[e-book]' : '[online]',
      MediaType.document => format.contains('pdf') ? '[PDF]' : '[online]',
      MediaType.image => '[photograph]',
      MediaType.video => '[video recording]',
      MediaType.audio => '[audio recording]',
      MediaType.other => '[online]',
    };
  }

  static String _end(String s) => s.endsWith('.') || s.endsWith('?') || s.endsWith('!') ? s : '$s.';

  static String reference(CatalogueRecord r) {
    final parts = <String>[];
    final creators = r.texts(Dc.creator);
    if (creators.isNotEmpty) {
      final names = creators.take(3).map(_creator).toList();
      var who = names.length == 1
          ? names.first
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
      if (creators.length > 3) who = '${names.first} et al';
      parts.add(_end(who));
    }
    parts.add(_end('${r.title} ${_medium(r)}'));
    final publisher = r.text(Dc.publisher);
    final year = RegExp(r'^\d{4}').firstMatch(r.text(Dc.date))?.group(0) ?? r.text(Dc.date);
    final pubLine = [if (publisher.isNotEmpty) publisher, if (year.isNotEmpty) year].join(', ');
    if (pubLine.isNotEmpty) parts.add(_end(pubLine));
    final id = r.texts(Dc.identifier).firstWhere(
          (i) => i.startsWith('ISBN') || i.toLowerCase().startsWith('doi:'),
          orElse: () => '',
        );
    if (id.isNotEmpty) parts.add(_end(id.toLowerCase().startsWith('doi:') ? 'DOI ${id.substring(4)}' : id));
    return parts.join(' ');
  }
}
