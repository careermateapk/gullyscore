// First-time app tour: the screen goes dark, one button at a time lights up
// with a gold ring, and a gold card explains it. Shown once after the first
// log in; Menu → App tour plays it again.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/scope.dart';

const _ink = Color(0xFF0B1220);
const _goldA = Color(0xFFF4C247);
const _goldB = Color(0xFFFFE7A3);

/// The buttons the tour points at.
class TourKeys {
  static final score = GlobalKey(debugLabel: 'tour-score');
  static final menu = GlobalKey(debugLabel: 'tour-menu');
  static final link = GlobalKey(debugLabel: 'tour-link');
  static final search = GlobalKey(debugLabel: 'tour-search');
  static final navBar = GlobalKey(debugLabel: 'tour-nav');
}

/// Bump this to play the tour again (Menu → App tour).
final tourRequest = ValueNotifier<int>(0);

class _Step {
  const _Step(this.rect, this.emoji, this.title, this.body);
  final Rect? Function() rect;
  final String emoji, title, body;
}

Rect? _rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Rect? _navSlot(int i) {
  final r = _rectOf(TourKeys.navBar);
  if (r == null) return null;
  final w = r.width / 5;
  return Rect.fromLTWH(r.left + w * i + 4, r.top + 4, w - 8, math.min(r.height - 8, 64));
}

/// Puts the tour over the whole app. [onDone] runs when it is finished or skipped.
OverlayEntry showAppTour(BuildContext context, {required VoidCallback onDone}) {
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => AppTour(onDone: () {
        entry.remove();
        onDone();
      }));
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

class AppTour extends StatefulWidget {
  const AppTour({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<AppTour> createState() => _AppTourState();
}

class _AppTourState extends State<AppTour> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _show = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  int _i = -1; // -1 = "Quick tour?" card
  Rect? _from, _to;
  List<_Step> _steps = const [];
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _show.value = 1;
      _move.value = 1;
      _pulse.stop();
    } else {
      if (_show.value == 0 && !_show.isAnimating) _show.forward();
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    _show.dispose();
    super.dispose();
  }

  List<_Step> _allSteps() => [
        _Step(() => _rectOf(TourKeys.score), '⚡', context.tr('tour_score_t'), context.tr('tour_score_b')),
        _Step(() => _rectOf(TourKeys.menu), '☰', context.tr('tour_menu_t'), context.tr('tour_menu_b')),
        _Step(() => _rectOf(TourKeys.link), '🔗', context.tr('tour_link_t'), context.tr('tour_link_b')),
        _Step(() => _rectOf(TourKeys.search), '🔍', context.tr('tour_search_t'), context.tr('tour_search_b')),
        _Step(() => _navSlot(1), '🏏', context.tr('tour_matches_t'), context.tr('tour_matches_b')),
        _Step(() => _navSlot(2), '🪪', context.tr('tour_mycricket_t'), context.tr('tour_mycricket_b')),
        _Step(() => _navSlot(3), '👥', context.tr('tour_community_t'), context.tr('tour_community_b')),
      ];

  void _go(int i) {
    if (i >= _steps.length) return _finish();
    final r = _steps[i].rect();
    if (r == null) return _go(i + 1); // that button is not on screen: skip it
    setState(() {
      _from = _to ?? r;
      _to = r;
      _i = i;
    });
    if (context.reduceMotion) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
  }

