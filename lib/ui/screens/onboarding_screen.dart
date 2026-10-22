// First launch: five animated scenes (score, live, grounds, player card, logo).
// Every scene plays once; Next or Skip moves on. With "Reduce motion" on, the
// scenes appear finished, without movement.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/scope.dart';

const _gold = [Color(0xFFB8862B), Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFFFF3C9), Color(0xFFC9952F)];

double _iv(double t, double a, double b, [Curve c = Curves.easeOutCubic]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Fades in from a blur, rising a little.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.t, required this.at, required this.child, this.dy = 14});
  final double t;
  final double at;
  final double dur;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final v = _iv(t, at, at + dur);
    if (v >= 1) return child;
    final blur = (1 - v) * 8;
    return Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, (1 - v) * dy),
        child: blur < 0.3 ? child : ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: child),
      ),
    );
  }
}

class _Gold extends StatelessWidget {
  const _Gold(this.text, {required this.style, this.shift = 0});
  final String text;
  final TextStyle style;
  final double shift; // moves the shine
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1 + shift * 2, -0.3),
          end: Alignment(1 + shift * 2, 0.3),
          colors: _gold,
          tileMode: TileMode.mirror,
        ).createShader(r),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
}

TextStyle _display(double size) => TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: size, height: 1.02, fontFamilyFallback: const ['NotoDeva'], color: Colors.white, letterSpacing: -0.3);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  int _i = 0;
  bool _calm = false;
  static const _count = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = context.reduceMotion;
    if (calm != _calm || (!_c.isAnimating && _c.value == 0)) {
      _calm = calm;
      _play();
    }
  }

  void _play() {
    if (_calm) {
      _c.value = 1;
      _loop.stop();
    } else {
      _c.forward(from: 0);
      if (!_loop.isAnimating) _loop.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _done() {
    context.settings.setOnboarded();
    widget.onDone();
  }

  void _next() {
    if (_i >= _count - 1) return _done();
    setState(() => _i++);
    _play();
  }

  static const _bg = [
    [Color(0xFF3A0B4F), Color(0xFF14061F)],
    [Color(0xFF0B3B6E), Color(0xFF06142A)],
    [Color(0xFF0F5B3A), Color(0xFF05261A)],
    [Color(0xFF4C1D95), Color(0xFF1A0835)],
    [Color(0xFF4A3206), Color(0xFF160F03)],
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final last = _i == _count - 1;
    return Scaffold(
      backgroundColor: const Color(0xFF03060D),
      body: AnimatedBuilder(
        animation: Listenable.merge([_c, _loop]),
        builder: (context, _) {
          final t = _c.value;
          final l = _loop.value;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -1.1), radius: 1.5, colors: [..._bg[_i], const Color(0xFF03060D)], stops: const [0, 0.45, 0.85]),
            ),
            child: SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth, h = box.maxHeight;
                return Stack(children: [
                  // the scene's picture (top part)
                  Positioned(left: 0, right: 0, top: 50, height: math.max(220, h * 0.5), child: _art(t, l, w, math.max(220, h * 0.5))),
                  // top bar: progress, brand, language, skip
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 8,
                    child: Column(children: [
                      Row(children: [
                        for (var k = 0; k < _count; k++) ...[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: Colors.white.withValues(alpha: 0.18)),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: k < _i ? 1 : (k == _i ? t : 0),
                                child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: Colors.white)),
                              ),
                            ),
                          ),
                          if (k < _count - 1) const SizedBox(width: 5),
                        ],
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        const _Brand(),
                        const Spacer(),
                        _LangSwitch(lang: s.lang, onChanged: s.setLang),
                        if (!last) ...[
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: _done,
                            style: TextButton.styleFrom(foregroundColor: Colors.white70, minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
                            child: Text(context.tr('skip'), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ]),
                    ]),
                  ),
                  // words
                  Positioned(left: 22, right: 22, bottom: 96, child: _words(context, t)),
                  // button
                  Positioned(left: 18, right: 18, bottom: 18, child: _GoldButton(label: context.tr(last ? 'get_started' : 'next'), shine: l, onTap: _next)),
                ]);
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _words(BuildContext context, double t) {
    final k = ['score', 'live', 'grounds', 'card', 'start'][_i];
    if (_i == 4) {
      return Column(children: [
        _Reveal(t: t, at: 0.42, child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [Text('GULLY', style: _display(56)), _Gold('SCORE', style: _display(56), shift: _loop.value)]))),
        const SizedBox(height: 8),
        _Reveal(t: t, at: 0.55, child: Text(context.tr('intro_tagline'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2.5, fontSize: 13))),
        const SizedBox(height: 40),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _Reveal(
        t: t,
        at: 0.06,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: Colors.white24)),
          child: Text(context.tr('intro_${k}_kicker'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 1.6)),
        ),
      ),
      const SizedBox(height: 10),
      _Reveal(t: t, at: 0.1, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(context.tr('intro_${k}_a').toUpperCase(), style: _display(46)))),
      _Reveal(
        t: t,
        at: 0.16,
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _Gold(context.tr('intro_${k}_b').toUpperCase(), style: _display(46), shift: _loop.value)),
      ),
      const SizedBox(height: 10),
      _Reveal(t: t, at: 0.24, child: Text(context.tr('intro_${k}_body'), style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500))),
    ]);
  }

  Widget _art(double t, double l, double w, double h) {
    switch (_i) {
      case 0:
        return _ScoreArt(t: t, l: l, calm: _calm);
      case 1:
        return _LiveArt(t: t, l: l, calm: _calm);
      case 2:
        return _MapArt(t: t, l: l, calm: _calm);
      case 3:
        return _CardArt(t: t, l: l, calm: _calm);
      default:
        return _LogoArt(t: t, l: l, calm: _calm);
    }
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Color(0xFFFFE7A3), Color(0xFFF4C247)])),
          child: const Icon(Icons.sports_cricket_rounded, size: 17, color: Color(0xFF0B1220)),
        ),
        const SizedBox(width: 7),
        const Text('GullyScore', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
      ]);
}

