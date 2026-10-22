// Premium looks for share pictures (player card, posters, comparison).
// Every picture is drawn at a fixed size and scaled, so it looks the same on
// every phone and comes out sharp when saved.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/strings.dart';

class StudioTheme {
  const StudioTheme({
    required this.id,
    required this.bg,
    required this.text,
    required this.sub,
    required this.foil,
    required this.glass,
    required this.line,
    required this.beam,
    this.radial = true,
    this.glowA,
    this.glowB,
    this.holo = false,
    this.light = false,
  });
  final String id; // strings key: theme_<id>
  final List<Color> bg; // background gradient, top-right → bottom-left
  final Color text;
  final Color sub;
  final List<Color> foil; // the shiny "gold foil" colours for big numbers
  final Color glass; // panels
  final Color line; // panel borders and rings
  final Color beam; // light beams
  final bool radial;
  final Color? glowA;
  final Color? glowB;
  final bool holo;
  final bool light;

  Color get accent => foil[foil.length ~/ 2];

  /// The same look in a team's colour (keeps the foil and text of the base).
  StudioTheme tinted(Color c) {
    final hsl = HSLColor.fromColor(c);
    Color shade(double l) => hsl.withLightness(l.clamp(0.0, 1.0).toDouble()).withSaturation(math.min(1.0, hsl.saturation * 0.95)).toColor();
    return StudioTheme(
      id: id,
      bg: [shade(0.42), shade(0.24), shade(0.09)],
      text: Colors.white,
      sub: shade(0.84),
      foil: light ? const [Color(0xFFB8862B), Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFFFF3C9), Color(0xFFC9952F)] : foil,
      glass: Colors.white.withValues(alpha: 0.08),
      line: shade(0.78).withValues(alpha: 0.3),
      beam: shade(0.85).withValues(alpha: 0.14),
      radial: radial,
      glowA: glowA,
      glowB: glowB,
      holo: holo,
    );
  }
}

const _gold = [Color(0xFFB8862B), Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFFFF3C9), Color(0xFFC9952F)];

const studioThemes = <StudioTheme>[
  StudioTheme(
    id: 'midnight',
    bg: [Color(0xFF1D3B6E), Color(0xFF0B1730), Color(0xFF050A15)],
    text: Color(0xFFF5F7FB),
    sub: Color(0xFF9FB0C8),
    foil: _gold,
    glass: Color(0x0EFFFFFF),
    line: Color(0x38FFE29A),
    beam: Color(0x29FFD678),
  ),
  StudioTheme(
    id: 'royal',
    bg: [Color(0xFF6D28D9), Color(0xFF3B0F7A), Color(0xFF14052E)],
    text: Color(0xFFFBF7FF),
    sub: Color(0xFFCDB8F5),
    foil: [Color(0xFFC08A2E), Color(0xFFFFEBB0), Color(0xFFF2C14E), Color(0xFFFFF6D8), Color(0xFFB97E22)],
    glass: Color(0x12FFFFFF),
    line: Color(0x40FFEBB0),
    beam: Color(0x2EC4A0FF),
  ),
  StudioTheme(
    id: 'neon',
    bg: [Color(0xFF0B3B4A), Color(0xFF05060B), Color(0xFF05060B)],
    text: Colors.white,
    sub: Color(0xFF8BE9FF),
    foil: [Color(0xFF22D3EE), Color(0xFF67E8F9), Color(0xFFA78BFA), Color(0xFFF0ABFC), Color(0xFFF472B6)],
    glass: Color(0x0F22D3EE),
    line: Color(0x5922D3EE),
    beam: Color(0x33F472B6),
    glowA: Color(0x5922D3EE),
    glowB: Color(0x52F472B6),
  ),
  StudioTheme(
    id: 'emerald',
    bg: [Color(0xFF13724A), Color(0xFF0A3D29), Color(0xFF03170F)],
    text: Color(0xFFF1FFF7),
    sub: Color(0xFFA7D9BF),
    foil: [Color(0xFFB98B2E), Color(0xFFFFE9A8), Color(0xFFEFC24F), Color(0xFFFFF4CE), Color(0xFFB98B2E)],
    glass: Color(0x0FFFFFFF),
    line: Color(0x38FFE9A8),
    beam: Color(0x1FAAFFD2),
  ),
  StudioTheme(
    id: 'sunset',
    bg: [Color(0xFFFF6A3D), Color(0xFFE8326E), Color(0xFF5B1C8C)],
    text: Colors.white,
    sub: Color(0xFFFFE1EC),
    foil: [Colors.white, Color(0xFFFFF1D6), Color(0xFFFFE3B3), Color(0xFFFFF1D6), Colors.white],
    glass: Color(0x24FFFFFF),
    line: Color(0x4DFFFFFF),
    beam: Color(0x2EFFFFFF),
    radial: false,
  ),
  StudioTheme(
    id: 'ivory',
    bg: [Color(0xFFFFFDF6), Color(0xFFF4ECD8), Color(0xFFE9DCBC)],
    text: Color(0xFF16120A),
    sub: Color(0xFF7A6A48),
    foil: [Color(0xFF8A5A12), Color(0xFFD9A441), Color(0xFF7A4E0E), Color(0xFFC8922F), Color(0xFF8A5A12)],
    glass: Color(0x0F785A1E),
    line: Color(0x38785A1E),
    beam: Color(0x1AC9922F),
    light: true,
  ),
  StudioTheme(
    id: 'ocean',
    bg: [Color(0xFF0EA5E9), Color(0xFF0F5E9C), Color(0xFF0B1E4A)],
    text: Color(0xFFF0FAFF),
    sub: Color(0xFFBDE6FF),
    foil: [Color(0xFFE0F7FF), Colors.white, Color(0xFF9EE6FF), Colors.white, Color(0xFFE0F7FF)],
    glass: Color(0x1FFFFFFF),
    line: Color(0x47FFFFFF),
    beam: Color(0x24FFFFFF),
    radial: false,
  ),
  StudioTheme(
    id: 'holo',
    bg: [Color(0xFF1A1B2E), Color(0xFF0B0B12), Color(0xFF0B0B12)],
    text: Colors.white,
    sub: Color(0xFFB9BED6),
    foil: [Color(0xFFFF9AD5), Color(0xFF9AF6FF), Color(0xFFFFF59A), Color(0xFFB39AFF), Color(0xFFFF9AD5)],
    glass: Color(0x0FFFFFFF),
    line: Color(0x4DB9BED6),
    beam: Color(0x249AF6FF),
    holo: true,
  ),
];

