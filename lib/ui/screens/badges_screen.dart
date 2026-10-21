// Badges: earned from your matches, shareable as a picture.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../scoring/badges.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'share_card.dart';

String _matchText(BuildContext context, EarnedBadge b) {
  final m = b.match;
  if (m == null) return '';
  final vs = m.me?['team'] == m.teamA.id ? m.teamB.name : m.teamA.name;
  return [if (b.detail.isNotEmpty) b.detail, if (vs.isNotEmpty) '${context.tr('vs')} $vs', dayText(context, DateTime.fromMillisecondsSinceEpoch(m.updated))].join(' · ');
}

Future<void> shareBadge(BuildContext context, EarnedBadge b, String player) {
  final name = context.tr('badge_${b.def.id}');
  return sharePicture(
    context,
    title: context.tr('share_badge'),
    fileName: 'gullyscore-badge-${b.def.id}',
    text: context.tr('badge_share_text', {'name': player, 'badge': name}),
    child: BadgeImage(badge: b, player: player),
  );
}

class BadgeImage extends StatelessWidget {
  const BadgeImage({super.key, required this.badge, required this.player});
  final EarnedBadge badge;
  final String player;

  @override
  Widget build(BuildContext context) {
    final c = Color(badge.def.color);
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.35), radius: 1.1, colors: [Color(0xFF2B4F8A), Color(0xFF0B1628)]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(context.tr('badge_unlocked').toUpperCase(), style: Tx.label(const Color(0xFFFFC94A), w: FontWeight.w800).copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Container(
          width: 120,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color.lerp(c, Colors.white, 0.45)!, c]),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: 40)],
          ),
          child: Text(badge.def.emoji, style: const TextStyle(fontSize: 60)),
        ),
        const SizedBox(height: 16),
        Text(context.tr('badge_${badge.def.id}'), textAlign: TextAlign.center, style: Tx.title(Colors.white).copyWith(fontSize: 26)),
        const SizedBox(height: 4),
        Text(player, textAlign: TextAlign.center, style: Tx.body(const Color(0xFFDCE4F0), w: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(_matchText(context, badge), textAlign: TextAlign.center, style: Tx.small(const Color(0xFFA9B6C9), w: FontWeight.w600)),
        const SizedBox(height: 18),
        Text('GullyScore', style: Tx.score(18, const Color(0xFFFFC94A), w: FontWeight.w800)),
      ]),
    );
  }
}

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key, required this.me});
  final MeInfo me;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final earned = earnedBadges(me.matches);
    final byId = {for (final b in earned) b.def.id: b};
    final player = me.profiles.where((x) => x.approved).map((x) => x.name).firstOrNull ?? me.name;
    final newest = earned.isEmpty ? null : earned.last;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('my_badges'), style: Tx.title(p.text).copyWith(fontSize: 20))),
            ]),
          ),
          if (newest != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Corners.hero),
                child: Column(children: [
                  FittedBox(fit: BoxFit.scaleDown, child: BadgeImage(badge: newest, player: player)),
                  Container(
                    color: const Color(0xFF0B1628),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: GoldButton(label: context.tr('share_badge'), icon: Icons.share_rounded, onPressed: () => shareBadge(context, newest, player)),
                  ),
                ]),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: AppCard(child: Text(context.tr('no_badges_yet'), style: Tx.small(p.text2))),
            ),
          SectionHeader(context.tr('badges_n', {'n': earned.length, 'm': badgeDefs.length})),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth < 330 ? 2 : 3;
              final w = (c.maxWidth - (cols - 1) * Space.s) / cols;
              return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final d in badgeDefs)
                  SizedBox(
                    width: w,
                    child: _BadgeTile(def: d, earned: byId[d.id], onTap: byId[d.id] == null ? null : () => shareBadge(context, byId[d.id]!, player)),
                  ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.def, required this.earned, required this.onTap});
  final BadgeDef def;
  final EarnedBadge? earned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = Color(def.color);
    final on = earned != null;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Opacity(
        opacity: on ? 1 : 0.4,
        child: Column(children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.withValues(alpha: 0.22) : p.raised),
            child: Text(on ? def.emoji : '🔒', style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(height: 6),
          Text(context.tr('badge_${def.id}'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
          Text(
            on ? (earned!.match == null ? '' : dayText(context, DateTime.fromMillisecondsSinceEpoch(earned!.match!.updated))) : context.tr('badge_${def.id}_how'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Tx.label(p.text2, w: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}
