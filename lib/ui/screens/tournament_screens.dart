// Tournaments: list, create, and the tournament home with fixtures,
// tables, stats and teams.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/engine.dart';
import '../../scoring/stats.dart';
import '../../scoring/tournament.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'certificates.dart';
import 'help.dart';
import 'match_centre_screen.dart';
import 'new_match_screen.dart';
import 'player_screen.dart';
import 'scoring_screen.dart';
import 'scoring_sheets.dart';
import 'series_screen.dart';
import 'team_screen.dart';

// ------------------------------------------------------------ labels

String categoryLabel(BuildContext context, String c) => context.tr('cat_$c');

String stageLabel(BuildContext context, Fixture f) {
  switch (f.stage) {
    case Stage.group:
      return context.tr('stage_group', {'g': groupLetter(f.group ?? 0)});
    case Stage.league:
      return context.tr('stage_league');
    case Stage.quarter:
      return context.tr('stage_qf');
    case Stage.semi:
      return context.tr('stage_sf');
    case Stage.finalStage:
      return context.tr('stage_final');
  }
  return context.tr('stage_round', {'n': f.stage.substring(1)});
}

String slotLabel(BuildContext context, Tournament t, String? slot) {
  if (slot == null) return context.tr('tbd');
  if (slot.startsWith('W:')) {
    final f = t.fixture(slot.substring(2));
    return context.tr('winner_of', {'n': f?.number ?? '?'});
  }
  if (slot.startsWith('L')) return context.tr('league_pos', {'n': slot.substring(1)});
  final m = RegExp(r'^G(\d+)P(\d+)$').firstMatch(slot);
  if (m != null) return context.tr('group_pos', {'g': groupLetter(int.parse(m.group(1)!)), 'n': m.group(2)!});
  return context.tr('tbd');
}

// ------------------------------------------------------------ list (inside Series tab)

class TournamentsSection extends StatelessWidget {
  const TournamentsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final list = repo.tournamentList;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(
        context.tr('tournaments'),
        action: list.isEmpty ? null : context.tr('new_tournament'),
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTournamentScreen())),
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: HeroCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.emoji_events_rounded, color: p.goldText, size: 34),
              const SizedBox(height: Space.s),
              Text(context.tr('tournament_empty_title'), style: Tx.section(p.text)),
              const SizedBox(height: 4),
              Text(context.tr('tournament_empty_body'), style: Tx.small(p.text2)),
              const SizedBox(height: Space.l),
              GoldButton(
                label: context.tr('new_tournament'),
                icon: Icons.add_rounded,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTournamentScreen())),
              ),
            ]),
          ),
        )
      else
        for (final t in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
            child: _TournamentCard(t: t),
          ),
    ]);
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.t});
  final Tournament t;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final v = repo.viewOf(t);
    final champ = v.champion();
    final total = t.fixtures.length;
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(tournamentId: t.id))),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Corners.button)),
          child: Icon(Icons.emoji_events_rounded, color: p.goldText),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              champ != null
                  ? context.tr('champions_are', {'team': repo.teamName(champ)})
                  : '${categoryLabel(context, t.category)} · ${context.tr('played_of', {'n': v.played, 'm': total})}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.label(champ != null ? p.win : p.text2),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: total == 0 ? 0 : v.played / total, minHeight: 5, backgroundColor: p.raised, color: p.gold),
            ),
          ]),
        ),
        const SizedBox(width: Space.s),
        Icon(Icons.chevron_right_rounded, color: p.text2),
      ]),
    );
  }
}

