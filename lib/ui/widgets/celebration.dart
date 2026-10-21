// Four, six and wicket celebrations drawn over the score card.
// They never block taps, play once per ball, and shrink to a short colour
// change when the phone asks for reduced motion.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';

enum Celebration { four, six, wicket }

class CelebrationLayer extends StatefulWidget {
  const CelebrationLayer({super.key, required this.child});
  final Widget child;

  @override
  State<CelebrationLayer> createState() => CelebrationLayerState();
}

class CelebrationLayerState extends State<CelebrationLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Celebration? _kind;
  bool _reduced = false;

  /// Starts a celebration. A new one replaces any that is still running.
  void play(Celebration kind, {required String label}) {
    final reduce = context.reduceMotion;
    final s = context.settings;
    if (s.haptics) {
      if (kind == Celebration.six) HapticFeedback.lightImpact();
      if (kind == Celebration.wicket) HapticFeedback.heavyImpact();
    }
    SemanticsService.announce(label, Directionality.of(context));
    setState(() {
      _kind = kind;
      _reduced = reduce;
    });
    _c.duration = reduce
        ? Motion.reduced * 4
        : switch (kind) {
            Celebration.four => Motion.four,
            Celebration.six => Motion.six,
            Celebration.wicket => Motion.wicket,
          };
    _c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _kind = null);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_kind != null)
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corners.hero),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _CelebrationPainter(_kind!, _c.value, _reduced),
                  child: _Word(kind: _kind!, t: _c.value, reduced: _reduced),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Word extends StatelessWidget {
  const _Word({required this.kind, required this.t, required this.reduced});
  final Celebration kind;
  final double t;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      Celebration.four => const Color(0xFFFFC94A),
      Celebration.six => const Color(0xFFFF8A3D),
      Celebration.wicket => const Color(0xFFFF6B6B),
    };
    final text = switch (kind) {
      Celebration.four => 'FOUR',
      Celebration.six => 'SIX!',
      Celebration.wicket => 'WICKET',
    };
    // In for the first 20%, hold, out over the last 25%.
    final opacity = reduced ? (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0) : (t < 0.2 ? t / 0.2 : (t > 0.75 ? (1 - t) / 0.25 : 1.0));
    final scale = reduced ? 1.0 : (t < 0.2 ? 0.86 + 0.14 * Curves.easeOutCubic.transform(t / 0.2) : 1.0);
    return Center(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Text(
            text,
            style: Tx.score(kind == Celebration.six ? 72 : 60, color).copyWith(
              shadows: [Shadow(color: color.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 6))],
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.kind, this.t, this.reduced);
  final Celebration kind;
  final double t;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
    final base = switch (kind) {
      Celebration.four => const Color(0xFFFFC94A),
      Celebration.six => const Color(0xFFFF8A3D),
      Celebration.wicket => const Color(0xFFFF4D4D),
    };
    final rect = Offset.zero & size;
    // Dim the card a little so the word reads clearly.
    canvas.drawRect(rect, Paint()..color = const Color(0xFF070F1E).withValues(alpha: 0.55 * fade));

    if (reduced) {
      canvas.drawRect(rect, Paint()..color = base.withValues(alpha: 0.18 * fade));
      return;
    }

    switch (kind) {
      case Celebration.four:
        // A gold band sweeps once across the card.
        final x = -size.width * 0.6 + size.width * 2.2 * Curves.easeInOutCubic.transform(t);
        final band = Rect.fromLTWH(x, 0, size.width * 0.5, size.height);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(colors: [base.withValues(alpha: 0), base.withValues(alpha: 0.32 * fade), base.withValues(alpha: 0)])
                .createShader(band),
        );
      case Celebration.six:
        final c = size.center(Offset.zero);
        canvas.drawCircle(
          c,
          size.longestSide * 0.6,
          Paint()
            ..shader = RadialGradient(colors: [base.withValues(alpha: 0.32 * fade), base.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: size.longestSide * 0.6)),
        );
        // Dotted arc with the ball travelling along it.
        final start = Offset(size.width * 0.08, size.height * 0.92);
        final ctrl = Offset(size.width * 0.5, -size.height * 0.35);
        final end = Offset(size.width * 0.92, size.height * 0.28);
        Offset at(double u) {
          final a = 1 - u;
          return start * (a * a) + ctrl * (2 * a * u) + end * (u * u);
        }

        final travel = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
        final dot = Paint()..color = base.withValues(alpha: 0.85 * fade);
        for (var u = 0.0; u <= travel; u += 0.035) {
          canvas.drawCircle(at(u), 1.8, dot);
        }
        final ball = at(travel);
        canvas.drawCircle(ball, 12, Paint()..color = base.withValues(alpha: 0.35 * fade));
        canvas.drawCircle(ball, 6.5, Paint()..color = Colors.white.withValues(alpha: fade));
      case Celebration.wicket:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(colors: [base.withValues(alpha: 0.30 * fade), base.withValues(alpha: 0)])
                .createShader(rect),
        );
        // Three stumps topple outwards.
        final fall = Curves.easeInCubic.transform((t / 0.5).clamp(0.0, 1.0));
        final groundY = size.height * 0.86;
        final h = size.height * 0.26;
        final cx = size.width / 2;
        final stump = Paint()
          ..color = const Color(0xFFF2F5FA).withValues(alpha: 0.9 * fade)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        for (var i = -1; i <= 1; i++) {
          final angle = i * 0.5 * fall + (i == 0 ? 0.25 * fall : 0);
          final bottom = Offset(cx + i * 16.0, groundY);
          final top = bottom + Offset(math.sin(angle) * h, -math.cos(angle) * h);
          canvas.drawLine(bottom, top, stump);
        }
        // Bails fly off.
        final bail = Paint()
          ..color = const Color(0xFFFFC94A).withValues(alpha: fade)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        final by = groundY - h - 4 - 40 * fall;
        canvas.drawLine(Offset(cx - 18 - 30 * fall, by), Offset(cx - 2 - 30 * fall, by + 6 * fall), bail);
        canvas.drawLine(Offset(cx + 2 + 30 * fall, by + 6 * fall), Offset(cx + 18 + 30 * fall, by), bail);
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.t != t || old.kind != kind || old.reduced != reduced;
}
