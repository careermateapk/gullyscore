// My Cricket: the logged-in player's own page — their numbers, their live,
// upcoming and past matches (from every scorer), and their teams.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'online.dart';
import 'ratings_screens.dart';

class MyCricketScreen extends StatefulWidget {
  const MyCricketScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<MyCricketScreen> createState() => _MyCricketScreenState();
}

class _MyCricketScreenState extends State<MyCricketScreen> {
  int _tab = 0; // 0 my matches, 1 my teams
  Future<MeInfo?>? _future;
  bool _busy = false;

  Future<void> _refresh() async {
    final f = context.sync.refreshMe();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _prompt(BuildContext context, {required IconData icon, required String title, required String body, String? button, VoidCallback? onTap}) {
    final p = Palette.of(context);
    return ListView(padding: const EdgeInsets.all(Space.edge), children: [
      const SizedBox(height: Space.xl),
      Icon(icon, size: 56, color: p.goldText),
      const SizedBox(height: Space.l),
      Text(title, textAlign: TextAlign.center, style: Tx.title(p.text).copyWith(fontSize: 22)),
      const SizedBox(height: Space.s),
      Text(body, textAlign: TextAlign.center, style: Tx.body(p.text2)),
      if (button != null) ...[
        const SizedBox(height: Space.xl),
        GoldButton(label: button, icon: icon, onPressed: _busy ? null : onTap),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              Expanded(child: Semantics(header: true, child: Text(context.tr('nav_my_cricket'), style: Tx.title(p.text)))),
              if (sync.loggedIn) IconBtn(icon: Icons.refresh_rounded, tooltip: context.tr('refresh'), onPressed: _refresh),
            ]),
          );
          Widget body;
          if (!sync.enabled || !sync.loginAvailable && !sync.loggedIn) {
            body = _prompt(context, icon: Icons.cloud_off_rounded, title: context.tr('nav_my_cricket'), body: context.tr('login_not_ready'));
          } else if (!sync.loggedIn) {
            body = _prompt(context,
                icon: Icons.login_rounded,
                title: context.tr('are_you_player'),
                body: context.tr('my_cricket_login_body'),
                button: context.tr('login_google'),
                onTap: () => _run(() => loginAsPlayer(context)));
          } else if (sync.me?.hasPhone != true) {
            body = _prompt(context,
                icon: Icons.phone_android_rounded,
                title: context.tr('add_my_mobile'),
                body: context.tr('add_my_mobile_body'),
                button: context.tr('add_my_mobile'),
                onTap: () => _run(() => askMyPhone(context)));
          } else {
            _future ??= sync.refreshMe();
            body = FutureBuilder<MeInfo?>(
              future: _future,
              builder: (context, snap) {
                final me = sync.me!;
                final loading = snap.connectionState != ConnectionState.done;
                return RefreshIndicator(
                  color: p.goldText,
                  backgroundColor: p.surface,
                  onRefresh: _refresh,
                  child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                    _Hero(me: me),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
                      child: Segmented<int>(
                        values: const [0, 1],
                        labels: [context.tr('my_matches'), context.tr('my_teams')],
                        selected: _tab,
                        onChanged: (v) => setState(() => _tab = v),
                      ),
                    ),
                    if (snap.hasError && me.matches.isEmpty) ...[
                      const SizedBox(height: Space.m),
                      OnlineError(error: snap.error!, onRetry: _refresh),
                    ] else if (loading && me.matches.isEmpty && me.teams.isEmpty) ...[
                      const SizedBox(height: Space.m),
                      const LoadingList(count: 2),
                    ] else if (_tab == 0)
                      ..._myMatches(context, me)
                    else
                      ..._myTeams(context, me),
                  ]),
                );
              },
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Expanded(child: body)]);
        },
      ),
    );
  }

  List<Widget> _myMatches(BuildContext context, MeInfo me) {
    final p = Palette.of(context);
    if (me.profiles.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(Space.edge),
          child: AppCard(child: Text(context.tr('no_profile_for_number'), style: Tx.small(p.text2))),
        ),
      ];
    }
    final live = me.matches.where((m) => m.live).toList();
    final next = me.matches.where((m) => m.upcoming).toList()..sort((a, b) => (a.scheduled ?? DateTime(3000)).compareTo(b.scheduled ?? DateTime(3000)));
    final recent = me.matches.where((m) => !m.live && !m.upcoming).toList();
    Widget card(MatchListItem m) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
          child: OnlineMatchCard(m: m, showMe: true, onTap: () => openFollowed(context, m.id)),
        );
    return [
      if (live.isNotEmpty) ...[SectionHeader(context.tr('live_now')), for (final m in live) card(m)],
      if (next.isNotEmpty) ...[SectionHeader(context.tr('next_match')), for (final m in next.take(3)) card(m)],
      SectionHeader(context.tr('recent')),
      if (recent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: AppCard(child: Text(context.tr('no_my_matches'), style: Tx.small(p.text2))),
        ),
      for (final m in recent) card(m),
    ];
  }

  List<Widget> _myTeams(BuildContext context, MeInfo me) {
    final p = Palette.of(context);
    if (me.teams.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(Space.edge),
          child: AppCard(child: Text(context.tr('no_teams_yet'), style: Tx.small(p.text2))),
        ),
      ];
    }
    return [
      const SizedBox(height: Space.m),
      for (final t in me.teams)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
          child: TeamSummaryCard(team: t, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OnlineTeamScreen(team: t)))),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
        child: Text(context.tr('my_teams_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
      ),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.me});
  final MeInfo me;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = me.totals;
    final name = me.profiles.where((x) => x.approved).map((x) => x.name).firstOrNull ?? me.name;
    final teams = me.teams.map((x) => x.name).where((x) => x.isNotEmpty).toSet().toList();
    Widget stat(String label, String value, {bool gold = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.text.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.heroLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Tx.score(24, gold ? p.goldText : p.text, w: FontWeight.w800))),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0),
      child: HeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB), border: Border.all(color: p.gold, width: 2)),
              alignment: Alignment.center,
              child: Text(initials(name), style: Tx.title(Colors.white).copyWith(fontSize: 20)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20)),
                if (teams.isNotEmpty) Text(teams.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2, w: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: Space.m),
          Row(children: [
            stat(context.tr('matches'), '${t.matches}'),
            const SizedBox(width: Space.s),
            stat(context.tr('runs'), '${t.runs}'),
            const SizedBox(width: Space.s),
            stat(context.tr('wickets'), '${t.wickets}'),
            const SizedBox(width: Space.s),
            stat(context.tr('best'), t.matches == 0 ? '-' : '${t.best}${t.bestNotOut ? '*' : ''}', gold: true),
          ]),
        ]),
      ),
    );
  }
}

