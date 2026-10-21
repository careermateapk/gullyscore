// Match centre: score, scorecard, commentary, squads and stats for one match.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/commentary.dart';
import '../../scoring/engine.dart';
import '../../scoring/format.dart';
import '../../scoring/predictor.dart';
import '../widgets/common.dart';
import '../widgets/ground_map.dart';
import 'help.dart';
import 'player_screen.dart';
import 'scoring_screen.dart';
import 'share_card.dart';

/// How a match should be labelled right now. Only a match being scored on
/// this phone in the last 30 minutes is called live.
enum MatchStatus { live, paused, notStarted, finished }

MatchStatus statusOf(MatchRecord m, MatchState st) {
  if (st.finished) return MatchStatus.finished;
  if (st.innings.isEmpty) return MatchStatus.notStarted;
  if (DateTime.now().difference(m.updatedAt).inMinutes < 30) return MatchStatus.live;
  return MatchStatus.paused;
}

String agoText(BuildContext context, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return context.tr('just_now');
  if (d.inMinutes < 60) return context.tr('min_ago', {'n': d.inMinutes});
  if (d.inHours < 24) return context.tr('hours_ago', {'n': d.inHours});
  return context.tr('days_ago', {'n': d.inDays});
}

class MatchCentreScreen extends StatelessWidget {
  const MatchCentreScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final p = Palette.of(context);
        final m = repo.matches[matchId];
        if (m == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: p.bg),
            body: Center(child: EmptyState(icon: Icons.search_off_rounded, title: context.tr('match_not_found'), body: context.tr('match_not_found_body'))),
          );
        }
        final st = m.state;
        String name(String id) => repo.playerName(id);
        final status = statusOf(m, st);
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            backgroundColor: p.bg,
            floatingActionButton: status == MatchStatus.finished
                ? null
                : FloatingActionButton.extended(
                    backgroundColor: p.gold,
                    foregroundColor: const Color(0xFF0B1220),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.button)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id))),
                    icon: const Icon(Icons.edit_rounded),
                    label: Text(context.tr('continue_scoring'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
            body: SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
                      child: Row(children: [
                        IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${repo.teams[m.teamA]?.short ?? ''} vs ${repo.teams[m.teamB]?.short ?? ''}',
                                style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
                            Text([if (m.title.isNotEmpty) m.title, if (m.venue.isNotEmpty) m.venue, context.tr('overs_match', {'n': m.overs})].join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                          ]),
                        ),
                        IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'match_centre')),
                        const SizedBox(width: Space.s),
                        IconBtn(icon: Icons.ios_share_rounded, tooltip: context.tr('share_score'), onPressed: () => shareMatchCard(context, m)),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                      child: _Hero(m: m, st: st, status: status),
                    ),
                  ),
                  SliverPersistentHeader(pinned: true, delegate: _TabsHeader(p)),
                ],
                body: TabBarView(children: [
                  _SummaryTab(m: m, st: st, name: name),
                  _ScorecardTab(m: m, st: st, name: name),
                  _CommentaryTab(m: m, st: st, name: name),
                  _SquadsTab(m: m),
                  _StatsTab(m: m, st: st, name: name),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.p);
  final Palette p;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: p.bg,
      padding: const EdgeInsets.only(top: 4),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        labelColor: p.text,
        unselectedLabelColor: p.text2,
        indicatorColor: p.gold,
        indicatorWeight: 2,
        dividerColor: p.line,
        labelStyle: const TextStyle(fontFamily: 'Hanken', fontFamilyFallback: ['NotoDeva'], fontWeight: FontWeight.w700, fontSize: 14),
        tabs: [
          Tab(text: context.tr('tab_summary')),
          Tab(text: context.tr('tab_scorecard')),
          Tab(text: context.tr('tab_commentary')),
          Tab(text: context.tr('tab_squads')),
          Tab(text: context.tr('tab_stats')),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) => old.p != p;
}

// ------------------------------------------------------------ hero

