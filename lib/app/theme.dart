/// Visual language from the design canvas: navy ink, marigold accent,
/// tinted media tiles, monospace call numbers.
library;

import 'package:flutter/material.dart';

import '../core/record.dart';

class IpesColors {
  IpesColors._();
  static const ink = Color(0xFF10233F);
  static const inkSoft = Color(0xFF1F3A60);
  static const muted = Color(0xFF4A5872);
  static const accent = Color(0xFFF2B230);
  static const ground = Color(0xFFF5F6F8);
  static const line = Color(0xFFE3E7EE);
  static const warn = Color(0xFFFFF1CC);
  static const warnInk = Color(0xFF8A5A00);
  static const good = Color(0xFF2E6B4F);

  static Color tint(MediaType t) => switch (t) {
        MediaType.book => const Color(0xFFFCE7B2),
        MediaType.document => const Color(0xFFDCE6F5),
        MediaType.image => const Color(0xFFD8F0EC),
        MediaType.video => const Color(0xFFD8F0EC),
        MediaType.audio => const Color(0xFFF6DED6),
        MediaType.other => const Color(0xFFE2E8F3),
      };

  static Color source(FieldSource s) => switch (s) {
        FieldSource.embedded || FieldSource.lookup => const Color(0xFFD8F0EC),
        FieldSource.user => const Color(0xFFE2E8F3),
        FieldSource.ai || FieldSource.rules => const Color(0xFFFCE7B2),
        FieldSource.content || FieldSource.filename => const Color(0xFFDCE6F5),
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: IpesColors.ink,
    primary: IpesColors.ink,
    secondary: IpesColors.accent,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: IpesColors.ground,
    appBarTheme: const AppBarTheme(
      backgroundColor: IpesColors.ground,
      foregroundColor: IpesColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: IpesColors.line),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: IpesColors.accent,
      foregroundColor: IpesColors.ink,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFFCE7B2),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: IpesColors.ink,
      selectedIconTheme: IconThemeData(color: IpesColors.ink),
      unselectedIconTheme: IconThemeData(color: Color(0xFFC9D3E3)),
      selectedLabelTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: Color(0xFFC9D3E3)),
      indicatorColor: IpesColors.accent,
    ),
  );
}

const monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: IpesColors.muted);

/// Coloured tile showing the file kind, as on the canvas.
class MediaTile extends StatelessWidget {
  const MediaTile(this.record, {super.key, this.width = 44, this.height = 56});
  final CatalogueRecord record;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ext = record.fileName.contains('.')
        ? record.fileName.substring(record.fileName.lastIndexOf('.') + 1).toUpperCase()
        : record.mediaType.label.toUpperCase();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: IpesColors.tint(record.mediaType), borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(4),
      // Scale the label down rather than wrapping it at large text sizes.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(ext.length > 4 ? ext.substring(0, 4) : ext,
            maxLines: 1, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: IpesColors.ink)),
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.value, {super.key});
  final FieldValue value;

  @override
  Widget build(BuildContext context) {
    final label = value.source == FieldSource.user
        ? 'You'
        : '${value.source.label} ${value.confidence.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: IpesColors.source(value.source), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: IpesColors.ink)),
    );
  }
}

class CallNumber extends StatelessWidget {
  const CallNumber(this.number, {super.key});
  final String number;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: IpesColors.ink, borderRadius: BorderRadius.circular(6)),
        child: Text(number, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white)),
      );
}

String languageName(String code) => const {
      'eng': 'English',
      'fre': 'French',
      'spa': 'Spanish',
      'ger': 'German',
      'por': 'Portuguese',
      'twi': 'Twi',
      'aka': 'Akan',
      'ewe': 'Ewe',
      'hau': 'Hausa',
      'yor': 'Yoruba',
      'swa': 'Swahili',
    }[code] ??
    code;