StudioTheme themeById(String id) => studioThemes.firstWhere((t) => t.id == id, orElse: () => studioThemes.first);

/// Text in the picture's own language (the picture can be Hindi while the app is English).
String st(String key, String lang, [Map<String, Object> args = const {}]) {
  var s = Strings.get(key, lang);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Shiny foil text (gold, neon or chrome depending on the look).
class FoilText extends StatelessWidget {
  const FoilText(this.text, {super.key, required this.theme, required this.size, this.opacity = 1, this.letterSpacing = 0, this.height = 0.95, this.align});
  final String text;
  final StudioTheme theme;
  final double size;
  final double opacity;
  final double letterSpacing;
  final double height;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          begin: const Alignment(-1, -0.4),
          end: const Alignment(1, 0.4),
          colors: theme.foil,
        ).createShader(r),
        child: Text(
          text,
          maxLines: 1,
          textAlign: align,
          style: TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: size, height: height, letterSpacing: letterSpacing, color: Colors.white),
        ),
      ),
    );
  }
}

/// Big numbers and names in the condensed sports font.
TextStyle studioNum(double size, Color c, {FontWeight w = FontWeight.w800, double height = 0.95, double spacing = 0}) =>
    TextStyle(fontFamily: 'Saira', fontWeight: w, fontSize: size, height: height, color: c, letterSpacing: spacing, fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle studioText(double size, Color c, {FontWeight w = FontWeight.w700, double spacing = 0, double height = 1.25}) =>
    TextStyle(fontFamily: 'Hanken', fontWeight: w, fontSize: size, height: height, color: c, letterSpacing: spacing);

/// Small capital labels ("RUNS", "MATCHES").
TextStyle studioCap(StudioTheme t, {double size = 9.5}) => studioText(size, t.sub, w: FontWeight.w800, spacing: 1.4);

/// Background: gradient, light beams, rings, glows and a little grain.
class StudioBackground extends StatelessWidget {
  const StudioBackground({super.key, required this.theme, required this.child});
  final StudioTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: t.radial
            ? RadialGradient(center: const Alignment(0.6, -1.1), radius: 1.5, colors: t.bg, stops: const [0, 0.45, 1])
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.bg),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (t.glowA != null) Positioned(right: -90, top: -90, width: 320, height: 320, child: _Glow(t.glowA!)),
        if (t.glowB != null) Positioned(left: -100, bottom: -70, width: 320, height: 320, child: _Glow(t.glowB!)),
        if (t.holo)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: SweepGradient(center: const Alignment(0.6, -0.8), colors: [
                const Color(0xFFFF9AD5).withValues(alpha: 0.16),
                const Color(0xFF9AF6FF).withValues(alpha: 0.16),
                const Color(0xFFFFF59A).withValues(alpha: 0.12),
                const Color(0xFFB39AFF).withValues(alpha: 0.16),
                const Color(0xFFFF9AD5).withValues(alpha: 0.16),
              ]),
            ),
          ),
        CustomPaint(painter: _DecorPainter(t)),
        child,
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.c);
  final Color c;
  @override
  Widget build(BuildContext context) =>
      DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)], stops: const [0, 0.65])));
}

