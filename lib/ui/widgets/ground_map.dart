// Cricket ground drawn from above: used to tap where the ball went,
// and to draw a batter's wagon wheel.
//
// Angles are in a right-hander's frame: 0° is straight past the bowler
// (top of the screen), increasing clockwise. Off side is on the right for a
// right-hander; the map is mirrored for left-handers.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../scoring/commentary.dart';
import '../../scoring/engine.dart';

class ShotPoint {
  const ShotPoint(this.angle, this.dist, this.runs);
  final double angle;
  final double dist; // 0-1
  final int runs;
}

/// Pixel position of an angle/distance on a ground of radius [r] centred on [c].
Offset groundOffset(Offset c, double r, double angle, double dist, bool leftHanded) {
  final a = leftHanded ? -angle : angle;
  final rad = (a - 90) * math.pi / 180;
  return c + Offset(math.cos(rad), math.sin(rad)) * (r * dist);
}

class GroundPainter extends CustomPainter {
  GroundPainter({
    required this.palette,
    required this.lang,
    this.selectedZone,
    this.tap,
    this.shots = const [],
    this.leftHanded = false,
    this.showLabels = true,
  });

  final Palette palette;
  final String lang;
  final String? selectedZone;
  final ShotPoint? tap;
  final List<ShotPoint> shots;
  final bool leftHanded;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;

    canvas.drawCircle(c, r + 4, Paint()..color = const Color(0xFF0B3B26));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1F6B45), Color(0xFF124A30)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Selected zone wedge.
    if (selectedZone != null) {
      final i = Zone.all.indexOf(selectedZone!);
      if (i >= 0) {
        var start = i * 45.0;
        if (leftHanded) start = -start - 45;
        final path = Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(Rect.fromCircle(center: c, radius: r), (start - 90) * math.pi / 180, math.pi / 4, false)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0x47FFC94A));
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFC94A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 8; i++) {
      canvas.drawLine(c, groundOffset(c, r, i * 45.0, 1, false), linePaint);
    }

    // 30-yard circle (dashed).
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const steps = 48;
    for (var i = 0; i < steps; i += 2) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.49), i * 2 * math.pi / steps, 2 * math.pi / steps, false, dash);
    }

    // Pitch and batter.
    final pitch = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: r * 0.09, height: r * 0.33), const Radius.circular(3));
    canvas.drawRRect(pitch, Paint()..color = const Color(0xFFC9B07A));
    final bat = c + Offset(0, r * 0.125);
    canvas.drawCircle(bat, 5, Paint()..color = const Color(0xFFF2F5FA));

    // Wagon wheel lines.
    for (final s in shots) {
      final color = s.runs == 6
          ? const Color(0xFFFF8A3D)
          : s.runs == 4
              ? const Color(0xFFFFC94A)
              : const Color(0xFF9DB4D6);
      canvas.drawLine(
        bat,
        groundOffset(c, r, s.angle, s.dist.clamp(0.08, 1.02), leftHanded),
        Paint()
          ..color = color.withValues(alpha: s.runs >= 4 ? 1 : 0.7)
          ..strokeWidth = s.runs >= 4 ? 3 : 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Zone names.
    if (showLabels) {
      for (var i = 0; i < 8; i++) {
        final z = Zone.all[i];
        final pos = groundOffset(c, r, i * 45.0 + 22.5, 0.77, leftHanded);
        final selected = z == selectedZone;
        final tp = TextPainter(
          text: TextSpan(
            text: Zone.name(z, lang),
            style: TextStyle(
              fontFamily: 'Hanken',
              fontFamilyFallback: const ['NotoDeva'],
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? const Color(0xFF0B1220) : const Color(0xFFF2F5FA),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (selected) {
          final box = RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: tp.width + 16, height: 24), const Radius.circular(8));
          canvas.drawRRect(box, Paint()..color = const Color(0xFFFFC94A));
        }
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Tap marker.
    final t = tap;
    if (t != null) {
      final end = groundOffset(c, r, t.angle, t.dist, leftHanded);
      canvas.drawLine(
        bat,
        end,
        Paint()
          ..color = const Color(0xFFFFC94A)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(end, 16, Paint()..color = const Color(0x40FFC94A));
      canvas.drawCircle(end, 8, Paint()..color = const Color(0xFFFFC94A));
      canvas.drawCircle(
        end,
        8,
        Paint()
          ..color = const Color(0xFF0B1220)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(GroundPainter old) =>
      old.selectedZone != selectedZone || old.tap != tap || old.shots != shots || old.leftHanded != leftHanded || old.lang != lang || old.palette != palette;
}

/// Ground the scorer taps. Calls [onTap] with angle (right-hander frame) and distance.
class TapGround extends StatelessWidget {
  const TapGround({super.key, required this.leftHanded, required this.onTap, this.selected, this.tap});
  final bool leftHanded;
  final String? selected;
  final ShotPoint? tap;
  final void Function(double angle, double dist) onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lang = context.settings.lang;
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(box.maxWidth, 340.0);
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Semantics(
            label: context.tr('shot_map_semantics'),
            child: GestureDetector(
              onTapDown: (d) {
                final c = Offset(side / 2, side / 2);
                final r = side / 2 - 6;
                final v = d.localPosition - c;
                var deg = math.atan2(v.dy, v.dx) * 180 / math.pi + 90;
                if (leftHanded) deg = -deg;
                deg = ((deg % 360) + 360) % 360;
                final dist = ((d.localPosition - c).distance / r).clamp(0.15, 1.0);
                onTap(deg, dist);
              },
              child: CustomPaint(
                painter: GroundPainter(palette: p, lang: lang, selectedZone: selected, tap: tap, leftHanded: leftHanded),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Shots for a batter's wagon wheel.
List<ShotPoint> wagonShots(Iterable<BallLog> balls, String batterId) => [
      for (final b in balls)
        if (b.striker == batterId && b.angle != null && (b.kind == BallKind.normal || b.kind == BallKind.noBall) && b.runs > 0)
          ShotPoint(b.angle!, b.dist ?? (b.runs >= 4 ? 1 : 0.6), b.runs),
    ];
