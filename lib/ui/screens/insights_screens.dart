// Head to head (one batter against one bowler), My level (XP) and the
// row of fun tools on a player's profile.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../scoring/insights.dart';
import '../../scoring/stats.dart';
import '../../studio/share_entry.dart';
import '../../studio/stories.dart';
import '../../studio/studio_screen.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

/// Fun tools on a player's profile: card, wrapped, level, compare, head to head.
class PlayerTools extends StatelessWidget {
  const PlayerTools({super.key, required this.playerId});
  final String playerId;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final list = statMatchesOf(repo, playerId: playerId);
    final s = playerStats(playerId, list);
    final level = Level(xpOf(s, potm: potmCount(playerId, list)));
    final lang = context.settings.lang;
    Widget tool(String emoji, String label, VoidCallback onTap, {List<Color>? colors}) => Expanded(
          child: Pressable(
            onTap: onTap,
            semanticLabel: label,
            child: Container(
              constraints: const BoxConstraints(minHeight: 86),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corners.card),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors ?? [p.surface, p.surface]),
                border: Border.all(color: p.line),
              ),
              child: ExcludeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 8),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(colors == null ? p.text : Colors.white, w: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Level strip
      Pressable(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LevelScreen(playerId: playerId))),
        semanticLabel: context.tr('my_level'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corners.card),
            gradient: const LinearGradient(colors: [Color(0xFF17325A), Color(0xFF0E1B30)]),
            border: Border.all(color: const Color(0xFF234071)),
          ),
          child: ExcludeSemantics(
            child: Row(children: [
              Text(levelEmoji[level.tier], style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(levelName(level, lang), style: Tx.score(22, const Color(0xFFFFC94A), w: FontWeight.w800)),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(value: level.progress, minHeight: 6, backgroundColor: Colors.white12, color: const Color(0xFFFFC94A)),
                  ),
                  const SizedBox(height: 4),
                  Text(level.isMax ? context.tr('level_max') : context.tr('xp_to_next', {'n': level.toNext}),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(const Color(0xFFA9B6C9))),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFA9B6C9)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: Space.s),
      Row(children: [
        tool('🪪', context.tr('player_card'), () => openPlayerCard(context, playerId), colors: const [Color(0xFF6D28D9), Color(0xFF3B0F7A)]),
        const SizedBox(width: Space.s),
        tool('🎁', context.tr('season_wrapped'), () => openSeasonWrapped(context, playerId), colors: const [Color(0xFFFF6A3D), Color(0xFFE8326E)]),
      ]),
      const SizedBox(height: Space.s),
      Row(children: [
        tool('⚔️', context.tr('compare_players'), () async {
          final other = await pickOtherPlayer(context, playerId);
          if (other != null && context.mounted) await openFaceOff(context, playerId, other);
        }),
        const SizedBox(width: Space.s),
        tool('😈', context.tr('head_to_head'), () async {
          final all = statMatchesOf(repo);
          final faced = rivals(playerId, all, asBatter: true);
          final bowledTo = rivals(playerId, all, asBatter: false);
          final merged = [...faced, ...bowledTo]..sort((a, b) => b.$2.compareTo(a.$2));
          final other = await pickOtherPlayer(context, playerId, suggested: merged);
          if (other == null || !context.mounted) return;
          // The player batted against the other player more often, or bowled to them?
          final asBat = faced.where((x) => x.$1 == other).firstOrNull?.$2 ?? 0;
          final asBowl = bowledTo.where((x) => x.$1 == other).firstOrNull?.$2 ?? 0;
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => HeadToHeadScreen(batter: asBat >= asBowl ? playerId : other, bowler: asBat >= asBowl ? other : playerId)),
          );
        }),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- head to head

class HeadToHeadScreen extends StatefulWidget {
  const HeadToHeadScreen({super.key, required this.batter, required this.bowler});
  final String batter;
  final String bowler;

  @override
  State<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends State<HeadToHeadScreen> {
  final _key = GlobalKey();
  late String _bat = widget.batter;
  late String _bowl = widget.bowler;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final h = headToHead(_bat, _bowl, statMatchesOf(repo));
    final batName = repo.playerName(_bat), bowlName = repo.playerName(_bowl);
    final edge = h.edge;
    final (emoji, verdict) = h.balls == 0
        ? ('🤷', context.tr('h2h_none'))
        : edge < 0
            ? ('😈', context.tr('h2h_bowler_ahead', {'name': bowlName.split(' ').first}))
            : edge > 0
                ? ('🔥', context.tr('h2h_batter_ahead', {'name': batName.split(' ').first}))
                : ('🤝', context.tr('h2h_even'));
    final detail = h.balls == 0
        ? context.tr('h2h_none_body')
        : h.outs > 0
            ? context.tr('h2h_out_detail', {'n': h.outs, 'b': h.balls, 'e': (h.balls / h.outs).toStringAsFixed(0)})
            : context.tr('h2h_not_out_detail', {'b': h.balls, 'r': h.runs});
    Widget person(String id, String role, List<Color> ring) => Expanded(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: ring)),
              child: PlayerAvatar(playerId: id, size: 64, color: const Color(0xFF17325A)),
            ),
            const SizedBox(height: 8),
            Text(repo.playerName(id), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(Colors.white, w: FontWeight.w800)),
            Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(const Color(0xFFA9B6C9))),
          ]),
        );
    Widget row(String label, String a, String b, {int better = 0}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          child: Row(children: [
            SizedBox(width: 64, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(a, style: Tx.score(22, better == 1 ? p.goldText : p.text, w: FontWeight.w800)))),
            Expanded(child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w800))),
            SizedBox(
              width: 64,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(b, style: Tx.score(22, better == -1 ? const Color(0xFFC084FC) : p.text, w: FontWeight.w800))),
            ),
          ]),
        );
    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2408), Color(0xFF0E1B30), Color(0xFF2A0F4A)]),
        border: Border.all(color: const Color(0xFF234071)),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          person(_bat, '🏏 ${context.tr('batter')}', const [Color(0xFFFFE7A3), Color(0xFFF97316)]),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFB8862B), Color(0xFFFFE7A3), Color(0xFFF4C247)]).createShader(r),
                child: Text('VS', style: Tx.score(34, Colors.white)),
              ),
              Text(context.tr('matches_n', {'n': h.matches.length}), style: Tx.label(const Color(0xFFA9B6C9))),
            ]),
          ),
          person(_bowl, '🎯 ${context.tr('bowler')}', const [Color(0xFFD8B4FE), Color(0xFF7C3AED)]),
        ]),
        const SizedBox(height: Space.m),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0x26A855F7), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x59A855F7))),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(verdict, style: Tx.body(Colors.white, w: FontWeight.w800)),
                Text(detail, style: Tx.label(const Color(0xFFA9B6C9), w: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ]),
    );
    final seq = h.sequence.length > 60 ? h.sequence.sublist(h.sequence.length - 60) : h.sequence;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        title: Text(context.tr('head_to_head')),
        actions: [
          IconButton(
            tooltip: context.tr('swap_roles'),
            onPressed: () => setState(() {
              final t = _bat;
              _bat = _bowl;
              _bowl = t;
            }),
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(
            tooltip: context.tr('share_picture'),
            onPressed: () => sharePng(_key, fileName: 'gullyscore-h2h', text: context.tr('h2h_share_text', {'a': batName, 'b': bowlName})),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: [
        RepaintBoundary(key: _key, child: ColoredBox(color: p.bg, child: card)),
        const SizedBox(height: Space.m),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(child: Text(batName.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.goldText, w: FontWeight.w800))),
                Expanded(child: Text(bowlName.split(' ').first, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(const Color(0xFFC084FC), w: FontWeight.w800))),
              ]),
            ),
            row(context.tr('h2h_runs'), '${h.runs}', '${h.runs}'),
            row(context.tr('balls'), '${h.balls}', '${h.balls}'),
            row(context.tr('h2h_sr_econ'), h.balls == 0 ? '-' : h.strikeRate.toStringAsFixed(1), h.balls == 0 ? '-' : h.economy.toStringAsFixed(2),
                better: h.balls == 0 ? 0 : (h.strikeRate >= 120 ? 1 : (h.economy <= 6 ? -1 : 0))),
            row(context.tr('dismissals'), '-', '${h.outs}', better: h.outs > 0 ? -1 : 0),
            row(context.tr('dot_balls'), '${h.dotPercent}%', '${h.dotPercent}%', better: h.dotPercent >= 50 ? -1 : 0),
            row(context.tr('boundaries'), '${h.fours + h.sixes}', '${h.fours + h.sixes}', better: h.fours + h.sixes > 0 ? 1 : 0),
          ]),
        ),
        if (seq.isNotEmpty) ...[
          SectionHeader(context.tr('every_ball_between')),
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (final b in seq)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: b == 'W'
                      ? const Color(0xFFFF4D4D)
                      : b == '4'
                          ? const Color(0x405B9BFF)
                          : b == '6'
                              ? const Color(0x4DA855F7)
                              : p.raised,
                ),
                child: Text(b, style: Tx.label(b == 'W' ? Colors.white : p.text, w: FontWeight.w800)),
              ),
          ]),
        ],
        if (h.howOut.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in h.howOut.entries) Tag('${context.tr('out_${e.key.replaceAll(' ', '_')}')} ${e.value}')]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- my level