class _LangSwitch extends StatelessWidget {
  const _LangSwitch({required this.lang, required this.onChanged});
  final String lang;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget opt(String code, String label) => Semantics(
          button: true,
          selected: lang == code,
          child: GestureDetector(
            onTap: () => onChanged(code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: lang == code ? const Color(0xFFF4C247) : Colors.transparent),
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: lang == code ? const Color(0xFF0B1220) : Colors.white70)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opt('en', 'EN'), opt('hi', 'हिंदी')]),
    );
  }
}

/// Gold button with a light sweeping across it.
class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap, required this.shine});
  final String label;
  final VoidCallback onTap;
  final double shine;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFFF4C247), Color(0xFFFFE7A3), Color(0xFFF4C247)]),
              boxShadow: const [BoxShadow(color: Color(0x59F4C247), blurRadius: 24, offset: Offset(0, 10))],
            ),
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: FractionalTranslation(
                  translation: Offset(-1.2 + (shine * 1.6 % 1.6) * 2, 0),
                  child: Transform(
                    transform: Matrix4.skewX(-0.35),
                    child: Container(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0xAAFFFFFF), Color(0x00FFFFFF)], stops: [0.4, 0.5, 0.6])),
                    ),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0B1220), fontWeight: FontWeight.w800, fontSize: 16.5))),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Color(0xFF0B1220), size: 20),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------- scene 1: score + SIX