// ------------------------------------------------------------ create

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _name = TextEditingController();
  final _venue = TextEditingController();
  String _category = 'open';
  String _format = TFormat.league;
  int _overs = 10;
  int _groups = 2;
  int _qualifiers = 2;
  final List<String> _teams = [];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  String? _problem() {
    final n = _teams.length;
    if (_name.text.trim().isEmpty) return context.tr('tournament_name_needed');
    if (n < 2) return context.tr('need_two_teams');
    switch (_format) {
      case TFormat.knockout:
        if (!isPowerOfTwo(n)) return context.tr('knockout_team_count');
      case TFormat.groups:
        if (n < _groups * 2) return context.tr('groups_team_count', {'n': _groups * 2});
        if (!isPowerOfTwo(_groups * _qualifiers)) return context.tr('groups_qualify_count');
      default:
        if (_qualifiers > n) return context.tr('league_qualify_count');
    }
    return null;
  }

  int _matchCount() {
    final n = _teams.length;
    int rr(int k) => k * (k - 1) ~/ 2;
    switch (_format) {
      case TFormat.knockout:
        return n < 2 ? 0 : n - 1;
      case TFormat.groups:
        if (n < 2) return 0;
        final gs = makeGroups(_teams, _groups);
        final q = _groups * _qualifiers;
        return gs.fold<int>(0, (a, g) => a + rr(g.length)) + (isPowerOfTwo(q) ? q - 1 : 0);
      default:
        return rr(n) + (_qualifiers >= 2 && isPowerOfTwo(_qualifiers) ? _qualifiers - 1 : 0);
    }
  }

  Future<void> _addTeams() async {
    final repo = context.repo;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          final p = Palette.of(ctx);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetTitle(ctx.tr('choose_teams'), subtitle: ctx.tr('selected_n', {'n': _teams.length})),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: Space.edge), children: [
                  for (final t in repo.teamList)
                    CheckboxListTile(
                      value: _teams.contains(t.id),
                      activeColor: p.gold,
                      checkColor: const Color(0xFF0B1220),
                      secondary: Crest(logo: t.logo, color: Palette.team(t.colorIndex), text: t.short, size: 28),
                      title: Text(t.name, style: Tx.body(p.text, w: FontWeight.w700)),
                      onChanged: (v) {
                        setSheet(() => v == true ? _teams.add(t.id) : _teams.remove(t.id));
                        setState(() {});
                      },
                    ),
                  if (repo.teams.isEmpty)
                    Padding(padding: const EdgeInsets.all(Space.l), child: Text(ctx.tr('no_teams_yet'), textAlign: TextAlign.center, style: Tx.body(p.text2))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
                child: Row(children: [
                  Expanded(
                    child: OutlineBtn(
                      label: ctx.tr('new_team'),
                      icon: Icons.add_rounded,
                      onPressed: () async {
                        final id = await openTeamEditor(ctx);
                        if (id != null) {
                          setSheet(() => _teams.add(id));
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: GoldButton(label: ctx.tr('done'), onPressed: () => Navigator.pop(ctx))),
                ]),
              ),
            ]),
          );
        }));
  }

  void _create() {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final t = context.repo.addTournament(
      name: _name.text,
      format: _format,
      overs: _overs,
      teamIds: List.of(_teams),
      groupCount: _groups,
      qualifiers: _format == TFormat.knockout ? 0 : _qualifiers,
      category: _category,
      venue: _venue.text,
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TournamentScreen(tournamentId: t.id)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    Widget label(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.s), child: Text(t, style: Tx.section(p.text).copyWith(fontSize: 15)));
    final count = _matchCount();
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.close_rounded, tooltip: context.tr('close'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('new_tournament'), style: Tx.title(p.text).copyWith(fontSize: 20))),
              IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'tournament')),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.xl), children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(hintText: context.tr('tournament_name_hint')),
              ),
              const SizedBox(height: Space.s),
              TextField(controller: _venue, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('ground_hint'))),
              label(context.tr('category')),
              Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final c in const ['open', 'women', 'u17', 'u14'])
                  ChoiceChipX(label: categoryLabel(context, c), selected: _category == c, onTap: () => setState(() => _category = c)),
              ]),
              label(context.tr('format')),
              for (final f in const [TFormat.league, TFormat.groups, TFormat.knockout])
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: AppCard(
                    borderColor: _format == f ? p.gold : null,
                    onTap: () => setState(() {
                      _format = f;
                      _error = null;
                    }),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(_format == f ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _format == f ? p.goldText : p.text2),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.tr('fmt_$f'), style: Tx.body(p.text, w: FontWeight.w800)),
                          Text(context.tr('fmt_${f}_body'), style: Tx.label(p.text2, w: FontWeight.w500)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              if (_format == TFormat.groups) ...[
                label(context.tr('number_of_groups')),
                Segmented<int>(values: const [2, 3, 4], labels: const ['2', '3', '4'], selected: _groups, onChanged: (v) => setState(() => _groups = v)),
                label(context.tr('qualify_per_group')),
                Segmented<int>(values: const [1, 2, 4], labels: const ['1', '2', '4'], selected: _qualifiers, onChanged: (v) => setState(() => _qualifiers = v)),
              ],
              if (_format == TFormat.league) ...[
                label(context.tr('after_league')),
                Segmented<int>(
                  values: const [0, 2, 4],
                  labels: [context.tr('no_knockout'), context.tr('top_2_final'), context.tr('top_4_semis')],
                  selected: _qualifiers,
                  onChanged: (v) => setState(() => _qualifiers = v),
                ),
              ],
              label(context.tr('overs_per_side')),
              Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final o in const [5, 6, 8, 10, 12, 15, 20]) ChoiceChipX(label: '$o', selected: _overs == o, onTap: () => setState(() => _overs = o)),
              ]),
              label(context.tr('teams_n', {'n': _teams.length})),
              for (final id in _teams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AppCard(
                    padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                    child: Row(children: [
                      Crest(logo: repo.teams[id]?.logo, color: Palette.team(repo.teams[id]?.colorIndex ?? 0), text: repo.teams[id]?.short ?? '', size: 26),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(repo.teamName(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w700))),
                      IconButton(
                        tooltip: context.tr('remove'),
                        onPressed: () => setState(() => _teams.remove(id)),
                        icon: Icon(Icons.close_rounded, color: p.text2),
                      ),
                    ]),
                  ),
                ),
              OutlineBtn(label: context.tr('add_teams'), icon: Icons.group_add_rounded, onPressed: _addTeams),
              if (_teams.length >= 2) ...[
                const SizedBox(height: Space.m),
                Text(context.tr('will_create_matches', {'n': count}), style: Tx.small(p.text2)),
              ],
              if (_error != null) ...[
                const SizedBox(height: Space.m),
                Text(_error!, style: Tx.small(p.liveText, w: FontWeight.w700)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
            child: GoldButton(label: context.tr('create_tournament'), icon: Icons.emoji_events_rounded, onPressed: _create),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ tournament home

class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key, required this.tournamentId});
  final String tournamentId;

  Future<void> _delete(BuildContext context, Tournament t) async {
    final repo = context.repo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_tournament_q')),
        content: Text(ctx.tr('delete_tournament_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'), style: TextStyle(color: Palette.of(ctx).liveText))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.pop(context);
      repo.deleteTournament(t.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final p = Palette.of(context);
        final repo = context.repo;
        final t = repo.tournaments[tournamentId];
        if (t == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: p.bg),
            body: Center(child: EmptyState(icon: Icons.emoji_events_outlined, title: context.tr('tournament_not_found'), body: context.tr('match_not_found_body'))),
          );
        }
        final v = repo.viewOf(t);
        final champ = v.champion();
        final tabs = [
          context.tr('fixtures'),
          context.tr(t.format == TFormat.knockout ? 'bracket' : 'points_table'),
          context.tr('tab_stats'),
          context.tr('teams'),
        ];
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.s, Space.s),
                      child: Row(children: [
                        IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 17))),
                        IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'tournament')),
                        PopupMenuButton<String>(
                          tooltip: context.tr('more'),
                          icon: Icon(Icons.more_vert_rounded, color: p.text),
                          onSelected: (k) {
                            if (k == 'delete') _delete(context, t);
                          },
                          itemBuilder: (ctx) => [PopupMenuItem(value: 'delete', child: Text(ctx.tr('delete_tournament')))],
                        ),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                      child: HeroCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            Tag(categoryLabel(context, t.category), color: p.goldText, background: p.gold.withValues(alpha: 0.14)),
                            Tag(context.tr('fmt_${t.format}')),
                            Tag(context.tr('overs_match', {'n': t.overs})),
                          ]),
                          const SizedBox(height: Space.m),
                          if (champ != null) ...[
                            Row(children: [
                              Crest(logo: repo.teams[champ]?.logo, color: Palette.team(repo.teams[champ]?.colorIndex ?? 0), text: repo.teams[champ]?.short ?? '', size: 40),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(context.tr('champions'), style: Tx.label(p.goldText, w: FontWeight.w800)),
                                  Text(repo.teamName(champ), style: Tx.title(p.text).copyWith(fontSize: 20)),
                                ]),
                              ),
                            ]),
                            const SizedBox(height: Space.m),
                            OutlineBtn(
                              label: context.tr('champion_certificate'),
                              icon: Icons.workspace_premium_rounded,
                              height: 44,
                              onPressed: () => shareChampionCertificate(context, t, champ),
                            ),
                          ] else ...[
                            Text(context.tr('played_of', {'n': v.played, 'm': t.fixtures.length}), style: Tx.body(p.text, w: FontWeight.w800)),
                            const SizedBox(height: Space.s),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: t.fixtures.isEmpty ? 0 : v.played / t.fixtures.length,
                                minHeight: 6,
                                backgroundColor: p.raised,
                                color: p.gold,
                              ),
                            ),
                            if (t.venue.isNotEmpty) ...[const SizedBox(height: Space.s), Text(t.venue, style: Tx.label(p.text2))],
                          ],
                        ]),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(pinned: true, delegate: _Tabs(p, tabs)),
                ],
                body: TabBarView(children: [
                  _FixturesTab(t: t, v: v),
                  _TableTab(t: t, v: v),
                  _StatsTab(t: t, v: v),
                  _TeamsTab(t: t),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends SliverPersistentHeaderDelegate {
  _Tabs(this.p, this.labels);
  final Palette p;
  final List<String> labels;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: p.bg,
        padding: const EdgeInsets.only(top: 4),
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          labelColor: p.text,
          unselectedLabelColor: p.text2,
          indicatorColor: p.gold,
          dividerColor: p.line,
          labelStyle: const TextStyle(fontFamily: 'Hanken', fontFamilyFallback: ['NotoDeva'], fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [for (final l in labels) Tab(text: l)],
        ),
      );

  @override
  bool shouldRebuild(_Tabs old) => old.p != p || old.labels.join() != labels.join();
}

// ------------------------------------------------------------ fixtures

class _FixturesTab extends StatelessWidget {
  const _FixturesTab({required this.t, required this.v});
  final Tournament t;
  final TournamentView v;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = <Widget>[];
    String? lastHeader;
    for (final f in t.fixtures) {
      final header = stageLabel(context, f);
      if (header != lastHeader) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, Space.l, 0, Space.s),
          child: Text(header.toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 0.4)),
        ));
        lastHeader = header;
      }
      items.add(Padding(padding: const EdgeInsets.only(bottom: Space.s), child: FixtureCard(t: t, v: v, f: f)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: items);
  }
}