class _Hero extends StatelessWidget {
  const _Hero({required this.m, required this.st, required this.status});
  final MatchRecord m;
  final MatchState st;
  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final inn = st.current;
    final mainTeam = inn?.battingTeam ?? m.firstBatting;
    final other = 1 - mainTeam;
    Team? team(int i) => repo.teams[i == 0 ? m.teamA : m.teamB];
    Innings? innOf(int t) {
      for (final i in st.innings) {
        if (i.battingTeam == t) return i;
      }
      return null;
    }

    final mainInn = innOf(mainTeam);
    final otherInn = innOf(other);

    Widget badge;
    switch (status) {
      case MatchStatus.live:
        badge = LiveBadge(label: context.tr('live'));
      case MatchStatus.paused:
        badge = Tag(context.tr('last_ball_ago', {'t': agoText(context, m.updatedAt)}), color: p.goldText, background: p.gold.withValues(alpha: 0.14));
      case MatchStatus.notStarted:
        badge = Tag(context.tr('not_started'));
      case MatchStatus.finished:
        badge = Tag(context.tr('result'), color: p.win, background: p.win.withValues(alpha: 0.14));
    }

    String statusText;
    if (st.finished) {
      statusText = st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB));
    } else if (inn != null && inn.number == 1 && !inn.ended) {
      statusText = context.tr('team_need_runs', {'team': team(inn.battingTeam)?.short ?? '', 'n': st.runsNeeded ?? 0, 'b': st.ballsLeft ?? 0});
    } else if (inn != null && inn.ended && st.innings.length == 1) {
      statusText = context.tr('innings_break_need', {'team': team(1 - inn.battingTeam)?.short ?? '', 'n': inn.runs + 1});
    } else if (st.innings.isEmpty) {
      statusText = m.tossText.isEmpty ? context.tr('match_not_started_body') : m.tossText;
    } else {
      statusText = m.tossText.isEmpty ? context.tr('first_innings') : m.tossText;
    }

    final stats = <(String, String)>[];
    if (inn != null) {
      stats.add((context.tr('crr'), inn.runRate.toStringAsFixed(2)));
      if (inn.number == 1 && !st.finished) {
        final need = st.runsNeeded ?? 0;
        final balls = st.ballsLeft ?? 0;
        stats.add((context.tr('rrr'), balls > 0 ? (need * 6 / balls).toStringAsFixed(2) : '-'));
        stats.add((context.tr('target'), '${st.target ?? '-'}'));
      } else {
        stats.add((context.tr('extras'), '${inn.extras.total}'));
        stats.add((context.tr('overs'), '${inn.overs}/${m.overs}'));
      }
      if (!inn.ended) stats.add((context.tr('pship'), '${inn.partnershipRuns} (${inn.partnershipBalls})'));
    }

    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          badge,
          const Spacer(),
          if (status != MatchStatus.notStarted) Text(context.tr('updated_ago', {'t': agoText(context, m.updatedAt)}), style: Tx.label(p.text2)),
        ]),
        const SizedBox(height: Space.m),
        Row(children: [
          Crest(color: Palette.team(team(mainTeam)?.colorIndex ?? 0), text: team(mainTeam)?.short ?? '', size: 40),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team(mainTeam)?.name ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
              if (inn != null && !inn.ended && !st.finished) Text(context.tr('batting'), style: Tx.label(p.text2)),
            ]),
          ),
          if (mainInn != null) ...[
            const SizedBox(width: Space.s),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  AnimatedScore(text: '${mainInn.runs}/${mainInn.wickets}', style: Tx.score(52, p.text)),
                  const SizedBox(height: 2),
                  Text(context.tr('overs_of', {'o': mainInn.overs, 'n': m.overs}), style: Tx.score(17, p.text2, w: FontWeight.w700)),
                ]),
              ),
            ),
          ],
        ]),
        Container(height: 1, color: p.line, margin: const EdgeInsets.symmetric(vertical: Space.m)),
        Row(children: [
          Crest(color: Palette.team(team(other)?.colorIndex ?? 0), text: team(other)?.short ?? '', size: 28),
          const SizedBox(width: Space.m),
          Expanded(child: Text(team(other)?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text2, w: FontWeight.w700).copyWith(fontSize: 14))),
          const SizedBox(width: Space.s),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(otherInn == null ? context.tr('yet_to_bat') : '${otherInn.runs}/${otherInn.wickets} (${otherInn.overs})',
                  style: otherInn == null ? Tx.small(p.text2) : Tx.score(20, p.text2, w: FontWeight.w800)),
            ),
          ),
        ]),
        const SizedBox(height: Space.m),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Text(statusText, style: Tx.body(p.goldText, w: FontWeight.w800).copyWith(fontSize: 14)),
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Row(children: [
            for (final s in stats)
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.$1, style: Tx.label(p.text2)),
                  const SizedBox(height: 3),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(s.$2, style: Tx.score(20, p.text, w: FontWeight.w800))),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------ summary

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.m, required this.st, required this.name});
  final MatchRecord m;
  final MatchState st;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final inn = st.current;
    if (inn == null) {
      return ListView(children: [
        EmptyState(icon: Icons.sports_cricket_rounded, title: context.tr('not_started'), body: context.tr('match_not_started_body')),
      ]);
    }
    final chance = winChance(st);
    final lastWicket = inn.balls.lastWhere((b) => b.isWicket, orElse: () => BallLog('', false, 0));
    final over = inn.legalBalls ~/ 6;
    final thisOver = inn.balls.where((b) => b.over == over).toList();
    final prevOver = inn.balls.where((b) => b.over == over - 1).toList();
    final teamName = context.repo.teams[inn.battingTeam == 0 ? m.teamA : m.teamB]?.short ?? '';
    final chaseTeam = chance == null ? '' : (context.repo.teams[chance.chasingTeam == 0 ? m.teamA : m.teamB]?.short ?? '');
    final defendTeam = chance == null ? '' : (context.repo.teams[chance.chasingTeam == 0 ? m.teamB : m.teamA]?.short ?? '');

    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 96), children: [
      if (!inn.ended)
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(children: [
            _BatHeader(label: context.tr('batter')),
            for (final id in [inn.striker, inn.nonStriker])
              if (id != null && inn.batters[id] != null) _BatRow(card: inn.batters[id]!, name: name(id), strike: id == inn.striker, showHowOut: false),
            if (inn.bowler != null && inn.bowlers[inn.bowler] != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${context.tr('bowling')} ', style: Tx.label(p.text2)),
                        TextSpan(text: name(inn.bowler!), style: Tx.small(p.text, w: FontWeight.w800)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Builder(builder: (_) {
                        final b = inn.bowlers[inn.bowler]!;
                        return Text('${b.overs}-${b.maidens}-${b.runs}-${b.wickets}', style: Tx.score(17, p.text, w: FontWeight.w800));
                      }),
                    ),
                  ),
                ]),
              ),
          ]),
        )
      else
        AppCard(child: Text(context.tr('innings_complete', {'team': teamName, 'score': '${inn.runs}/${inn.wickets}', 'o': inn.overs}), style: Tx.body(p.text, w: FontWeight.w700))),
      const SizedBox(height: Space.s),
      AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(context.tr('this_over_n', {'n': over + 1}), style: Tx.label(p.text2))),
            Text(context.tr('runs_n', {'n': thisOver.fold<int>(0, (a, b) => a + b.teamRuns)}), style: Tx.label(p.text2)),
          ]),
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final b in thisOver) Padding(padding: const EdgeInsets.only(right: 6), child: BallChip(b.label)),
                  if (thisOver.isEmpty) Text(context.tr('no_balls_yet'), style: Tx.small(p.text2)),
                ]),
              ),
            ),
            if (prevOver.isNotEmpty) ...[
              Container(width: 1, height: 22, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 8)),
              Flexible(child: Text('$over: ${prevOver.map((b) => b.label == '•' ? '0' : b.label).join(' ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2))),
            ],
          ]),
        ]),
      ),
      if (lastWicket.outPlayer != null) ...[
        const SizedBox(height: Space.s),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const BallChip('W', size: 32),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Builder(builder: (_) {
                  final c = inn.batters[lastWicket.outPlayer!];
                  return Text(
                    c == null ? name(lastWicket.outPlayer!) : '${name(c.id)} ${howOutText(c, name)} ${c.runs} (${c.balls})',
                    style: Tx.small(p.text, w: FontWeight.w700),
                  );
                }),
                Text(context.tr('last_wicket_at', {'s': '${lastWicket.scoreRuns}/${lastWicket.scoreWickets}', 'o': lastWicket.overBall}), style: Tx.label(p.text2)),
              ]),
            ),
          ]),
        ),
      ],
      if (chance != null) ...[
        const SizedBox(height: Space.s),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(context.tr('win_chance'), style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 14))),
              Tag(context.tr('for_fun_only')),
            ]),
            const SizedBox(height: Space.s),
            Row(children: [
              Text('$chaseTeam ${chance.chasingPercent}%', style: Tx.score(20, Palette.team(context.repo.teams[chance.chasingTeam == 0 ? m.teamA : m.teamB]?.colorIndex ?? 0))),
              const SizedBox(width: Space.s),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 8,
                    child: Row(children: [
                      Expanded(flex: chance.chasingPercent.clamp(1, 99), child: Container(color: Palette.team(context.repo.teams[chance.chasingTeam == 0 ? m.teamA : m.teamB]?.colorIndex ?? 0))),
                      const SizedBox(width: 3),
                      Expanded(flex: chance.defendingPercent.clamp(1, 99), child: Container(color: Palette.team(context.repo.teams[chance.chasingTeam == 0 ? m.teamB : m.teamA]?.colorIndex ?? 1))),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: Space.s),
              Text('$defendTeam ${chance.defendingPercent}%', style: Tx.score(20, Palette.team(context.repo.teams[chance.chasingTeam == 0 ? m.teamB : m.teamA]?.colorIndex ?? 1))),
            ]),
            const SizedBox(height: 6),
            Text(context.tr('win_chance_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
          ]),
        ),
      ],
    ]);
  }
}