/// A team with its record, last 5 results, next match and rating.
class TeamSummaryCard extends StatelessWidget {
  const TeamSummaryCard({super.key, required this.team, required this.onTap});
  final TeamSummary team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final next = team.next;
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Crest(color: teamColorFor(team.name), text: initials(team.name), size: 40),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${context.tr('matches_n', {'n': team.played})} · '),
                TextSpan(text: context.tr('won_n', {'n': team.won}), style: TextStyle(color: p.win)),
                const TextSpan(text: ' · '),
                TextSpan(text: context.tr('lost_n', {'n': team.lost}), style: TextStyle(color: p.liveText)),
              ]), style: Tx.small(p.text2, w: FontWeight.w700)),
            ]),
          ),
          if (team.rating != null) ...[
            Icon(Icons.star_rounded, size: 18, color: p.goldText),
            Text(team.rating!.toStringAsFixed(1), style: Tx.body(p.text, w: FontWeight.w800)),
          ],
          Icon(Icons.chevron_right_rounded, color: p.text2),
        ]),
        if (team.form.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Row(children: [
            for (final f in team.form)
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: f == 'W' ? p.win.withValues(alpha: 0.18) : f == 'L' ? p.liveText.withValues(alpha: 0.85) : p.raised,
                ),
                child: Text(f, style: Tx.small(f == 'W' ? p.win : f == 'L' ? Colors.white : p.text2, w: FontWeight.w800)),
              ),
            const Spacer(),
            Text(context.tr('last_n', {'n': team.form.length}), style: Tx.label(p.text2)),
          ]),
        ],
        if (next != null) ...[
          const SizedBox(height: Space.m),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '📅 ${context.tr('next')}: ${context.tr('vs')} ${next.teamA.id == team.id ? next.teamB.name : next.teamA.name}'
              '${next.scheduled == null ? '' : ' · ${whenText(context, next.scheduled!)}'}',
              style: Tx.small(p.goldText, w: FontWeight.w800),
            ),
          ),
        ],
      ]),
    );
  }
}

/// All matches of one team (live, upcoming, past) and a link to its ratings.
class OnlineTeamScreen extends StatelessWidget {
  const OnlineTeamScreen({super.key, required this.team});
  final TeamSummary team;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final up = team.matches.where((m) => m.upcoming).toList();
    final live = team.matches.where((m) => m.live).toList();
    final past = team.matches.where((m) => !m.upcoming && !m.live).toList();
    Widget card(MatchListItem m) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
          child: OnlineMatchCard(m: m, onTap: () => openFollowed(context, m.id)),
        );
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Crest(color: teamColorFor(team.name), text: initials(team.name), size: 32),
              const SizedBox(width: Space.s),
              Expanded(child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, 0),
            child: AppCard(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamRatingsScreen(scorerId: team.scorerId, teamId: team.id, teamName: team.name))),
              child: Row(children: [
                Icon(Icons.star_rounded, color: p.goldText),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    team.rating == null ? context.tr('no_ratings_yet') : context.tr('rating_of', {'r': team.rating!.toStringAsFixed(1), 'n': team.ratings}),
                    style: Tx.body(p.text, w: FontWeight.w800),
                  ),
                ),
                Text(context.tr('see_comments'), style: Tx.small(p.goldText, w: FontWeight.w800)),
              ]),
            ),
          ),
          if (live.isNotEmpty) ...[SectionHeader(context.tr('live_now')), for (final m in live) card(m)],
          if (up.isNotEmpty) ...[SectionHeader(context.tr('upcoming')), for (final m in up.reversed) card(m)],
          if (past.isNotEmpty) ...[SectionHeader(context.tr('results')), for (final m in past) card(m)],
        ]),
      ),
    );
  }
}
