// Series: matches that share a name (e.g. "MPL 2026") get a points table
// and leaders. Teams are managed here too.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/stats.dart';
import '../widgets/common.dart';
import 'help.dart';
import 'player_screen.dart';
import 'team_screen.dart';
import 'tournament_screens.dart';
import '../widgets/avatar.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  String? _series; // null = all matches

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final all = repo.matchList;
        final titles = {for (final m in all) if (m.title.isNotEmpty) m.title}.toList()..sort();
        if (_series != null && !titles.contains(_series)) _series = null;
        final chosen = all.where((m) => _series == null || m.title == _series).toList();
        final statMatches = [for (final m in chosen) StatMatch(id: m.id, teamIds: [m.teamA, m.teamB], state: m.state)];
        final finished = statMatches.where((s) => s.state.finished).toList();
        final teamIds = {for (final m in chosen) ...[m.teamA, m.teamB]}.toList();
        final table = _series == null ? <PointsRow>[] : pointsTable(teamIds, finished);
        final runs = topRunScorers(statMatches, limit: 5);
        final wkts = topWicketTakers(statMatches, limit: 5);

        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
              child: Row(children: [
                Expanded(child: Semantics(header: true, child: Text(context.tr('nav_series'), style: Tx.title(p.text)))),
                IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'series')),
              ]),
            ),
            const TournamentsSection(),
            SectionHeader(context.tr('all_match_stats')),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0), children: [
                ChoiceChipX(label: context.tr('all_matches'), selected: _series == null, onTap: () => setState(() => _series = null)),
                for (final t in titles) ...[
                  const SizedBox(width: Space.s),
                  ChoiceChipX(label: t, icon: Icons.emoji_events_rounded, selected: _series == t, onTap: () => setState(() => _series = t)),
                ],
              ]),
            ),
            if (titles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
                child: AppCard(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.emoji_events_outlined, color: p.goldText),
                    const SizedBox(width: Space.m),
                    Expanded(child: Text(context.tr('series_how'), style: Tx.small(p.text2))),
                  ]),
                ),
              ),
            if (_series != null) ...[
              SectionHeader(context.tr('points_table')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: table.isEmpty || finished.isEmpty
                      ? Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(context.tr('table_after_first_result'), style: Tx.small(p.text2)))
                      : PointsTableView(rows: table),
                ),
              ),
            ],
            SectionHeader(context.tr('most_runs')),
            _Leaders(leaders: runs, empty: context.tr('no_runs_yet'), detailKey: 'balls_n'),
            SectionHeader(context.tr('most_wickets')),
            _Leaders(leaders: wkts, empty: context.tr('no_wickets_yet'), detailKey: 'runs_n'),
            SectionHeader(context.tr('teams'), action: context.tr('new_team'), onAction: () => openTeamEditor(context)),
            if (repo.teams.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: Space.edge), child: Text(context.tr('no_teams_yet'), style: Tx.small(p.text2)))
            else
              for (final t in repo.teamList)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                  child: _TeamRow(team: t),
                ),
          ]),
        );
      },
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});
  final Team team;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context).settings;
    final fav = s.favouriteTeams.contains(team.id);
    return AppCard(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      onTap: () => openTeamEditor(context, teamId: team.id),
      child: Row(children: [
        Crest(color: Palette.team(team.colorIndex), text: team.short, size: 30),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w700)),
            Text(context.tr('players_n', {'n': team.playerIds.length}), style: Tx.label(p.text2)),
          ]),
        ),
        IconButton(
          tooltip: fav ? context.tr('unfollow') : context.tr('follow'),
          onPressed: () => s.toggleFavourite(team.id),
          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: fav ? p.goldText : p.text2),
        ),
      ]),
    );
  }
}

class PointsTableView extends StatelessWidget {
  const PointsTableView({required this.rows});
  final List<PointsRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final h = Tx.label(p.text2);
    final c = Tx.small(p.text, w: FontWeight.w500).copyWith(fontSize: 14);
    Widget cells(List<Widget> w) => Row(children: w);
    return Column(children: [
      cells([
        SizedBox(width: 20, child: Text('#', style: h)),
        Expanded(child: Text(context.tr('team'), style: h)),
        SizedBox(width: 26, child: Text('P', textAlign: TextAlign.right, style: h)),
        SizedBox(width: 26, child: Text('W', textAlign: TextAlign.right, style: h)),
        SizedBox(width: 26, child: Text('L', textAlign: TextAlign.right, style: h)),
        SizedBox(width: 54, child: Text('NRR', textAlign: TextAlign.right, style: h)),
        SizedBox(width: 34, child: Text(context.tr('pts'), textAlign: TextAlign.right, style: h)),
      ]),
      const SizedBox(height: 6),
      for (var i = 0; i < rows.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          child: cells([
            SizedBox(width: 20, child: Text('${i + 1}', style: c.copyWith(color: p.text2))),
            Expanded(
              child: Row(children: [
                Crest(color: Palette.team(repo.teams[rows[i].teamId]?.colorIndex ?? 0), size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(repo.teamName(rows[i].teamId), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.copyWith(fontWeight: FontWeight.w800))),
              ]),
            ),
            SizedBox(width: 26, child: Text('${rows[i].played}', textAlign: TextAlign.right, style: c)),
            SizedBox(width: 26, child: Text('${rows[i].won}', textAlign: TextAlign.right, style: c)),
            SizedBox(width: 26, child: Text('${rows[i].lost}', textAlign: TextAlign.right, style: c)),
            SizedBox(
              width: 54,
              child: Text('${rows[i].nrr >= 0 ? '+' : '−'}${rows[i].nrr.abs().toStringAsFixed(2)}', textAlign: TextAlign.right, style: c.copyWith(color: p.text2)),
            ),
            SizedBox(width: 34, child: Text('${rows[i].points}', textAlign: TextAlign.right, style: Tx.score(18, p.text, w: FontWeight.w800))),
          ]),
        ),
    ]);
  }
}

class _Leaders extends StatelessWidget {
  const _Leaders({required this.leaders, required this.empty, required this.detailKey});
  final List<Leader> leaders;
  final String empty;
  final String detailKey;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    if (leaders.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: Space.edge), child: Text(empty, style: Tx.small(p.text2)));
    }
    final max = leaders.first.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.edge),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < leaders.length; i++)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: leaders[i].playerId))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: Tx.label(p.text2))),
                  PlayerAvatar(playerId: leaders[i].playerId, size: 32),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(repo.playerName(leaders[i].playerId), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800).copyWith(fontSize: 14)),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(value: leaders[i].value / (max == 0 ? 1 : max), minHeight: 5, backgroundColor: p.raised, color: i == 0 ? p.gold : p.text2),
                      ),
                    ]),
                  ),
                  const SizedBox(width: Space.m),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${leaders[i].value}', style: Tx.score(22, p.text, w: FontWeight.w800)),
                    Text(context.tr(detailKey, {'n': leaders[i].detail}), style: Tx.label(p.text2, w: FontWeight.w500)),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