class _BatHeader extends StatelessWidget {
  const _BatHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = Tx.label(p.text2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: s)),
        SizedBox(width: 34, child: Text('R', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 30, child: Text('B', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 26, child: Text('4s', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 26, child: Text('6s', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 50, child: Text('SR', textAlign: TextAlign.right, style: s)),
      ]),
    );
  }
}

class _BatRow extends StatelessWidget {
  const _BatRow({required this.card, required this.name, required this.strike, required this.showHowOut, this.howOut = ''});
  final BatterCard card;
  final String name;
  final bool strike;
  final bool showHowOut;
  final String howOut;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = Tx.small(p.text, w: FontWeight.w500).copyWith(fontSize: 14);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: Tx.small(p.text, w: FontWeight.w800).copyWith(fontSize: 14)),
                if (strike) TextSpan(text: ' *', style: Tx.small(p.goldText, w: FontWeight.w800)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showHowOut) Text(howOut, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w500)),
          ]),
        ),
        SizedBox(width: 34, child: Text('${card.runs}', textAlign: TextAlign.right, style: Tx.score(18, p.text, w: FontWeight.w800))),
        SizedBox(width: 30, child: Text('${card.balls}', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 26, child: Text('${card.fours}', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 26, child: Text('${card.sixes}', textAlign: TextAlign.right, style: s)),
        SizedBox(width: 50, child: Text(card.strikeRate.toStringAsFixed(1), textAlign: TextAlign.right, style: s.copyWith(color: p.text2))),
      ]),
    );
  }
}

