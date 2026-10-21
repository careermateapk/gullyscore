// Home: matches in progress, recent results and favourite teams.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/engine.dart';
import '../../scoring/predictor.dart';
import '../widgets/common.dart';
import 'backup_ui.dart';
import 'match_centre_screen.dart';
import 'new_match_screen.dart';
import 'online.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = 'all'; // 'all', 'fav' or a match title
  final _pager = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  bool _keep(MatchRecord m) {
    if (_filter == 'all') return true;
    if (_filter == 'fav') {
      final fav = context.settings.favouriteTeams;
      return fav.contains(m.teamA) || fav.contains(m.teamB);
    }
    return m.title == _filter;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        if (!repo.loaded) return const _HomeLoading();
        if (repo.loadError != null) {
          return SafeArea(
            child: Center(
              child: ErrorState(
                title: context.tr('load_failed'),
                body: context.tr('load_failed_body'),
                retryLabel: context.tr('try_again'),
                onRetry: repo.load,
              ),
            ),
          );
        }
        final all = repo.matchList;
        final titles = {for (final m in all) if (m.title.isNotEmpty) m.title}.toList();
        final list = all.where(_keep).toList();
        final states = {for (final m in list) m.id: m.state};
        final going = list.where((m) => !states[m.id]!.finished).toList();
        final done = list.where((m) => states[m.id]!.finished).toList();

        return Stack(children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: p.goldText,
              backgroundColor: p.surface,
              onRefresh: repo.load,
              child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                _TopBar(onSearch: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), onProfile: () => widget.onOpenTab(4)),
                if (all.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0),
                      children: [
                        ChoiceChipX(label: context.tr('all'), selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                        const SizedBox(width: Space.s),
                        ChoiceChipX(label: context.tr('following'), icon: Icons.star_rounded, selected: _filter == 'fav', onTap: () => setState(() => _filter = 'fav')),
                        for (final t in titles) ...[
                          const SizedBox(width: Space.s),
                          ChoiceChipX(label: t, icon: Icons.emoji_events_rounded, selected: _filter == t, onTap: () => setState(() => _filter = t)),
                        ],
                      ],
                    ),
                  ),
                const ClaimsCard(),
                const MyMatchesSection(),
                if (all.isEmpty)
                  const _FirstRun()
                else ...[
                  if (going.isNotEmpty) ...[
                    const SizedBox(height: Space.m),
                    SizedBox(
                      height: 254,
                      child: PageView.builder(
                        controller: _pager,
                        padEnds: false,
                        itemCount: going.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) => Padding(
                          padding: EdgeInsets.only(left: i == 0 ? Space.edge : Space.s, right: i == going.length - 1 ? Space.edge : 0),
                          child: FeaturedMatchCard(m: going[i], st: states[going[i].id]!),
                        ),
                      ),
                    ),
                    if (going.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var i = 0; i < going.length; i++)
                            AnimatedContainer(
                              duration: Motion.fade,
                              width: i == _page ? 18 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(color: i == _page ? p.gold : p.line, borderRadius: BorderRadius.circular(99)),
                            ),
                        ]),
                      ),
                  ],
                  if (done.isNotEmpty) ...[
                    SectionHeader(context.tr('recent_results'), action: context.tr('all_matches'), onAction: () => widget.onOpenTab(1)),
                    for (final m in done.take(4))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                        child: ResultCard(m: m, st: states[m.id]!),
                      ),
                  ],
                  if (list.isEmpty)
                    EmptyState(
                      icon: Icons.star_outline_rounded,
                      title: context.tr('nothing_here'),
                      body: _filter == 'fav' ? context.tr('no_fav_matches') : context.tr('nothing_here_filter'),
                    ),
                ],
              ]),
            ),
          ),
          Positioned(
            right: Space.edge,
            bottom: Space.l,
            child: GoldButton(
              label: context.tr('score_a_match'),
              icon: Icons.add_rounded,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMatchScreen())),
            ),
          ),
        ]);
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSearch, required this.onProfile});
  final VoidCallback onSearch;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
      child: Row(children: [
        const AppLogo(size: 36),
        const SizedBox(width: Space.s + 2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GullyScore', style: Tx.score(24, p.text, w: FontWeight.w800)),
            Text(context.tr('saved_on_phone'), style: Tx.label(p.text2, w: FontWeight.w600)),
          ]),
        ),
        if (context.sync.enabled) ...[
          IconBtn(icon: Icons.link_rounded, tooltip: context.tr('follow_a_match'), onPressed: () => followMatchByLink(context)),
          const SizedBox(width: Space.s),
        ],
        IconBtn(icon: Icons.search_rounded, tooltip: context.tr('search'), onPressed: onSearch),
        const SizedBox(width: Space.s),
        IconBtn(icon: Icons.person_outline_rounded, tooltip: context.tr('nav_profile'), onPressed: onProfile),
      ]),
    );
  }
}

