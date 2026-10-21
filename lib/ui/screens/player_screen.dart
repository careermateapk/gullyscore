// Player profile: career numbers from matches scored on this phone.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../scoring/engine.dart';
import '../../scoring/stats.dart';
import '../widgets/common.dart';
import '../widgets/ground_map.dart';
import 'match_centre_screen.dart';
import 'online.dart';
import '../widgets/avatar.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.playerId});
  final String playerId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int _tab = 0; // 0 batting, 1 bowling

  Future<void> _rename() async {
    final repo = context.repo;
    final pl = repo.players[widget.playerId];
    if (pl == null) return;
    final ctrl = TextEditingController(text: pl.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('edit_name')),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null) repo.updatePlayer(pl, name: name);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final pl = repo.players[widget.playerId];
        final team = repo.teams.values.where((t) => t.playerIds.contains(widget.playerId)).firstOrNull;
        final matches = repo.matchList.where((m) => m.playersA.contains(widget.playerId) || m.playersB.contains(widget.playerId)).toList();
        final statList = [for (final m in matches) StatMatch(id: m.id, teamIds: [m.teamA, m.teamB], state: m.state)];
        final s = playerStats(widget.playerId, statList);

        // Recent innings, newest first.
        final recent = <(String, BatterCard)>[];
        final allBalls = <BallLog>[];
        for (final sm in statList) {
          for (final inn in sm.state.innings) {
            allBalls.addAll(inn.balls);
            final c = inn.batters[widget.playerId];
            if (c != null) recent.add((sm.id, c));
          }
        }
        final last8 = recent.take(8).toList().reversed.toList();
        final maxRuns = last8.fold<int>(1, (a, e) => e.$2.runs > a ? e.$2.runs : a);
        final shots = wagonShots(allBalls, widget.playerId);

        if (pl == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: p.bg),
            body: Center(child: EmptyState(icon: Icons.person_off_outlined, title: context.tr('player_not_found'), body: context.tr('match_not_found_body'))),
          );
        }

        Widget kv(String label, String value) => Expanded(
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Tx.score(24, p.text, w: FontWeight.w800))),
                ]),
              ),
            );

        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl), children: [
              Row(children: [
                IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                const Spacer(),
                IconBtn(icon: Icons.edit_outlined, tooltip: context.tr('edit_name'), onPressed: _rename),
              ]),
              const SizedBox(height: Space.m),
              HeroCard(
                glow: Palette.team(team?.colorIndex ?? 0),
                child: Row(children: [
                  EditableAvatar(playerId: pl.id, size: 72, color: Palette.team(team?.colorIndex ?? 0)),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pl.name, style: Tx.title(p.text).copyWith(fontSize: 22)),
                      if (team != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Crest(logo: team.logo, color: Palette.team(team.colorIndex), size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2))),
                        ]),
                      ],
                      const SizedBox(height: Space.s),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Pressable(
                          onTap: () => repo.updatePlayer(pl, leftHanded: !pl.leftHanded),
                          semanticLabel: context.tr('change_batting_hand'),
                          child: Tag(pl.leftHanded ? context.tr('left_hand_bat') : context.tr('right_hand_bat')),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
              if (context.sync.enabled && !pl.remote) ...[
                const SizedBox(height: Space.m),
                OutlineBtn(
                  label: context.tr('invite_player', {'name': pl.name}),
                  icon: Icons.send_to_mobile_rounded,
                  height: 48,
                  onPressed: () => invitePlayer(context, pl),
                ),
              ],
              const SizedBox(height: Space.m),
              Row(children: [
                kv(context.tr('matches'), '${s.matches}'),
                const SizedBox(width: Space.s),
                kv(context.tr('runs'), '${s.runs}'),
                const SizedBox(width: Space.s),
                kv(context.tr('average'), s.innings == 0 ? '-' : s.average.toStringAsFixed(1)),
                const SizedBox(width: Space.s),
                kv(context.tr('sr'), s.balls == 0 ? '-' : s.strikeRate.toStringAsFixed(1)),
              ]),
              const SizedBox(height: Space.m),
              Segmented<int>(values: const [0, 1], labels: [context.tr('batting'), context.tr('bowling')], selected: _tab, onChanged: (v) => setState(() => _tab = v)),
              const SizedBox(height: Space.m),
              if (_tab == 0) ...[
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(context.tr('last_innings_n', {'n': last8.length}), style: Tx.small(p.text, w: FontWeight.w800))),
                      Text(context.tr('runs'), style: Tx.label(p.text2)),
                    ]),
                    const SizedBox(height: Space.m),
                    if (last8.isEmpty)
                      Text(context.tr('no_innings_yet'), style: Tx.small(p.text2))
                    else
                      SizedBox(
                        height: 120,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          for (var i = 0; i < last8.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Container(
                                    height: 4 + 86 * last8[i].$2.runs / maxRuns,
                                    decoration: BoxDecoration(
                                      color: i == last8.length - 1 ? p.gold : (p.dark ? const Color(0xFF2B4268) : const Color(0xFFC9D3E3)),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('${last8[i].$2.runs}${last8[i].$2.out ? '' : '*'}',
                                      style: Tx.label(i == last8.length - 1 ? p.goldText : p.text2, w: FontWeight.w800)),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: Space.s),
                Row(children: [
                  kv(context.tr('highest'), s.highestText),
                  const SizedBox(width: Space.s),
                  kv('50s', '${s.fifties}'),
                  const SizedBox(width: Space.s),
                  kv(context.tr('fours'), '${s.fours}'),
                  const SizedBox(width: Space.s),
                  kv(context.tr('sixes'), '${s.sixes}'),
                ]),
                if (shots.isNotEmpty) ...[
                  SectionHeader(context.tr('wagon_wheel')),
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(painter: GroundPainter(palette: p, lang: context.settings.lang, shots: shots, leftHanded: pl.leftHanded, showLabels: false)),
                  ),
                ],
                SectionHeader(context.tr('recent')),
                for (final r in recent.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: r.$1))),
                      child: Row(children: [
                        Expanded(
                          child: Builder(builder: (_) {
                            final m = repo.matches[r.$1];
                            final opp = m == null ? '' : (m.playersA.contains(widget.playerId) ? repo.teamName(m.teamB) : repo.teamName(m.teamA));
                            return Text(context.tr('vs_team', {'team': opp}), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w700));
                          }),
                        ),
                        Text('${r.$2.runs}${r.$2.out ? '' : '*'}', style: Tx.score(18, p.text, w: FontWeight.w800)),
                        Text(' (${r.$2.balls})', style: Tx.label(p.text2)),
                      ]),
                    ),
                  ),
              ] else ...[
                Row(children: [
                  kv(context.tr('wickets'), '${s.wickets}'),
                  const SizedBox(width: Space.s),
                  kv(context.tr('best'), s.best),
                  const SizedBox(width: Space.s),
                  kv(context.tr('econ'), s.ballsBowled == 0 ? '-' : s.economy.toStringAsFixed(2)),
                ]),
                const SizedBox(height: Space.s),
                Row(children: [
                  kv(context.tr('overs'), oversText(s.ballsBowled)),
                  const SizedBox(width: Space.s),
                  kv(context.tr('catches'), '${s.catches}'),
                  const SizedBox(width: Space.s),
                  kv(context.tr('run_outs'), '${s.runOuts}'),
                ]),
              ],
              const SizedBox(height: Space.l),
              Text(context.tr('stats_from_phone'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
            ]),
          ),
        );
      },
    );
  }
}