// ------------------------------------------------------------ scorecard

class _InningsPicker extends StatelessWidget {
  const _InningsPicker({required this.m, required this.st, required this.selected, required this.onChanged});
  final MatchRecord m;
  final MatchState st;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final repo = context.repo;
    return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
      for (var i = 0; i < st.innings.length; i++)
        ChoiceChipX(
          label: '${repo.teams[st.innings[i].battingTeam == 0 ? m.teamA : m.teamB]?.short ?? ''} ${st.innings[i].runs}/${st.innings[i].wickets} (${st.innings[i].overs})',
          selected: selected == i,
          onTap: () => onChanged(i),
        ),
    ]);
  }
}

class _ScorecardTab extends StatefulWidget {
  const _ScorecardTab({required this.m, required this.st, required this.name});
  final MatchRecord m;
  final MatchState st;
  final String Function(String) name;

  @override
  State<_ScorecardTab> createState() => _ScorecardTabState();
}

class _ScorecardTabState extends State<_ScorecardTab> {
  int? _sel;
  bool _allBowlers = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final st = widget.st;
    final name = widget.name;
    if (st.innings.isEmpty) {
      return ListView(children: [EmptyState(icon: Icons.table_chart_outlined, title: context.tr('not_started'), body: context.tr('match_not_started_body'))]);
    }
    final idx = (_sel ?? st.innings.length - 1).clamp(0, st.innings.length - 1);
    final inn = st.innings[idx];
    final bowlers = inn.bowlingOrder;
    final shownBowlers = _allBowlers || bowlers.length <= 4 ? bowlers : bowlers.take(4).toList();
    final hs = Tx.label(p.text2);
    final cell = Tx.small(p.text, w: FontWeight.w500).copyWith(fontSize: 14);

    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 96), children: [
      _InningsPicker(m: widget.m, st: st, selected: idx, onChanged: (i) => setState(() => _sel = i)),
      const SizedBox(height: Space.m),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(children: [
          _BatHeader(label: context.tr('batting')),
          for (final id in inn.battingOrder)
            _BatRow(
              card: inn.batters[id]!,
              name: name(id),
              strike: !inn.ended && id == inn.striker,
              showHowOut: true,
              howOut: (!inn.batters[id]!.out && inn.batters[id]!.outKind != OutKind.retired)
                  ? (!inn.ended && (id == inn.striker || id == inn.nonStriker) ? context.tr('batting_now') : context.tr('not_out'))
                  : howOutText(inn.batters[id]!, name),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(child: Text('${context.tr('extras')} (wd ${inn.extras.wides}, nb ${inn.extras.noBalls}, b ${inn.extras.byes}, lb ${inn.extras.legByes})', style: Tx.small(p.text2))),
              Text('${inn.extras.total}', style: Tx.small(p.text, w: FontWeight.w800)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(child: Text(context.tr('total'), style: Tx.body(p.text, w: FontWeight.w800))),
              Flexible(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${inn.runs}/${inn.wickets}', style: Tx.score(22, p.text)),
                    const SizedBox(width: 6),
                    Text('(${inn.overs} ${context.tr('ov')}, RR ${inn.runRate.toStringAsFixed(2)})', style: Tx.small(p.text2)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
      if (inn.fallOfWickets.isNotEmpty) ...[
        const SizedBox(height: Space.s),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('fall_of_wickets'), style: Tx.small(p.text, w: FontWeight.w800)),
            const SizedBox(height: Space.s),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: inn.fallOfWickets.length,
                separatorBuilder: (c, i) => const SizedBox(width: Space.s),
                itemBuilder: (_, i) {
                  final f = inn.fallOfWickets[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${f.wicket}-${f.runs}', style: Tx.score(18, p.text, w: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${name(f.player)} · ${f.overs} ${context.tr('ov')}', style: Tx.label(p.text2, w: FontWeight.w600)),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: Space.s),
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(context.tr('bowling'), style: hs)),
            SizedBox(width: 34, child: Text('O', textAlign: TextAlign.right, style: hs)),
            SizedBox(width: 26, child: Text('M', textAlign: TextAlign.right, style: hs)),
            SizedBox(width: 32, child: Text('R', textAlign: TextAlign.right, style: hs)),
            SizedBox(width: 26, child: Text('W', textAlign: TextAlign.right, style: hs)),
            SizedBox(width: 48, child: Text(context.tr('econ'), textAlign: TextAlign.right, style: hs)),
          ]),
          const SizedBox(height: 6),
          for (final id in shownBowlers)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
              child: Row(children: [
                Expanded(child: Text(name(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800).copyWith(fontSize: 14))),
                SizedBox(width: 34, child: Text(inn.bowlers[id]!.overs, textAlign: TextAlign.right, style: cell)),
                SizedBox(width: 26, child: Text('${inn.bowlers[id]!.maidens}', textAlign: TextAlign.right, style: cell)),
                SizedBox(width: 32, child: Text('${inn.bowlers[id]!.runs}', textAlign: TextAlign.right, style: cell)),
                SizedBox(width: 26, child: Text('${inn.bowlers[id]!.wickets}', textAlign: TextAlign.right, style: Tx.score(18, p.goldText, w: FontWeight.w800))),
                SizedBox(width: 48, child: Text(inn.bowlers[id]!.economy.toStringAsFixed(2), textAlign: TextAlign.right, style: cell.copyWith(color: p.text2))),
              ]),
            ),
          if (bowlers.length > 4)
            TextButton(
              onPressed: () => setState(() => _allBowlers = !_allBowlers),
              style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(48, 44)),
              child: Text(_allBowlers ? context.tr('show_less') : context.tr('show_all_bowlers', {'n': bowlers.length})),
            ),
        ]),
      ),
      if (inn.partnerships.isNotEmpty || (!inn.ended && inn.partnershipBalls > 0)) ...[
        const SizedBox(height: Space.s),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('partnerships'), style: Tx.small(p.text, w: FontWeight.w800)),
            for (var i = 0; i < inn.partnerships.length; i++)
              _PartnershipRow(index: i + 1, a: name(inn.partnerships[i].a), b: name(inn.partnerships[i].b), runs: inn.partnerships[i].runs, balls: inn.partnerships[i].balls),
            if (!inn.ended && inn.striker != null && inn.nonStriker != null)
              _PartnershipRow(index: inn.partnerships.length + 1, a: name(inn.striker!), b: name(inn.nonStriker!), runs: inn.partnershipRuns, balls: inn.partnershipBalls, current: true),
          ]),
        ),
      ],
    ]);
  }
}