/// The GullyScore mark: three rising bars and a red ball.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 200;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(52 * k)), Paint()..color = const Color(0xFFFFC94A));
    final bar = Paint()..color = const Color(0xFF070F1E);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(46 * k, 98 * k, 20 * k, 62 * k), Radius.circular(5 * k)), bar);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(80 * k, 76 * k, 20 * k, 84 * k), Radius.circular(5 * k)), bar);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(114 * k, 54 * k, 20 * k, 106 * k), Radius.circular(5 * k)), bar);
    canvas.drawCircle(Offset(152 * k, 50 * k), 20 * k, Paint()..color = const Color(0xFFFF4D4D));
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Shimmer(
        child: ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(Space.edge), children: const [
          Row(children: [SkeletonBox(width: 36, height: 36, radius: 10), SizedBox(width: 10), SkeletonBox(width: 140, height: 22)]),
          SizedBox(height: Space.l),
          SkeletonBox(height: 220, radius: Corners.hero),
          SizedBox(height: Space.l),
          SkeletonBox(width: 120, height: 18),
          SizedBox(height: Space.m),
          SkeletonBox(height: 84, radius: Corners.card),
          SizedBox(height: Space.s),
          SkeletonBox(height: 84, radius: Corners.card),
        ]),
      ),
    );
  }
}