  void _start() {
    _steps = _allSteps().where((s) => s.rect() != null).toList();
    if (_steps.isEmpty) return _finish();
    _go(0);
  }

  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    if (!context.reduceMotion) await _show.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([_move, _pulse, _show]),
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          final fade = _show.value;
          if (_i < 0) return Opacity(opacity: fade, child: _intro(context));
          final k = Curves.easeOutCubic.transform(_move.value);
          // re-read the target in case the screen moved
          final target = _steps[_i].rect() ?? _to!;
          final rect = Rect.lerp(_from, target, k)!;
          final below = rect.center.dy < size.height * 0.55;
          final tipIn = context.reduceMotion ? 1.0 : Curves.easeOut.transform(((_move.value - 0.45) / 0.55).clamp(0.0, 1.0));
          return Opacity(
            opacity: fade,
            child: Stack(children: [
              // dark screen with a hole; taps on it do nothing
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(painter: _SpotPainter(rect: rect, pulse: context.reduceMotion ? null : _pulse.value)),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: below ? rect.bottom + 18 : null,
                bottom: below ? null : size.height - rect.top + 18,
                child: Opacity(
                  opacity: tipIn,
                  child: Transform.translate(
                    offset: Offset(0, (1 - tipIn) * (below ? 12 : -12)),
                    child: _tip(context, rect, below),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _tip(BuildContext context, Rect rect, bool below) {
    final last = _i == _steps.length - 1;
    final s = _steps[_i];
    final arrowX = (rect.center.dx - 16 - 9).clamp(18.0, MediaQuery.sizeOf(context).width - 32 - 36);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_goldB, _goldA, Color(0xFFE9A21A)], stops: [0, 0.55, 1]),
        boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(context.tr('tour_step_n', {'i': _i + 1, 'n': _steps.length}).toUpperCase(),
            style: TextStyle(color: _ink.withValues(alpha: 0.65), fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 1.3)),
        const SizedBox(height: 3),
        Text('${s.emoji}  ${s.title}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text(s.body, style: TextStyle(color: _ink.withValues(alpha: 0.85), fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 5, runSpacing: 4, children: [
              for (var j = 0; j < _steps.length; j++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: j == _i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: j == _i ? _ink : _ink.withValues(alpha: 0.25)),
                ),
            ]),
          ),
          if (!last)
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(foregroundColor: _ink.withValues(alpha: 0.65), minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: Text(context.tr('skip'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          FilledButton(
            onPressed: () => _go(_i + 1),
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: _goldB,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(last ? context.tr('tour_lets_play') : '${context.tr('next')} →', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ]),
    );
    final arrow = Padding(
      padding: EdgeInsets.only(left: arrowX),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(width: 18, height: 18, decoration: BoxDecoration(color: below ? _goldB : _goldA, borderRadius: BorderRadius.circular(3))),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: below
          ? [Transform.translate(offset: const Offset(0, 9), child: arrow), card]
          : [card, Transform.translate(offset: const Offset(0, -9), child: arrow)],
    );
  }

  Widget _intro(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: () {}, child: const ColoredBox(color: Color(0xCC03060D)))),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Transform.scale(
            scale: 0.9 + 0.1 * Curves.easeOutBack.transform(_show.value),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C2540), Color(0xFF0E1626)]),
                border: Border.all(color: _goldB.withValues(alpha: 0.3)),
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('👋🏏', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(context.tr('tour_q_title'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 21)),
                const SizedBox(height: 6),
                Text(context.tr('tour_q_body'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.45)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        minimumSize: const Size(48, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(context.tr('skip'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: _start,
                      style: FilledButton.styleFrom(
                        backgroundColor: _goldA,
                        foregroundColor: _ink,
                        minimumSize: const Size(48, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('${context.tr('tour_show_me')} →', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter({required this.rect, this.pulse});
  final Rect rect;
  final double? pulse; // 0..1, null when motion is reduced

  @override
  void paint(Canvas canvas, Size size) {
    final hole = rect.inflate(6);
    final radius = Radius.circular(math.min(hole.shortestSide / 2, hole.height > 70 ? 22 : 16));
    final rr = RRect.fromRectAndRadius(hole, radius);
    final dim = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr));
    canvas.drawPath(dim, Paint()..color = const Color(0xC703060D));
    canvas.drawRRect(rr, Paint()..color = _goldA.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 10..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawRRect(rr, Paint()..color = _goldA..style = PaintingStyle.stroke..strokeWidth = 3);
    final p = pulse;
    if (p != null) {
      final grow = p * 12;
      canvas.drawRRect(RRect.fromRectAndRadius(hole.inflate(grow), radius + Radius.circular(grow)),
          Paint()..color = _goldB.withValues(alpha: (1 - p) * 0.8)..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_SpotPainter old) => old.rect != rect || old.pulse != pulse;
}