class _PartnershipRow extends StatelessWidget {
  const _PartnershipRow({required this.index, required this.a, required this.b, required this.runs, required this.balls, this.current = false});
  final int index;
  final String a;
  final String b;
  final int runs;
  final int balls;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        SizedBox(width: 22, child: Text('$index', style: Tx.label(p.text2))),
        Expanded(child: Text('$a & $b', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(current ? p.text : p.text2, w: FontWeight.w700))),
        const SizedBox(width: Space.s),
        Text('$runs ($balls)', style: Tx.score(17, current ? p.goldText : p.text, w: FontWeight.w800)),
      ]),
    );
  }
}

// ------------------------------------------------------------ commentary

class _CommentaryTab extends StatefulWidget {
  const _CommentaryTab({required this.m, required this.st, required this.name});
  final MatchRecord m;
  final MatchState st;
  final String Function(String) name;

  @override
  State<_CommentaryTab> createState() => _CommentaryTabState();
}

class _CommentaryTabState extends State<_CommentaryTab> {
  int? _sel;
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final st = widget.st;
    if (st.innings.isEmpty) {
      return ListView(children: [EmptyState(icon: Icons.chat_bubble_outline_rounded, title: context.tr('no_commentary'), body: context.tr('no_commentary_body'))]);
    }
    final idx = (_sel ?? st.innings.length - 1).clamp(0, st.innings.length - 1);
    final all = buildCommentary(st.innings[idx], widget.name, lang: context.settings.lang);
    final items = all.where((c) {
      switch (_filter) {
        case 'boundaries':
          return c.ball != null && (c.ball!.isFour || c.ball!.isSix);
        case 'wickets':
          return c.ball != null && c.ball!.isWicket;
        case 'overs':
          return c.type == CommType.overEnd;
      }
      return true;
    }).toList();

    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
        child: _InningsPicker(m: widget.m, st: st, selected: idx, onChanged: (i) => setState(() => _sel = i)),
      ),
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
          children: [
            for (final f in const ['all', 'boundaries', 'wickets', 'overs']) ...[
              ChoiceChipX(label: context.tr('filter_$f'), selected: _filter == f, onTap: () => setState(() => _filter = f)),
              const SizedBox(width: Space.s),
            ],
          ],
        ),
      ),
      const SizedBox(height: Space.s),
      if (items.isEmpty)
        EmptyState(icon: Icons.filter_alt_off_rounded, title: context.tr('nothing_here'), body: context.tr('nothing_here_filter'))
      else
        for (final c in items) c.type == CommType.overEnd ? _OverEndRow(item: c) : _BallRow(item: c),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Text(context.tr('commentary_source_note'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
        ),
    ]);
  }
}