class _DecorPainter extends CustomPainter {
  _DecorPainter(this.t);
  final StudioTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // light beams
    for (final (x, bw) in [(0.55, 64.0), (0.72, 24.0), (0.84, 11.0)]) {
      canvas.save();
      canvas.translate(w * x, -100);
      canvas.rotate(22 * math.pi / 180);
      final r = Rect.fromLTWH(0, 0, bw, h + 260);
      canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.beam, t.beam.withValues(alpha: 0)], stops: const [0, 0.7]).createShader(r));
      canvas.restore();
    }
    // rings
    final c = Offset(w + 90, h + 70);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = t.line.withValues(alpha: t.line.a * 0.8);
    canvas.drawCircle(c, 200, ring..strokeWidth = 1.4);
    canvas.drawCircle(c, 150, ring..strokeWidth = 1);
    // grain: tiny dots, same every time
    final rnd = math.Random(7);
    final dot = Paint()..color = (t.light ? Colors.black : Colors.white).withValues(alpha: 0.035);
    for (var i = 0; i < 900; i++) {
      canvas.drawCircle(Offset(rnd.nextDouble() * w, rnd.nextDouble() * h), 0.6, dot);
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) => old.t != t;
}

/// A rounded "glass" box.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.theme, required this.child, this.padding = const EdgeInsets.all(12), this.radius = 16});
  final StudioTheme theme;
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: theme.glass, borderRadius: BorderRadius.circular(radius), border: Border.all(color: theme.line)),
        child: child,
      );
}

/// GullyScore name and logo for the top of pictures.
class StudioBrand extends StatelessWidget {
  const StudioBrand({super.key, required this.theme});
  final StudioTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: const Color(0xFFFFC94A), borderRadius: BorderRadius.circular(7)),
        child: CustomPaint(painter: _StumpsPainter()),
      ),
      const SizedBox(width: 7),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('GullyScore', style: studioText(13.5, theme.text, w: FontWeight.w800, height: 1.1)),
        Text('GULLY SE GROUND TAK', style: studioText(7.5, theme.sub, w: FontWeight.w800, spacing: 0.8, height: 1.2)),
      ]),
    ]);
  }
}

class _StumpsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xFF0B1220);
    final u = s.width / 48;
    for (final x in [13.0, 22.0, 31.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * u, 12 * u, 4 * u, 22 * u), Radius.circular(1.5 * u)), p);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(11 * u, 10 * u, 26 * u, 3.5 * u), Radius.circular(1.5 * u)), p);
    canvas.drawCircle(Offset(36 * u, 37 * u), 4 * u, Paint()..color = const Color(0xFFE23B3B));
  }

  @override
  bool shouldRepaint(_StumpsPainter old) => false;
}

/// Picture sizes. All are drawn 360 points wide.
enum StudioSize { post, story, square, wide }

extension StudioSizeX on StudioSize {
  double get height => switch (this) { StudioSize.post => 450.0, StudioSize.story => 640.0, StudioSize.square => 360.0, StudioSize.wide => 256.0 };
  String get key => switch (this) { StudioSize.post => 'size_post', StudioSize.story => 'size_story', StudioSize.square => 'size_square', StudioSize.wide => 'size_wide' };
}