class _ScoreArt extends StatelessWidget {
  const _ScoreArt({required this.t, required this.l, required this.calm});
  final double t, l;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final runs = t < 0.2 ? 128 : (t < 0.62 ? 129 : 135);
    final balls = t < 0.2 ? '16.2' : (t < 0.62 ? '16.3' : '16.4');
    final bt = _iv(t, 0.3, 0.62, Curves.easeInOut);
    final slam = _iv(t, 0.6, 0.78, Curves.elasticOut);
    final wave = _iv(t, 0.6, 0.9);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final swing = calm ? 0.0 : math.sin(l * math.pi * 2) * 0.12;
      // ball path: from the pitch, high up, out of the ground
      final bx = w * 0.5 + bt * w * 0.32;
      final by = h * 0.95 - math.sin(bt * math.pi) * h * 0.75 - bt * h * 0.2;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: _BeamsPainter(swing))),
        Positioned(left: 0, right: 0, bottom: 0, height: h * 0.35, child: CustomPaint(painter: _PitchPainter())),
        Positioned(
          left: 20,
          right: 20,
          top: 10,
          child: _Reveal(
            t: t,
            at: 0.02,
            dy: 40,
            child: _Glass(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(context.tr('intro_score_card'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4))),
                  const Text('● LIVE', style: TextStyle(color: Color(0xFFFF8080), fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (c, a) => SlideTransition(position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: FadeTransition(opacity: a, child: c)),
                    child: Text('$runs', key: ValueKey(runs), style: _display(54)),
                  ),
                  Text('/3', style: _display(54).copyWith(color: Colors.white54)),
                  const Spacer(),
                  Text(balls, style: _display(24)),
                ]),
              ]),
            ),
          ),
        ),
        if (bt > 0 && bt < 1)
          Positioned(
            left: bx - 11,
            top: by - 11,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFB0B0), Color(0xFFE0202C), Color(0xFF6A0710)]),
                boxShadow: [BoxShadow(color: Color(0xCCFF5050), blurRadius: 18)],
              ),
            ),
          ),
        if (wave > 0 && wave < 1)
          Positioned(
            left: w / 2 - 150 * wave,
            top: h * 0.55 - 150 * wave,
            child: Opacity(
              opacity: 1 - wave,
              child: Container(width: 300 * wave, height: 300 * wave, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFE7A3), width: 3))),
            ),
          ),
        if (slam > 0)
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.4,
            child: Opacity(
              opacity: slam.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 2.4 - 1.4 * slam,
                child: Center(child: _Gold(context.tr('six').toUpperCase(), style: _display(96), shift: l)),
              ),
            ),
          ),
      ]);
    });
  }
}

class _BeamsPainter extends CustomPainter {
  _BeamsPainter(this.swing);
  final double swing;
  @override
  void paint(Canvas canvas, Size s) {
    for (final (x, dir) in [(s.width * 0.08, -1.0), (s.width * 0.92, 1.0)]) {
      canvas.save();
      canvas.translate(x, -40);
      canvas.rotate(dir * (0.38 + swing));
      final r = Rect.fromLTWH(-45, 0, 90, s.height * 1.2);
      canvas.drawRect(
          r,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80FFECAA), Color(0x00FFECAA)]).createShader(r)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.restore();
      canvas.drawCircle(Offset(x, -30), 26, Paint()..color = const Color(0xCCFFF6D8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    final rnd = math.Random(3);
    for (var i = 0; i < 70; i++) {
      canvas.drawCircle(Offset(rnd.nextDouble() * s.width, s.height * (0.48 + rnd.nextDouble() * 0.16)), 1.2,
          Paint()..color = const Color(0xFFFFE7A3).withValues(alpha: 0.2 + rnd.nextDouble() * 0.6));
    }
  }

  @override
  bool shouldRepaint(_BeamsPainter old) => old.swing != swing;
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(-s.width * 0.3, 0, s.width * 1.6, s.height * 2);
    canvas.drawOval(r, Paint()..shader = const RadialGradient(colors: [Color(0xFF1E8C4A), Color(0xFF0D4B28), Color(0x000D4B28)], stops: [0, 0.5, 1]).createShader(r));
    final strip = Path()
      ..moveTo(s.width * 0.46, 0)
      ..lineTo(s.width * 0.54, 0)
      ..lineTo(s.width * 0.6, s.height)
      ..lineTo(s.width * 0.4, s.height)
      ..close();
    canvas.drawPath(strip, Paint()..color = const Color(0x55C9B27C));
  }

  @override
  bool shouldRepaint(_PitchPainter old) => false;
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0.04)]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: child,
      );
}

// ---------------------------------------------------------------- scene 2: live