class _BallRow extends StatelessWidget {
  const _BallRow({required this.item});
  final CommItem item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final b = item.ball!;
    final accent = b.isWicket ? p.live : (b.isFour || b.isSix ? (b.isSix ? p.six : p.gold) : null);
    return Container(
      padding: EdgeInsets.fromLTRB(accent == null ? Space.edge : Space.edge - 3, 12, Space.edge, 12),
      decoration: accent == null
          ? null
          : BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
              gradient: LinearGradient(colors: [accent.withValues(alpha: 0.10), accent.withValues(alpha: 0)], stops: const [0, 0.7]),
            ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 44,
          child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(b.overBall, style: Tx.score(17, p.text2, w: FontWeight.w800))),
        ),
        BallChip(b.label, size: 32),
        const SizedBox(width: Space.m),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: item.headline, style: Tx.small(p.text, w: accent != null ? FontWeight.w800 : FontWeight.w700).copyWith(fontSize: 14)),
            if (item.detail.isNotEmpty) TextSpan(text: ' ${item.detail}', style: Tx.small(p.text, w: FontWeight.w500).copyWith(fontSize: 14)),
          ])),
        ),
      ]),
    );
  }
}

class _OverEndRow extends StatelessWidget {
  const _OverEndRow({required this.item});
  final CommItem item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.edge, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(Corners.button)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.headline, style: Tx.score(17, p.text, w: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(item.scoreText, style: Tx.label(p.text2)),
          ]),
        ),
        Flexible(
          child: Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: [for (final l in item.overBalls) BallChip(l, size: 22)]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ squads

class _SquadsTab extends StatelessWidget {
  const _SquadsTab({required this.m});
  final MatchRecord m;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    Widget squad(String teamId, List<String> ids) {
      final t = repo.teams[teamId];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Crest(color: Palette.team(t?.colorIndex ?? 0), text: t?.short ?? '', size: 26),
          const SizedBox(width: Space.s),
          Expanded(child: Text(t?.name ?? '', style: Tx.section(p.text).copyWith(fontSize: 15))),
          Text(context.tr('players_n', {'n': ids.length}), style: Tx.label(p.text2)),
        ]),
        const SizedBox(height: Space.s),
        for (final id in ids)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: id))),
              child: Row(children: [
                Expanded(child: Text(repo.playerName(id), style: Tx.small(p.text, w: FontWeight.w700).copyWith(fontSize: 14))),
                if (repo.players[id]?.leftHanded ?? false) Tag(context.tr('lhb')),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: p.text2, size: 20),
              ]),
            ),
          ),
      ]);
    }

    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 96), children: [
      squad(m.teamA, m.playersA),
      const SizedBox(height: Space.l),
      squad(m.teamB, m.playersB),
    ]);
  }
}