class FixtureCard extends StatelessWidget {
  const FixtureCard({super.key, required this.t, required this.v, required this.f});
  final Tournament t;
  final TournamentView v;
  final Fixture f;

  Future<void> _pick(BuildContext context, String a, String b) async {
    final repo = context.repo;
    final id = await showAppSheet<String>(context, (ctx) {
      final p = Palette.of(ctx);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(ctx.tr('who_goes_through'), subtitle: ctx.tr('who_goes_through_body')),
          for (final team in [a, b])
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
              child: AppCard(
                onTap: () => Navigator.pop(ctx, team),
                child: Row(children: [
                  Crest(logo: repo.teams[team]?.logo, color: Palette.team(repo.teams[team]?.colorIndex ?? 0), text: repo.teams[team]?.short ?? '', size: 30),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(repo.teamName(team), style: Tx.body(p.text, w: FontWeight.w800))),
                ]),
              ),
            ),
        ]),
      );
    });
    if (id != null) repo.pickWinner(t, f, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final (a, b) = v.teamsOf(f);
    final m = f.matchId == null ? null : repo.matches[f.matchId];
    final st = m?.state;
    final ready = a != null && b != null;
    final winner = v.winnerOf(f);

    Widget team(String? id, String? slot) {
      final tm = id == null ? null : repo.teams[id];
      Innings? inn;
      if (st != null && m != null && id != null) {
        for (final i in st.innings) {
          if ((i.battingTeam == 0 ? m.teamA : m.teamB) == id) inn = i;
        }
      }
      final won = winner != null && winner == id;
      return Row(children: [
        if (tm != null)
          Crest(logo: tm.logo, color: Palette.team(tm.colorIndex), text: tm.short, size: 24)
        else
          Container(
            width: 24,
            height: 26,
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.help_outline_rounded, size: 14, color: p.text2),
          ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            tm?.name ?? slotLabel(context, t, slot),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tx.body(tm == null ? p.text2 : (winner == null || won ? p.text : p.text2), w: won ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
        if (inn != null)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('${inn.runs}/${inn.wickets} (${inn.overs})', style: Tx.score(18, won ? p.text : p.text2, w: FontWeight.w800)),
            ),
          ),
      ]);
    }

    Widget footer;
    if (v.needsPick(f) && a != null && b != null) {
      footer = OutlineBtn(label: context.tr('pick_who_goes_through'), height: 44, color: p.goldText, onPressed: () => _pick(context, a, b));
    } else if (m != null && st != null && st.finished) {
      final mom = playerOfMatch(st);
      footer = Row(children: [
        Expanded(
          child: Text(st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB)), maxLines: 2, style: Tx.small(p.win, w: FontWeight.w700)),
        ),
        if (mom != null) ...[
          const SizedBox(width: Space.s),
          Flexible(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.star_rounded, size: 16, color: p.goldText),
              const SizedBox(width: 2),
              Flexible(child: Text(repo.playerName(mom), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.goldText, w: FontWeight.w800))),
            ]),
          ),
        ],
      ]);
    } else if (f.winnerOverride != null) {
      footer = Text(context.tr('goes_through', {'team': repo.teamName(f.winnerOverride!)}), style: Tx.small(p.win, w: FontWeight.w700));
    } else if (m != null) {
      footer = Row(children: [
        Expanded(child: Text(context.tr('in_progress'), style: Tx.small(p.goldText, w: FontWeight.w800))),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id))),
          style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(48, 40)),
          child: Text(context.tr('continue_scoring')),
        ),
      ]);
    } else if (ready) {
      footer = GoldButton(
        label: context.tr('start_this_match'),
        icon: Icons.sports_cricket_rounded,
        height: 44,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewMatchScreen(
              tournamentId: t.id,
              fixtureId: f.id,
              teamA: a,
              teamB: b,
              overs: t.overs,
              title: '${t.name} · ${context.tr('match_n', {'n': f.number})}',
              venue: t.venue,
            ),
          ),
        ),
      );
    } else {
      footer = Text(context.tr('waiting_for_teams'), style: Tx.small(p.text2));
    }

    return AppCard(
      onTap: m == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(context.tr('match_n', {'n': f.number}), style: Tx.label(p.text2)),
          const SizedBox(width: Space.s),
          if (Stage.isKnockout(f.stage)) Flexible(child: Tag(stageLabel(context, f), color: p.goldText, background: p.gold.withValues(alpha: 0.14))),
        ]),
        const SizedBox(height: Space.s),
        team(a, f.slotA),
        const SizedBox(height: 6),
        team(b, f.slotB),
        const SizedBox(height: Space.m),
        footer,
      ]),
    );
  }
}