class _LiveArt extends StatelessWidget {
  const _LiveArt({required this.t, required this.l, required this.calm});
  final double t, l;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final rise = _iv(t, 0.0, 0.3, Curves.easeOutCubic);
    final float = calm ? 0.0 : math.sin(l * math.pi * 2) * 6;
    Widget toast(String emoji, Color c, String title, String sub, double at, double right) {
      final v = _iv(t, at, at + 0.2, Curves.easeOutBack);
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset((1 - v) * 120, 0),
          child: Padding(
            padding: EdgeInsets.only(right: right, bottom: 8),
            child: _Glass(
              padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)), child: Text(emoji, style: const TextStyle(fontSize: 16))),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600, fontSize: 10.5)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 10 + (1 - rise) * 60 + float,
          child: Center(
            child: Opacity(
              opacity: rise,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(0.16 * (1 - rise) + 0.12)
                  ..rotateY(-0.14),
                child: Container(
                  width: 200,
                  height: math.min(h * 0.92, 340),
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1222),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF1B2740), width: 5),
                    boxShadow: const [BoxShadow(color: Color(0x993B82F6), blurRadius: 60), BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 30))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFF3B5C), borderRadius: BorderRadius.circular(99)),
                        child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFF17325A), Color(0xFF0E1B30)])),
                      child: Column(children: [
                        Row(children: [
                          const _MiniCrest('MS', Color(0xFFF97316)),
                          const SizedBox(width: 6),
                          const Expanded(child: Text('Madhubani', maxLines: 1, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))),
                          Text('134/3', style: _display(20)),
                        ]),
                        const SizedBox(height: 6),
                        const Row(children: [
                          _MiniCrest('JW', Color(0xFFA855F7)),
                          SizedBox(width: 6),
                          Expanded(child: Text('Jhanjharpur', maxLines: 1, style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 11))),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: CustomPaint(painter: _LinePainter(_iv(t, 0.15, 0.7)))),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 30,
          width: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            toast('💥', const Color(0xFFA855F7), context.tr('intro_live_t1'), 'Madhubani 134/3 · 16.3', 0.25, 0),
            toast('🎯', const Color(0xFFFF4D4D), context.tr('intro_live_t2'), 'c Amit b Vikas', 0.38, 24),
            toast('🏆', const Color(0xFF2BD38A), context.tr('intro_live_t3'), 'Player of the Match: Suraj', 0.51, 6),
          ]),
        ),
        Positioned(
          left: 16,
          bottom: 4,
          child: Transform.scale(
            scale: _iv(t, 0.62, 0.8, Curves.elasticOut),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0x24FFC94A), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x66FFC94A))),
              child: Text('👀 ${context.tr('intro_live_watching')}', style: const TextStyle(color: Color(0xFFFFE7A3), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
        ),
      ]);
    });
  }
}

class _MiniCrest extends StatelessWidget {
  const _MiniCrest(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.v);
  final double v;
  @override
  void paint(Canvas canvas, Size s) {
    const pts = [0.75, 0.68, 0.72, 0.55, 0.6, 0.42, 0.47, 0.3, 0.35, 0.15, 0.2];
    final path = Path();
    final n = (pts.length - 1) * v;
    for (var i = 0; i <= n.floor(); i++) {
      final o = Offset(s.width * i / (pts.length - 1), s.height * pts[i]);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF2BD38A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.v != v;
}

// ---------------------------------------------------------------- scene 3: grounds map

class _MapArt extends StatelessWidget {
  const _MapArt({required this.t, required this.l, required this.calm});
  final double t, l;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final tilt = _iv(t, 0, 0.35, Curves.easeOutCubic);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final pins = [(0.22, 0.2, 'Rajnagar', 0.18), (0.75, 0.16, 'Sakri', 0.26), (0.32, 0.46, 'Pandaul', 0.34), (0.78, 0.44, 'Madhubani', 0.42), (0.55, 0.08, '', 0.5)];
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: w * 0.08,
          right: w * 0.08,
          top: 0,
          height: h * 0.62,
          child: Opacity(
            opacity: tilt,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0014)
                ..rotateX(0.9 - 0.15 * tilt)
                ..rotateZ(-0.25 + 0.1 * tilt),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  gradient: const RadialGradient(colors: [Color(0xFF1C8C55), Color(0xFF0B4A2D), Color(0xFF062A1A)]),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 30))],
                ),
                child: CustomPaint(painter: _MapPainter(calm ? 0.5 : l)),
              ),
            ),
          ),
        ),
        for (final (x, y, name, at) in pins)
          Positioned(
            left: w * x - 14,
            top: h * y,
            child: Opacity(
              opacity: _iv(t, at, at + 0.1),
              child: Transform.translate(
                offset: Offset(0, -80 * (1 - _iv(t, at, at + 0.16, Curves.bounceOut))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (name.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0x66FFE7A3))),
                      child: Text(name, style: const TextStyle(color: Color(0xFFFFE7A3), fontSize: 8.5, fontWeight: FontWeight.w800)),
                    ),
                  const Icon(Icons.location_on_rounded, color: Color(0xFFF4C247), size: 30, shadows: [Shadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4))]),
                ]),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(left: 22),
            children: [
              for (final (i, g) in [('Rajnagar Stadium', '★ 4.4 · Turf · 1.2 km', '₹1,500'), ('Sakri High School', '★ 4.1 · Matting', 'FREE')].indexed)
                _Reveal(
                  t: t,
                  at: 0.5 + i * 0.08,
                  dy: 40,
                  child: Container(
                    width: 210,
                    margin: const EdgeInsets.only(right: 10),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Colors.white.withValues(alpha: 0.07), border: Border.all(color: Colors.white24)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(
                        height: 40,
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9FB8CF), Color(0xFFE8D6B8), Color(0xFF5F8F3A), Color(0xFF2F5A1F)], stops: [0, 0.4, 0.42, 1])),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(g.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                              Text(g.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, fontSize: 10)),
                            ]),
                          ),
                          _Gold(g.$3, style: _display(15)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ]);
    });
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.pulse);
  final double pulse;
  @override
  void paint(Canvas canvas, Size s) {
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawPath(Path()..moveTo(0, s.height * 0.25)..quadraticBezierTo(s.width * 0.4, s.height * 0.15, s.width, s.height * 0.4), road);
    canvas.drawPath(Path()..moveTo(s.width * 0.15, s.height)..quadraticBezierTo(s.width * 0.3, s.height * 0.5, s.width * 0.9, 0), road);
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, s.shortestSide * 0.22, road);
    canvas.drawCircle(c, s.shortestSide * 0.42, road..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawCircle(c, 30 * pulse, Paint()..color = const Color(0xFF5B9BFF).withValues(alpha: 0.5 * (1 - pulse)));
    canvas.drawCircle(c, 9, Paint()..color = Colors.white);
    canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF5B9BFF));
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.pulse != pulse;
}

