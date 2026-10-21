// Shareable certificates: tournament champions and player of the match.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/tournament.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'share_card.dart';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

class CertificateCard extends StatelessWidget {
  const CertificateCard({
    super.key,
    required this.kicker,
    required this.name,
    required this.line,
    required this.detail,
    required this.date,
    this.badge,
  });

  final String kicker; // e.g. "Champions"
  final String name; // team or player
  final String line; // e.g. tournament name
  final String detail; // e.g. figures
  final String date;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    const p = Palette.darkP;
    const gold = Color(0xFFFFC94A);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corners.hero),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF17325A), Color(0xFF070F1E)]),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corners.card),
            border: Border.all(color: gold.withValues(alpha: 0.7), width: 1.5),
          ),
          child: Column(children: [
            const Icon(Icons.workspace_premium_rounded, color: gold, size: 40),
            const SizedBox(height: Space.s),
            Text(kicker.toUpperCase(), textAlign: TextAlign.center, style: Tx.label(gold, w: FontWeight.w800).copyWith(letterSpacing: 2)),
            const Spacer(),
            if (badge != null) badge!,
            const SizedBox(height: Space.m),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name, textAlign: TextAlign.center, style: Tx.score(40, p.text)),
            ),
            const SizedBox(height: Space.s),
            Text(line, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w700)),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(detail, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2)),
            ],
            const Spacer(),
            Container(height: 1, color: gold.withValues(alpha: 0.4)),
            const SizedBox(height: Space.s),
            Row(children: [
              Text(date, style: Tx.label(p.text2)),
              const Spacer(),
              Text('GullyScore', style: Tx.score(16, gold, w: FontWeight.w800)),
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<void> shareChampionCertificate(BuildContext context, Tournament t, String teamId) {
  final repo = context.repo;
  final team = repo.teams[teamId];
  final name = repo.teamName(teamId);
  return sharePicture(
    context,
    title: context.tr('champion_certificate'),
    fileName: 'champions-${t.id}',
    text: context.tr('champions_share_text', {'team': name, 't': t.name}),
    child: CertificateCard(
      kicker: context.tr('champions'),
      name: name,
      line: t.name,
      detail: context.tr('players_n', {'n': team?.playerIds.length ?? 0}),
      date: _date(DateTime.now()),
      badge: Crest(logo: team?.logo, color: Palette.team(team?.colorIndex ?? 0), text: team?.short ?? '', size: 64),
    ),
  );
}

Future<void> shareMomCertificate(BuildContext context, MatchRecord m) async {
  final repo = context.repo;
  final st = m.state;
  final id = playerOfMatch(st);
  if (id == null) return;
  final parts = <String>[];
  for (final inn in st.innings) {
    final b = inn.batters[id];
    if (b != null && (b.runs > 0 || b.balls > 0)) parts.add('${b.runs}${b.out ? '' : '*'} (${b.balls})');
    final w = inn.bowlers[id];
    if (w != null && w.balls > 0) parts.add('${w.wickets}/${w.runs} (${w.overs})');
  }
  final line = '${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}';
  await sharePicture(
    context,
    title: context.tr('mom_certificate'),
    fileName: 'mom-${m.id}',
    text: context.tr('mom_share_text', {'name': repo.playerName(id), 'm': line}),
    child: CertificateCard(
      kicker: context.tr('player_of_match'),
      name: repo.playerName(id),
      line: m.title.isEmpty ? line : '$line\n${m.title}',
      detail: parts.join(' · '),
      date: _date(m.updatedAt),
      badge: PlayerAvatar(playerId: id, size: 72, ring: const Color(0xFFFFC94A)),
    ),
  );
}