// ------------------------------------------------------------ table / bracket

class _TableTab extends StatelessWidget {
  const _TableTab({required this.t, required this.v});
  final Tournament t;
  final TournamentView v;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final children = <Widget>[];
    if (t.format == TFormat.groups) {
      for (var g = 0; g < t.groups.length; g++) {
        children.add(SectionHeader(context.tr('stage_group', {'g': groupLetter(g)})));
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: AppCard(padding: const EdgeInsets.fromLTRB(14, 12, 14, 4), child: PointsTableView(rows: v.table(group: g))),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
        child: Text(context.tr('qualify_note', {'n': t.qualifiers}), style: Tx.label(p.text2, w: FontWeight.w600)),
      ));
    } else if (t.format == TFormat.league) {
      children.add(const SizedBox(height: Space.m));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.edge),
        child: AppCard(padding: const EdgeInsets.fromLTRB(14, 12, 14, 4), child: PointsTableView(rows: v.table())),
      ));
      if (t.qualifiers >= 2) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
          child: Text(context.tr('league_qualify_note', {'n': t.qualifiers}), style: Tx.label(p.text2, w: FontWeight.w600)),
        ));
      }
    }
    final ko = t.fixtures.where((f) => Stage.isKnockout(f.stage)).toList();
    if (ko.isNotEmpty) {
      children.add(SectionHeader(context.tr('knockouts')));
      for (final f in ko) {
        children.add(Padding(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s), child: FixtureCard(t: t, v: v, f: f)));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: children);
  }
}