class LevelScreen extends StatelessWidget {
  const LevelScreen({super.key, required this.playerId});
  final String playerId;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final lang = context.settings.lang;
    final list = statMatchesOf(repo, playerId: playerId);
    final s = playerStats(playerId, list);
    final potm = potmCount(playerId, list);
    final xp = xpOf(s, potm: potm);
    final level = Level(xp);
    // XP from the last 7 days
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recent = [for (final m in repo.matchList) if (m.updatedAt.isAfter(weekAgo) && (m.playersA.contains(playerId) || m.playersB.contains(playerId))) m.id];
    final weekList = list.where((m) => recent.contains(m.id)).toList();
    final weekXp = xpOf(playerStats(playerId, weekList), potm: potmCount(playerId, weekList));
    final earned = <(String, String, int)>[
      ('🏟', context.tr('xp_match'), s.matches * 10),
      ('🏏', context.tr('xp_run'), s.runs),
      ('🎯', context.tr('xp_wicket'), s.wickets * 20),
      ('🧤', context.tr('xp_catch'), (s.catches + s.runOuts + s.stumpings) * 10),
      ('⭐', context.tr('xp_fifty'), s.fifties * 25 + s.hundreds * 75),
      ('🏆', context.tr('xp_potm'), potm * 100),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.bg, title: Text(context.tr('my_level'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const RadialGradient(center: Alignment(0, -1), radius: 1.3, colors: [Color(0xFF3A3416), Color(0xFF17325A), Color(0xFF0E1B30)], stops: [0, 0.45, 1]),
            border: Border.all(color: const Color(0xFF234071)),
          ),
          child: Column(children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: CustomPaint(painter: _Ring(level.progress))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(levelEmoji[level.tier], style: const TextStyle(fontSize: 30)),
                  SizedBox(
                    width: 130,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFB8862B), Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFFFF3C9)]).createShader(r),
                        child: Text(levelName(level, lang).replaceFirst('${levelEmoji[level.tier]} ', ''), style: Tx.score(34, Colors.white, w: FontWeight.w800)),
                      ),
                    ),
                  ),
                  Text(context.tr('level_n', {'n': level.number + 1}), style: Tx.label(const Color(0xFFA9B6C9))),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$xp', style: Tx.score(28, Colors.white, w: FontWeight.w800)),
                TextSpan(text: level.isMax ? '  XP' : '  / ${level.nextAt} XP', style: Tx.small(const Color(0xFFA9B6C9))),
              ])),
            ),
            const SizedBox(height: 4),
            Text(
              level.isMax ? context.tr('level_max') : context.tr('xp_to_tier', {'n': level.toNext, 't': '${context.tr('tier_${levelTiers[level.nextTier]}')} ${levelEmoji[level.nextTier]}'}),
              textAlign: TextAlign.center,
              style: Tx.small(const Color(0xFFA9B6C9)),
            ),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x242BD38A), borderRadius: BorderRadius.circular(99)),
                child: Text('▲ ${context.tr('xp_this_week', {'n': weekXp})}', style: Tx.label(const Color(0xFF2BD38A), w: FontWeight.w800)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: Space.l),
        Row(children: [
          for (var i = 0; i < levelTiers.length; i++)
            Expanded(
              child: Column(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: i == level.tier ? const LinearGradient(colors: [Color(0xFFFFE7A3), Color(0xFFF4C247)]) : null,
                    color: i == level.tier ? null : (i < level.tier ? const Color(0x29FFC94A) : p.raised),
                    border: Border.all(color: i <= level.tier ? const Color(0x66FFC94A) : p.line),
                    boxShadow: i == level.tier ? const [BoxShadow(color: Color(0x59FFC94A), blurRadius: 16)] : null,
                  ),
                  child: Opacity(opacity: i <= level.tier ? 1 : 0.45, child: Text(levelEmoji[i], style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(context.tr('tier_${levelTiers[i]}'), style: Tx.label(i == level.tier ? p.goldText : (i < level.tier ? p.text : p.text2), w: FontWeight.w800)),
                ),
              ]),
            ),
        ]),
        SectionHeader(context.tr('how_xp')),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(children: [
            for (final (i, r) in xpRules.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
                child: Row(children: [
                  SizedBox(width: 28, child: Text(earned[math.min(i, earned.length - 1)].$1, style: const TextStyle(fontSize: 17))),
                  Expanded(child: Text(context.tr(r.key), style: Tx.small(p.text, w: FontWeight.w700))),
                  Text('+${r.xp} XP', style: Tx.small(p.goldText, w: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
        SectionHeader(context.tr('your_xp')),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(children: [
            for (final (i, e) in earned.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
                child: Row(children: [
                  SizedBox(width: 28, child: Text(e.$1, style: const TextStyle(fontSize: 17))),
                  Expanded(child: Text(e.$2, style: Tx.small(p.text2, w: FontWeight.w700))),
                  Text('${e.$3} XP', style: Tx.small(p.text, w: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 10);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white10);
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * math.max(0.02, progress),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFF97316), Color(0xFFFFE7A3)]).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress;
}