// ---------------------------------------------------------------- scene 4: holo card

class _CardArt extends StatelessWidget {
  const _CardArt({required this.t, required this.l, required this.calm});
  final double t, l;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final flip = _iv(t, 0, 0.38, Curves.easeOutBack);
    final c = _iv(t, 0.3, 0.75);
    final wobble = calm ? 0.0 : math.sin(l * math.pi * 2) * 0.12;
    String n(double v, int dec) => v.toStringAsFixed(dec).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    Widget stat(String v, String k, {double size = 16}) => Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: const Color(0x40FFEBB0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _display(size))),
            Text(k, maxLines: 1, style: const TextStyle(color: Color(0xFFE5D4FF), fontSize: 6.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ]),
        );
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final cardH = math.min(h * 0.86, 300.0);
      return Stack(clipBehavior: Clip.none, children: [
        if (!calm) Positioned.fill(child: CustomPaint(painter: _ConfettiPainter(_iv(t, 0.4, 1, Curves.linear)))),
        Positioned(
          left: 0,
          right: 0,
          top: 4,
          child: Center(
            child: Opacity(
              opacity: _iv(t, 0, 0.15),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(-1.9 * (1 - flip) + wobble)
                  ..rotateX(0.1 * (1 - flip)),
                child: Container(
                  width: cardH * 0.72,
                  height: cardH,
                  padding: const EdgeInsets.all(12),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const RadialGradient(center: Alignment(-0.6, -1), radius: 1.4, colors: [Color(0xFF7C3AED), Color(0xFF3B0F7A), Color(0xFF14052E)]),
                    border: Border.all(color: const Color(0x59FFEBB0)),
                    boxShadow: const [BoxShadow(color: Color(0x59A855F7), blurRadius: 50), BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 24))],
                  ),
                  child: Stack(children: [
                    // holographic shine
                    Positioned.fill(
                      child: FractionalTranslation(
                        translation: Offset(-1 + (calm ? 0.5 : l) * 2, 0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0x00FFFFFF), Color(0x40FF9AD5), Color(0x509AF6FF), Color(0x40FFF59A), Color(0x00FFFFFF)],
                              stops: [0.3, 0.42, 0.5, 0.58, 0.7],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Row(children: [
                        Text('GullyScore', style: TextStyle(color: Color(0xFFE5D4FF), fontSize: 8, fontWeight: FontWeight.w800)),
                        Spacer(),
                        Text('SEASON 2026', style: TextStyle(color: Color(0xFFE5D4FF), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Container(
                          width: 48,
                          height: 48,
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: _gold)),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF4C8DF6), Color(0xFF1E3A8A)])),
                            child: const Text('ST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            FittedBox(fit: BoxFit.scaleDown, child: Text('SURAJ', style: _display(22))),
                            FittedBox(fit: BoxFit.scaleDown, child: _Gold('THAKUR', style: _display(22), shift: l)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: const Color(0x40FFEBB0))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                FittedBox(fit: BoxFit.scaleDown, child: _Gold(n(1412 * c, 0), style: _display(36), shift: l)),
                                const Text('RUNS', style: TextStyle(color: Color(0xFFE5D4FF), fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 1)),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(children: [
                              Expanded(child: stat(n(38.2 * c, 1), 'AVERAGE')),
                              const SizedBox(height: 6),
                              Expanded(child: stat(n(142.6 * c, 1), 'STRIKE RATE')),
                            ]),
                          ),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 0,
          child: Transform.scale(
            scale: _iv(t, 0.35, 0.55, Curves.elasticOut),
            child: SizedBox(
              width: 76,
              height: 76,
              child: CustomPaint(
                painter: _RingPainter(_iv(t, 0.45, 0.85)),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('⚡', style: TextStyle(fontSize: 15)),
                    _Gold('PRO II', style: _display(14)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: 4,
          child: Transform.scale(
            scale: _iv(t, 0.55, 0.72, Curves.elasticOut),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: 0.1), border: Border.all(color: Colors.white24)),
              child: Text('🏆 ${context.tr('intro_card_badge')}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ),
        ),
      ]);
    });
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);
  final double v;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 5);
    canvas.drawCircle(r.center, r.width / 2, Paint()..color = const Color(0x8C000000));
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = Colors.white12);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * 0.72 * v, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round..color = const Color(0xFFF4C247));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.v);
  final double v;
  static const _cols = [Color(0xFFFFC94A), Color(0xFF2BD38A), Color(0xFFF472B6), Color(0xFF5B9BFF), Color(0xFFA855F7), Color(0xFFFF8A3D)];
  @override
  void paint(Canvas canvas, Size s) {
    if (v <= 0 || v >= 1) return;
    final rnd = math.Random(9);
    for (var i = 0; i < 28; i++) {
      final x = rnd.nextDouble() * s.width;
      final delay = rnd.nextDouble() * 0.3;
      final p = ((v - delay) / 0.7).clamp(0.0, 1.0);
      if (p <= 0) continue;
      canvas.save();
      canvas.translate(x + math.sin(p * 6 + i) * 10, -20 + p * (s.height + 60));
      canvas.rotate(p * 8 + i);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -6, 6, 12), const Radius.circular(2)), Paint()..color = _cols[i % _cols.length].withValues(alpha: 1 - p * 0.6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.v != v;
}

