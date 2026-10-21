// Search teams, players and matches saved on this phone; star favourites.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'match_centre_screen.dart';
import 'player_screen.dart';
import 'team_screen.dart';
import '../widgets/avatar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';
  String _kind = 'all';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context).settings;
    final repo = context.repo;
    final q = _q.trim().toLowerCase();
    bool hit(String text) => q.isEmpty || text.toLowerCase().contains(q);

    final teams = repo.teamList.where((t) => hit(t.name)).toList();
    final players = repo.players.values.where((pl) => q.isNotEmpty && hit(pl.name)).take(20).toList();
    final matches = repo.matchList.where((m) => q.isNotEmpty && (hit(repo.teamName(m.teamA)) || hit(repo.teamName(m.teamB)) || hit(m.title) || hit(m.venue))).take(20).toList();

    TextSpan highlight(String text) {
      if (q.isEmpty) return TextSpan(text: text);
      final i = text.toLowerCase().indexOf(q);
      if (i < 0) return TextSpan(text: text);
      return TextSpan(children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(text: text.substring(i, i + q.length), style: TextStyle(color: p.goldText)),
        TextSpan(text: text.substring(i + q.length)),
      ]);
    }

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, Space.l, 0, Space.s),
          child: Text(t.toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 0.4)),
        );

    final showTeams = _kind == 'all' || _kind == 'teams';
    final showPlayers = _kind == 'all' || _kind == 'players';
    final showMatches = _kind == 'all' || _kind == 'matches';
    final nothing = (!showTeams || teams.isEmpty) && (!showPlayers || players.isEmpty) && (!showMatches || matches.isEmpty);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.s),
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded, color: p.text2), hintText: context.tr('search_hint')),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0), children: [
              for (final k in const ['all', 'teams', 'players', 'matches']) ...[
                ChoiceChipX(label: context.tr('search_$k'), selected: _kind == k, onTap: () => setState(() => _kind = k)),
                const SizedBox(width: Space.s),
              ],
            ]),
          ),
          Expanded(
            child: nothing
                ? ListView(children: [
                    EmptyState(
                      icon: Icons.search_off_rounded,
                      title: q.isEmpty ? context.tr('search_start') : context.tr('no_results'),
                      body: q.isEmpty ? context.tr('search_start_body') : context.tr('no_results_body', {'q': _q.trim()}),
                    ),
                  ])
                : ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: [
                    if (showTeams && teams.isNotEmpty) ...[
                      heading(context.tr('teams')),
                      for (final t in teams)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: AppCard(
                            padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                            onTap: () => openTeamEditor(context, teamId: t.id),
                            child: Row(children: [
                              Crest(logo: t.logo, color: Palette.team(t.colorIndex), text: t.short, size: 32),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text.rich(highlight(t.name), style: Tx.body(p.text, w: FontWeight.w800)),
                                  Text(context.tr('players_n', {'n': t.playerIds.length}), style: Tx.label(p.text2)),
                                ]),
                              ),
                              IconButton(
                                tooltip: s.favouriteTeams.contains(t.id) ? context.tr('unfollow') : context.tr('follow'),
                                onPressed: () => s.toggleFavourite(t.id),
                                icon: Icon(s.favouriteTeams.contains(t.id) ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: s.favouriteTeams.contains(t.id) ? p.goldText : p.text2),
                              ),
                            ]),
                          ),
                        ),
                    ],
                    if (showPlayers && players.isNotEmpty) ...[
                      heading(context.tr('players')),
                      for (final pl in players)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: pl.id))),
                            child: Row(children: [
                              PlayerAvatar(playerId: pl.id, size: 36),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text.rich(highlight(pl.name), style: Tx.body(p.text, w: FontWeight.w800)),
                                  Text(repo.teams.values.where((t) => t.playerIds.contains(pl.id)).map((t) => t.name).join(', '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ],
                    if (showMatches && matches.isNotEmpty) ...[
                      heading(context.tr('nav_matches')),
                      for (final m in matches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
                            child: Row(children: [
                              Icon(Icons.sports_cricket_rounded, color: p.goldText, size: 22),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                                  Text([if (m.title.isNotEmpty) m.title, agoText(context, m.updatedAt)].join(' · '), style: Tx.label(p.text2)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }
}