// ------------------------------------------------------------ stats

class _StatsTab extends StatefulWidget {
  const _StatsTab({required this.m, required this.st, required this.name});
  final MatchRecord m;
  final MatchState st;
  final String Function(String) name;

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  String? _batter;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final st = widget.st;
    final balls = [for (final i in st.innings) ...i.balls];
    final batters = <String>[for (final i in st.innings) ...i.battingOrder];
    if (batters.isEmpty) {
      return ListView(children: [EmptyState(icon: Icons.donut_large_rounded, title: context.tr('no_stats'), body: context.tr('match_not_started_body'))]);
    }
    final sel = _batter != null && batters.contains(_batter) ? _batter! : batters.first;
    final shots = wagonShots(balls, sel);
    final zones = zoneRuns(balls, sel);
    final off = zones.entries.where((e) => Zone.offSide.contains(e.key)).fold<int>(0, (a, e) => a + e.value);
    final leg = zones.entries.where((e) => !Zone.offSide.contains(e.key)).fold<int>(0, (a, e) => a + e.value);
    final sorted = zones.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lh = context.repo.players[sel]?.leftHanded ?? false;
    final maxZone = sorted.isEmpty ? 1 : sorted.first.value;

    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 96), children: [
      Text(context.tr('wagon_wheel'), style: Tx.section(p.text)),
      const SizedBox(height: Space.s),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final b in batters) ...[
            ChoiceChipX(label: widget.name(b), selected: b == sel, onTap: () => setState(() => _batter = b)),
            const SizedBox(width: Space.s),
          ],
        ]),
      ),
      const SizedBox(height: Space.s),
      Row(children: [
        Text(lh ? context.tr('off_side') : context.tr('leg_side'), style: Tx.label(p.text2)),
        const Spacer(),
        Text(lh ? context.tr('leg_side') : context.tr('off_side'), style: Tx.label(p.text2)),
      ]),
      AspectRatio(
        aspectRatio: 1,
        child: Semantics(
          label: context.tr('wagon_wheel_semantics', {'name': widget.name(sel), 'off': off, 'leg': leg}),
          child: CustomPaint(painter: GroundPainter(palette: p, lang: context.settings.lang, shots: shots, leftHanded: lh, showLabels: shots.isEmpty)),
        ),
      ),
      const SizedBox(height: Space.s),
      Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
        _Legend(color: const Color(0xFFFFC94A), label: context.tr('four')),
        _Legend(color: const Color(0xFFFF8A3D), label: context.tr('six')),
        _Legend(color: const Color(0xFF9DB4D6), label: context.tr('one_two_three')),
      ]),
      const SizedBox(height: Space.m),
      if (shots.isEmpty)
        AppCard(child: Text(context.tr('no_shot_data'), style: Tx.small(p.text2)))
      else ...[
        Row(children: [
          Expanded(child: _Stat(label: context.tr('off_side'), value: '$off')),
          const SizedBox(width: Space.s),
          Expanded(child: _Stat(label: context.tr('leg_side'), value: '$leg')),
          const SizedBox(width: Space.s),
          Expanded(child: _Stat(label: context.tr('best_area'), value: sorted.isEmpty ? '-' : Zone.name(sorted.first.key, context.settings.lang))),
        ]),
        const SizedBox(height: Space.s),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            for (final e in sorted.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  SizedBox(width: 92, child: Text(Zone.name(e.key, context.settings.lang), style: Tx.small(p.text, w: FontWeight.w700))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: e.value / maxZone, minHeight: 8, backgroundColor: p.raised, color: p.gold),
                    ),
                  ),
                  SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.right, style: Tx.score(18, p.text, w: FontWeight.w800))),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: Tx.label(p.text2)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Tx.label(p.text2)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Tx.score(22, p.text, w: FontWeight.w800))),
      ]),
    );
  }
}
