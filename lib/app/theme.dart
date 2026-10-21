// Design tokens: colours, type, spacing, corners and motion.
// Every screen takes its look from here, so light and dark stay in step.
import 'package:flutter/material.dart';

class Palette {
  const Palette({
    required this.bg,
    required this.top,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.text2,
    required this.gold,
    required this.goldText,
    required this.live,
    required this.liveText,
    required this.win,
    required this.six,
    required this.nav,
    required this.hero1,
    required this.hero2,
    required this.heroLine,
    required this.dark,
  });

  final Color bg, top, surface, raised, line, text, text2;
  final Color gold, goldText, live, liveText, win, six, nav;
  final Color hero1, hero2, heroLine;
  final bool dark;

  static const darkP = Palette(
    bg: Color(0xFF070F1E),
    top: Color(0xFF0B1628),
    surface: Color(0xFF0E1B30),
    raised: Color(0xFF142540),
    line: Color(0xFF1C2D47),
    text: Color(0xFFF2F5FA),
    text2: Color(0xFFA9B6C9),
    gold: Color(0xFFFFC94A),
    goldText: Color(0xFFFFC94A),
    live: Color(0xFFFF4D4D),
    liveText: Color(0xFFFF8080),
    win: Color(0xFF2BD38A),
    six: Color(0xFFFF8A3D),
    nav: Color(0xFF09142A),
    hero1: Color(0xFF17325A),
    hero2: Color(0xFF0E1B30),
    heroLine: Color(0xFF234071),
    dark: true,
  );

  static const lightP = Palette(
    bg: Color(0xFFF4F6FA),
    top: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEDF1F7),
    line: Color(0xFFE3E8F0),
    text: Color(0xFF0B1220),
    text2: Color(0xFF5A6678),
    gold: Color(0xFFFFC94A),
    goldText: Color(0xFF9A6400),
    live: Color(0xFFD92D2D),
    liveText: Color(0xFFD92D2D),
    win: Color(0xFF1D8A5A),
    six: Color(0xFFC2410C),
    nav: Color(0xFFFFFFFF),
    hero1: Color(0xFFFFFFFF),
    hero2: Color(0xFFFFFFFF),
    heroLine: Color(0xFFE3E8F0),
    dark: false,
  );

  /// Team colours for crests.
  static const teamColors = [
    Color(0xFFF97316),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFFA855F7),
    Color(0xFFEF4444),
    Color(0xFFE879F9),
    Color(0xFF14B8A6),
    Color(0xFF64748B),
  ];

  static Color team(int i) => teamColors[i % teamColors.length];

  static Palette of(BuildContext context) => Theme.of(context).extension<PaletteExt>()!.p;
}

class PaletteExt extends ThemeExtension<PaletteExt> {
  const PaletteExt(this.p);
  final Palette p;

  @override
  PaletteExt copyWith({Palette? p}) => PaletteExt(p ?? this.p);

  @override
  PaletteExt lerp(covariant ThemeExtension<PaletteExt>? other, double t) {
    if (other is! PaletteExt) return this;
    final o = other.p;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PaletteExt(Palette(
      bg: l(p.bg, o.bg),
      top: l(p.top, o.top),
      surface: l(p.surface, o.surface),
      raised: l(p.raised, o.raised),
      line: l(p.line, o.line),
      text: l(p.text, o.text),
      text2: l(p.text2, o.text2),
      gold: l(p.gold, o.gold),
      goldText: l(p.goldText, o.goldText),
      live: l(p.live, o.live),
      liveText: l(p.liveText, o.liveText),
      win: l(p.win, o.win),
      six: l(p.six, o.six),
      nav: l(p.nav, o.nav),
      hero1: l(p.hero1, o.hero1),
      hero2: l(p.hero2, o.hero2),
      heroLine: l(p.heroLine, o.heroLine),
      dark: t < 0.5 ? p.dark : o.dark,
    ));
  }
}

/// Corner sizes: only four in the whole app.
class Corners {
  static const chip = 10.0;
  static const button = 14.0;
  static const card = 18.0;
  static const hero = 24.0;
}

/// Spacing on a 4-point grid.
class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const edge = 16.0;
}

/// Motion durations and curves. With reduced motion, use [Motion.of].
class Motion {
  static const press = Duration(milliseconds: 100);
  static const fade = Duration(milliseconds: 180);
  static const page = Duration(milliseconds: 280);
  static const score = Duration(milliseconds: 220);
  static const pulse = Duration(milliseconds: 1600);
  static const four = Duration(milliseconds: 900);
  static const six = Duration(milliseconds: 1400);
  static const wicket = Duration(milliseconds: 1100);
  static const reduced = Duration(milliseconds: 150);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.easeInOutCubic;
}

/// Text styles. Numbers use Saira with fixed-width digits.
class Tx {
  static const _num = [FontFeature.tabularFigures()];

  static TextStyle score(double size, Color c, {FontWeight w = FontWeight.w900}) =>
      TextStyle(fontFamily: 'Saira', fontSize: size, fontWeight: w, color: c, height: 1.0, fontFeatures: _num);

  static TextStyle title(Color c) => TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c, height: 1.2);
  static TextStyle section(Color c) => TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c, height: 1.25);
  static TextStyle body(Color c, {FontWeight w = FontWeight.w500}) =>
      TextStyle(fontSize: 15, fontWeight: w, color: c, height: 1.45, fontFeatures: _num);
  static TextStyle small(Color c, {FontWeight w = FontWeight.w600}) =>
      TextStyle(fontSize: 13, fontWeight: w, color: c, height: 1.4, fontFeatures: _num);
  static TextStyle label(Color c, {FontWeight w = FontWeight.w700}) =>
      TextStyle(fontSize: 12, fontWeight: w, color: c, height: 1.3, fontFeatures: _num);
}

ThemeData buildTheme(Palette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Hanken',
    fontFamilyFallback: const ['NotoDeva'],
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme(
      brightness: p.dark ? Brightness.dark : Brightness.light,
      primary: p.gold,
      onPrimary: const Color(0xFF0B1220),
      secondary: p.gold,
      onSecondary: const Color(0xFF0B1220),
      error: p.live,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
    ),
    extensions: [PaletteExt(p)],
  );
  return base.copyWith(
    splashFactory: InkSparkle.splashFactory,
    dividerColor: p.line,
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: 'Hanken', fontFamilyFallback: const ['NotoDeva']),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corners.hero))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.card)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.button), borderSide: BorderSide(color: p.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.button), borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.button), borderSide: BorderSide(color: p.gold, width: 1.5)),
      hintStyle: TextStyle(color: p.text2),
      labelStyle: TextStyle(color: p.text2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.raised,
      contentTextStyle: TextStyle(color: p.text, fontFamily: 'Hanken', fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.button)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF0B1220) : p.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.gold : p.raised),
      trackOutlineColor: WidgetStateProperty.all(p.line),
    ),
  );
}
