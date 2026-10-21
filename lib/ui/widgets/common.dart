// Reusable building blocks used on every screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/photos.dart';

// ---------------------------------------------------------------- crest

/// Team badge: the team's logo if it has one, otherwise a shield with initials.
class Crest extends StatelessWidget {
  const Crest({super.key, required this.color, this.text = '', this.size = 28, this.logo});
  final Color color;
  final String text;
  final double size;
  final String? logo; // file name of the team logo saved on this phone

  @override
  Widget build(BuildContext context) {
    final file = PhotoStore.file(logo);
    if (file != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.file(
          file,
          width: size,
          height: size * 1.1,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          gaplessPlayback: true,
          errorBuilder: (c, e, st) => _shield(),
        ),
      );
    }
    return _shield();
  }

  Widget _shield() {
    return SizedBox(
      width: size,
      height: size * 1.1,
      child: CustomPaint(
        painter: _ShieldPainter(color),
        child: text.isEmpty || size < 20
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: size * 0.12),
                child: Center(
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.3, height: 1),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 40;
    final sy = size.height / 44;
    final p = Path()
      ..moveTo(20 * sx, 2 * sy)
      ..lineTo(36 * sx, 8 * sy)
      ..lineTo(36 * sx, 22 * sy)
      ..cubicTo(36 * sx, 32 * sy, 28 * sx, 38 * sy, 20 * sx, 42 * sy)
      ..cubicTo(12 * sx, 38 * sy, 4 * sx, 32 * sy, 4 * sx, 22 * sy)
      ..lineTo(4 * sx, 8 * sy)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.color != color;
}

// ---------------------------------------------------------------- badges

/// "Live" badge whose dot has a soft ring that pulses (never flashes).
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, required this.label});
  final String label;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: widget.label,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: p.live.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _c.value;
              return SizedBox(
                width: 14,
                height: 14,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: p.live,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: p.live.withValues(alpha: 0.35 * (1 - t)), spreadRadius: 1 + 4 * t)],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 3),
          Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.liveText, w: FontWeight.w800))),
        ]),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.background});
  final String text;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background ?? p.raised, borderRadius: BorderRadius.circular(8)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(color ?? p.text2, w: FontWeight.w800)),
    );
  }
}

/// One delivery as a round chip: gold four, orange six, red wicket.
class BallChip extends StatelessWidget {
  const BallChip(this.label, {super.key, this.size = 28, this.highlight = false});
  final String label;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Color bg = p.raised;
    Color fg = p.text;
    final wicket = label.contains('W') && !label.contains('Wd');
    if (wicket) {
      bg = const Color(0xFFFF4D4D);
      fg = Colors.white;
    } else if (label == '4' || label == '4Nb') {
      bg = const Color(0xFFFFC94A);
      fg = const Color(0xFF0B1220);
    } else if (label == '6' || label == '6Nb') {
      bg = const Color(0xFFFF8A3D);
      fg = const Color(0xFF0B1220);
    }
    final text = label == '•' ? '0' : label;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: highlight ? [BoxShadow(color: bg.withValues(alpha: 0.35), spreadRadius: 3)] : null,
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(text, style: TextStyle(fontSize: text.length > 2 ? 10 : 12, fontWeight: FontWeight.w800, color: fg)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- press feedback

/// Shrinks to 97% while pressed (100 ms, no bounce) and gives a light tick.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.semanticLabel, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = context.reduceMotion;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !reduce ? 0.97 : 1,
          duration: Motion.press,
          curve: Motion.enter,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: Motion.fade,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- surfaces

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.borderColor, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // A Material (not a coloured box) so list rows inside show their ripple.
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corners.card),
        boxShadow: p.dark ? null : const [BoxShadow(color: Color(0x0D0F1E3C), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Material(
        color: color ?? p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.card),
          side: BorderSide(color: borderColor ?? p.line),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return box;
    return Pressable(onTap: onTap, child: box);
  }
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.glow, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glow;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corners.hero),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.hero1, p.hero2], stops: const [0, 0.62]),
        border: Border.all(color: borderColor ?? p.heroLine),
        boxShadow: [BoxShadow(color: p.dark ? const Color(0x59000000) : const Color(0x1A0F1E3C), blurRadius: p.dark ? 36 : 28, offset: Offset(0, p.dark ? 16 : 10))],
      ),
      child: Stack(children: [
        Positioned(
          right: -60,
          top: -80,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [(glow ?? const Color(0xFFFFD678)).withValues(alpha: p.dark ? 0.18 : 0.14), (glow ?? const Color(0xFFFFD678)).withValues(alpha: 0)]),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

// ---------------------------------------------------------------- headings and buttons

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: Tx.section(p.text)))),
        if (action != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(48, 40), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            child: Text(action!),
          ),
      ]),
    );
  }
}