class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Text('$n', style: Tx.label(p.goldText, w: FontWeight.w800)),
            ),
            const SizedBox(width: Space.m),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: Tx.body(p.text)))),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
      child: HeroCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('first_match_title'), style: Tx.score(34, p.text)),
          const SizedBox(height: Space.s),
          Text(context.tr('first_match_body'), style: Tx.body(p.text2)),
          step(1, context.tr('first_step_1')),
          step(2, context.tr('first_step_2')),
          step(3, context.tr('first_step_3')),
          const SizedBox(height: Space.l),
          GoldButton(
            label: context.tr('score_a_match'),
            icon: Icons.add_rounded,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMatchScreen())),
          ),
          const SizedBox(height: Space.s),
          Center(
            child: TextButton.icon(
              onPressed: () => restoreBackup(context),
              style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(48, 44)),
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: Text(context.tr('have_backup')),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Big card for a match in progress.
class FeaturedMatchCard extends StatelessWidget {
  const FeaturedMatchCard({super.key, required this.m, required this.st});
  final MatchRecord m;
  final MatchState st;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final status = statusOf(m, st);
    final inn = st.current;
    final chance = winChance(st);
    Widget teamRow(int t) {
      final team = repo.teams[t == 0 ? m.teamA : m.teamB];
      Innings? i;
      for (final x in st.innings) {
        if (x.battingTeam == t) i = x;
      }
      final batting = inn != null && !inn.ended && inn.battingTeam == t;
      return Row(children: [
        Crest(logo: team?.logo, color: Palette.team(team?.colorIndex ?? 0), text: team?.short ?? '', size: 26),
        const SizedBox(width: Space.s + 2),
        Expanded(
          child: Text(team?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(batting ? p.text : p.text2, w: batting ? FontWeight.w800 : FontWeight.w700)),
        ),
        const SizedBox(width: Space.s),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: i != null
                ? Text.rich(TextSpan(children: [
                    TextSpan(text: '${i.runs}/${i.wickets}', style: Tx.score(batting ? 32 : 22, batting ? p.text : p.text2)),
                    TextSpan(text: ' (${i.overs})', style: Tx.score(batting ? 16 : 14, p.text2, w: FontWeight.w700)),
                  ]))
                : Text(context.tr('yet_to_bat'), style: Tx.label(p.text2)),
          ),
        ),
      ]);
    }

    String line;
    if (inn == null) {
      line = m.tossText.isEmpty ? context.tr('not_started') : m.tossText;
    } else if (inn.number == 1 && !inn.ended) {
      line = context.tr('need_runs', {'n': st.runsNeeded ?? 0, 'b': st.ballsLeft ?? 0});
    } else if (inn.ended) {
      line = context.tr('innings_break');
    } else {
      line = context.tr('crr_value', {'v': inn.runRate.toStringAsFixed(2)});
    }
    final recent = inn == null ? <BallLog>[] : inn.balls.reversed.take(4).toList().reversed.toList();

    return Pressable(
      semanticLabel: context.tr('open_match_centre'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
      child: HeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: status == MatchStatus.live ? LiveBadge(label: context.tr('live')) : Tag(status == MatchStatus.paused ? context.tr('paused') : context.tr('not_started'))),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text([if (m.title.isNotEmpty) m.title, context.tr('overs_match', {'n': m.overs})].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
            ),
          ]),
          const SizedBox(height: Space.m),
          teamRow(m.firstBatting),
          const SizedBox(height: Space.s),
          teamRow(1 - m.firstBatting),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.goldText, w: FontWeight.w800).copyWith(fontSize: 14)),
                if (chance != null) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 6,
                      child: Row(children: [
                        Expanded(flex: chance.chasingPercent.clamp(1, 99), child: Container(color: Palette.team(repo.teams[chance.chasingTeam == 0 ? m.teamA : m.teamB]?.colorIndex ?? 0))),
                        const SizedBox(width: 2),
                        Expanded(flex: chance.defendingPercent.clamp(1, 99), child: Container(color: Palette.team(repo.teams[chance.chasingTeam == 0 ? m.teamB : m.teamA]?.colorIndex ?? 1))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(context.tr('win_chance_short', {'team': repo.teams[chance.chasingTeam == 0 ? m.teamA : m.teamB]?.short ?? '', 'n': chance.chasingPercent}),
                      style: Tx.label(p.text2)),
                ],
              ]),
            ),
            const SizedBox(width: Space.s),
            for (final b in recent) Padding(padding: const EdgeInsets.only(left: 4), child: BallChip(b.label)),
          ]),
        ]),
      ),
    );
  }
}

/// Compact card for a finished match.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.m, required this.st});
  final MatchRecord m;
  final MatchState st;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final r = st.result;
    Widget row(int t) {
      final team = repo.teams[t == 0 ? m.teamA : m.teamB];
      Innings? i;
      for (final x in st.innings) {
        if (x.battingTeam == t) i = x;
      }
      final won = r?.winner == t;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Crest(logo: team?.logo, color: Palette.team(team?.colorIndex ?? 0), size: 20),
          const SizedBox(width: Space.s),
          Expanded(child: Text(team?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(won ? p.text : p.text2, w: won ? FontWeight.w800 : FontWeight.w600))),
          const SizedBox(width: Space.s),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(i == null ? '-' : '${i.runs}/${i.wickets}', style: Tx.score(20, won ? p.text : p.text2, w: FontWeight.w800)),
                if (i != null) Text(' (${i.overs})', style: Tx.label(p.text2)),
              ]),
            ),
          ),
        ]),
      );
    }

    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(m.firstBatting),
        row(1 - m.firstBatting),
        Text(
          '${st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB))} · ${agoText(context, m.updatedAt)}',
          maxLines: 2,
          style: Tx.small(p.win, w: FontWeight.w700),
        ),
      ]),
    );
  }
}