// ------------------------------------------------------------ stats

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.t, required this.v});
  final Tournament t;
  final TournamentView v;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final done = v.allFinished;
    if (done.isEmpty) {
      return ListView(children: [EmptyState(icon: Icons.leaderboard_outlined, title: context.tr('no_stats'), body: context.tr('stats_after_first_match'))]);
    }
    final mvp = mvpTable(done.map((m) => m.state)).take(5).toList();
    final runs = topRunScorers(done, limit: 5);
    final wkts = topWicketTakers(done, limit: 5);
    final sixes = <String, int>{};
    for (final m in done) {
      for (final inn in m.state.innings) {
        for (final b in inn.batters.values) {
          if (b.sixes > 0) sixes[b.id] = (sixes[b.id] ?? 0) + b.sixes;
        }
      }
    }
    final sixList = sixes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget board(String title, List<(String, String, String)> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                for (var i = 0; i < rows.length; i++)
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: rows[i].$1))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(children: [
                        SizedBox(width: 20, child: Text('${i + 1}', style: Tx.label(p.text2))),
                        PlayerAvatar(playerId: rows[i].$1, size: 30),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text(repo.playerName(rows[i].$1), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800).copyWith(fontSize: 14))),
                        const SizedBox(width: Space.s),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(rows[i].$2, style: Tx.score(20, i == 0 ? p.goldText : p.text, w: FontWeight.w800)),
                          if (rows[i].$3.isNotEmpty) Text(rows[i].$3, style: Tx.label(p.text2, w: FontWeight.w500)),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ]);

    return ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
      if (mvp.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
          child: HeroCard(
            child: Row(children: [
              PlayerAvatar(playerId: mvp.first.$1, size: 56, ring: p.gold),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('player_of_tournament'), style: Tx.label(p.goldText, w: FontWeight.w800)),
                  Text(repo.playerName(mvp.first.$1), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20)),
                  Text(context.tr('mvp_points', {'n': mvp.first.$2.round()}), style: Tx.label(p.text2)),
                ]),
              ),
            ]),
          ),
        ),
        board(context.tr('mvp_table'), [for (final e in mvp) (e.$1, '${e.$2.round()}', '')]),
      ],
      board(context.tr('most_runs'), [for (final l in runs) (l.playerId, '${l.value}', context.tr('balls_n', {'n': l.detail}))]),
      board(context.tr('most_wickets'), [for (final l in wkts) (l.playerId, '${l.value}', context.tr('runs_n', {'n': l.detail}))]),
      if (sixList.isNotEmpty) board(context.tr('most_sixes'), [for (final e in sixList.take(5)) (e.key, '${e.value}', '')]),
      Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Text(context.tr('mvp_how'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
      ),
    ]);
  }
}

// ------------------------------------------------------------ teams

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.t});
  final Tournament t;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl), children: [
      for (final id in t.teamIds)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: AppCard(
            onTap: () => openTeamEditor(context, teamId: id),
            child: Row(children: [
              Crest(logo: repo.teams[id]?.logo, color: Palette.team(repo.teams[id]?.colorIndex ?? 0), text: repo.teams[id]?.short ?? '', size: 32),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(repo.teamName(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                  Text(context.tr('players_n', {'n': repo.teams[id]?.playerIds.length ?? 0}), style: Tx.label(p.text2)),
                ]),
              ),
              if (t.format == TFormat.groups)
                Tag(context.tr('stage_group', {'g': groupLetter(t.groups.indexWhere((g) => g.contains(id)).clamp(0, 25))})),
            ]),
          ),
        ),
    ]);
  }
}

/// Short label for a player-of-the-match line (used by match centre too).
String? playerOfMatchName(BuildContext context, MatchRecord m) {
  final id = playerOfMatch(m.state);
  return id == null ? null : context.repo.playerName(id);
}