class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 52});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.gold, borderRadius: BorderRadius.circular(Corners.button)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: const Color(0xFF0B1220)), const SizedBox(width: 8)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0B1220), fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
        ),
      ),
    );
  }
}

class OutlineBtn extends StatelessWidget {
  const OutlineBtn({super.key, required this.label, required this.onPressed, this.icon, this.height = 52, this.color});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.text;
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Corners.button), border: Border.all(color: p.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 8)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
        ),
      ),
    );
  }
}

/// 44×44 square icon button.
class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color, this.highlight = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Corners.button),
            border: Border.all(color: highlight ? p.gold : p.line),
          ),
          child: Icon(icon, size: 20, color: color ?? (highlight ? p.goldText : p.text)),
        ),
      ),
    );
  }
}

/// Chip used for filters and choices.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: Motion.fade,
            curve: Motion.move,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? p.gold : p.surface,
              borderRadius: BorderRadius.circular(Corners.chip),
              border: Border.all(color: selected ? p.gold : p.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? const Color(0xFF0B1220) : p.text), const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? const Color(0xFF0B1220) : p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three or more equal segments, e.g. Light / Dark / Auto.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Corners.button), border: Border.all(color: p.line)),
      child: Row(children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Semantics(
              selected: values[i] == selected,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(values[i]);
                },
                child: AnimatedContainer(
                  duration: Motion.fade,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: values[i] == selected ? p.raised : Colors.transparent,
                    borderRadius: BorderRadius.circular(Corners.chip),
                  ),
                  child: Text(labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: values[i] == selected ? p.text : p.text2)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- loading, empty, error

/// Soft sweep across skeleton boxes; still when motion is reduced.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hi = p.dark ? const Color(0xFF1D3152) : const Color(0xFFF7F9FC);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = -1 + 3 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x, 0),
            colors: [p.raised, hi, p.raised],
          ).createShader(r);
        },
        child: child,
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(width: width, height: height, decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(radius)));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(Corners.card)),
          child: Icon(icon, size: 30, color: p.goldText),
        ),
        const SizedBox(height: Space.l),
        Text(title, textAlign: TextAlign.center, style: Tx.section(p.text)),
        const SizedBox(height: Space.s),
        Text(body, textAlign: TextAlign.center, style: Tx.body(p.text2)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: Space.l),
          GoldButton(label: actionLabel!, onPressed: onAction, height: 48),
        ],
      ]),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.title, required this.body, required this.retryLabel, required this.onRetry});
  final String title;
  final String body;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: p.live.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Corners.card)),
          child: Icon(Icons.error_outline_rounded, size: 28, color: p.liveText),
        ),
        const SizedBox(height: Space.m),
        Text(title, textAlign: TextAlign.center, style: Tx.section(p.text)),
        const SizedBox(height: Space.s),
        Text(body, textAlign: TextAlign.center, style: Tx.body(p.text2)),
        const SizedBox(height: Space.l),
        GoldButton(label: retryLabel, onPressed: onRetry, height: 44),
      ]),
    );
  }
}

// ---------------------------------------------------------------- score text

/// Score like "87/3" where only the characters that changed roll up.
class AnimatedScore extends StatelessWidget {
  const AnimatedScore({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final chars = text.split('');
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < chars.length; i++)
            AnimatedSwitcher(
              duration: reduce ? Motion.reduced : Motion.score,
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, anim) {
                if (reduce) return FadeTransition(opacity: anim, child: child);
                final incoming = child.key == ValueKey('$i-${chars[i]}');
                final offset = Tween<Offset>(begin: Offset(0, incoming ? 0.6 : -0.6), end: Offset.zero).animate(anim);
                return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
              },
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, if (current != null) current]),
              child: Text(chars[i], key: ValueKey('$i-${chars[i]}'), style: style),
            ),
        ]),
      ),
    );
  }
}