// ---------------------------------------------------------------- scene 5: logo

class _LogoArt extends StatelessWidget {
  const _LogoArt({required this.t, required this.l, required this.calm});
  final double t, l;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final inV = _iv(t, 0.02, 0.3, Curves.elasticOut);
    final glow = calm ? 0.5 : (math.sin(l * math.pi * 2) + 1) / 2;
    Widget stump(double left, double at) {
      final v = _iv(t, at, at + 0.12, Curves.bounceOut);
      return Positioned(
        left: left,
        top: 30 - (1 - v) * 120,
        child: Opacity(opacity: _iv(t, at, at + 0.04), child: Container(width: 9, height: 52, decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(4)))),
      );
    }

    return Center(
      child: Opacity(
        opacity: _iv(t, 0, 0.1),
        child: Transform.rotate(
          angle: -0.4 * (1 - inV),
          child: Transform.scale(
            scale: 0.3 + 0.7 * inV,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFE9A21A)]),
                boxShadow: [BoxShadow(color: const Color(0xFFF4C247).withValues(alpha: 0.3 + 0.35 * glow), blurRadius: 40 + 30 * glow, spreadRadius: 2)],
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                stump(30, 0.25),
                stump(56, 0.31),
                stump(82, 0.37),
                Positioned(
                  left: 26,
                  top: 24,
                  child: Transform.scale(scale: _iv(t, 0.45, 0.55, Curves.elasticOut), child: Container(width: 68, height: 8, decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(4)))),
                ),
                Positioned(
                  right: 16,
                  bottom: 14,
                  child: Transform.translate(
                    offset: Offset(-120 * (1 - _iv(t, 0.5, 0.65)), -90 * (1 - _iv(t, 0.5, 0.65))),
                    child: Opacity(opacity: _iv(t, 0.5, 0.55), child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFFE23B3B), shape: BoxShape.circle))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
