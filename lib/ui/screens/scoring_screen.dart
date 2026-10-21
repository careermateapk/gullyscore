// Ball-by-ball scoring. Every tap is saved on the phone straight away.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/engine.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import 'help.dart';
import 'match_centre_screen.dart';
import 'scoring_sheets.dart';
import 'share_card.dart';

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  final _celebration = GlobalKey<CelebrationLayerState>();
  bool _busy = false;

  MatchRecord? get _m => context.repo.matches[widget.matchId];

  void _tick() {
    if (context.settings.haptics) HapticFeedback.selectionClick();
  }

  String _name(String id) => context.repo.playerName(id);

  List<String> _squad(MatchRecord m, int team) => team == 0 ? m.playersA : m.playersB;

  Future<String?> _addPlayer(MatchRecord m, int team, String name) async {
    final repo = context.repo;
    final t = repo.teams[team == 0 ? m.teamA : m.teamB];
    if (t == null) return null;
    final p = repo.addPlayer(t, name);
    _squad(m, team).add(p.id);
    repo.setEvents(m, m.events); // saves the longer squad
    return p.id;
  }

  /// Adds one event and plays a celebration if the new ball deserves one.
  void _add(Map<String, dynamic> e) {
    final m = _m;
    if (m == null) return;
    final repo = context.repo;
    repo.addEvent(m, e);
    if (e['t'] != Ev.ball) return;
    final st = m.state;
    final inn = st.innings.isEmpty ? null : st.innings.last;
    if (inn == null || inn.balls.isEmpty) return;
    final b = inn.balls.last;
    final key = '${inn.number}-${b.index}';
    if (m.celebrated.contains(key)) return;
    Celebration? kind;
    String label = '';
    if (b.isWicket) {
      kind = Celebration.wicket;
      label = context.tr('wicket');
    } else if (b.isSix) {
      kind = Celebration.six;
      label = context.tr('six');
    } else if (b.isFour) {
      kind = Celebration.four;
      label = context.tr('four');
    }
    if (kind != null) {
      repo.markCelebrated(m, key);
      _celebration.currentState?.play(kind, label: label);
    }
  }

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    try {
      await f();
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _runs(MatchRecord m, MatchState st, int r) => _guard(() async {
        _tick();
        final inn = st.current!;
        var extra = <String, dynamic>{};
        if (r > 0 && context.settings.askShotDirection) {
          final striker = context.repo.players[inn.striker];
          final shot = await pickShot(
            context,
            runs: r,
            kind: BallKind.normal,
            strikerName: _name(inn.striker!),
            bowlerName: _name(inn.bowler!),
            leftHanded: striker?.leftHanded ?? false,
          );
          if (shot == null || !mounted) return; // backed out: nothing saved
          extra = shot.toEvent();
        }
        _add({'t': Ev.ball, 'kind': BallKind.normal, 'runs': r, ...extra});
      });

  Future<void> _extra(MatchRecord m, MatchState st, String kind) => _guard(() async {
        _tick();
        final options = switch (kind) {
          BallKind.wide => [0, 1, 2, 3, 4],
          BallKind.noBall => [0, 1, 2, 3, 4, 5, 6],
          _ => [1, 2, 3, 4],
        };
        final sub = switch (kind) {
          BallKind.wide => context.tr('wide_runs_help'),
          BallKind.noBall => context.tr('noball_runs_help'),
          _ => context.tr('bye_runs_help'),
        };
        final r = await pickRuns(context, title: extraTitle(context, kind), subtitle: sub, options: options);
        if (r == null || !mounted) return;
        var extra = <String, dynamic>{};
        final inn = st.current!;
        if (kind == BallKind.noBall && r > 0 && context.settings.askShotDirection) {
          final shot = await pickShot(
            context,
            runs: r,
            kind: kind,
            strikerName: _name(inn.striker!),
            bowlerName: _name(inn.bowler!),
            leftHanded: context.repo.players[inn.striker]?.leftHanded ?? false,
          );
          if (shot == null || !mounted) return;
          extra = shot.toEvent();
        }
        _add({'t': Ev.ball, 'kind': kind, 'runs': r, ...extra});
      });

  Future<void> _wicket(MatchRecord m, MatchState st) => _guard(() async {
        _tick();
        final inn = st.current!;
        final w = await pickWicket(
          context,
          striker: inn.striker!,
          nonStriker: inn.nonStriker!,
          fielders: _squad(m, st.bowlingTeamNow),
          name: _name,
        );
        if (w == null || !mounted) return;
        _add({
          't': Ev.ball,
          'kind': BallKind.normal,
          'runs': w.runs,
          'out': {'kind': w.kind, 'player': w.outPlayer, if (w.fielder != null) 'fielder': w.fielder},
        });
      });

  void _undo(MatchRecord m) {
    _tick();
    if (!m.events.any((e) => e['t'] == Ev.ball)) return;
    context.repo.setEvents(m, undoLast(m.events));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr('ball_undone')), duration: const Duration(seconds: 2)));
  }

  Future<void> _startInnings(MatchRecord m, MatchState st) => _guard(() async {
        final bat = st.battingTeamNow;
        final bowl = 1 - bat;
        final batTeam = context.repo.teamName(bat == 0 ? m.teamA : m.teamB);
        final striker = await pickPlayer(context,
            title: context.tr('pick_striker'),
            subtitle: batTeam,
            ids: _squad(m, bat),
            name: _name,
            onAdd: (n) => _addPlayer(m, bat, n));
        if (striker == null || !mounted) return;
        final non = await pickPlayer(context,
            title: context.tr('pick_non_striker'),
            subtitle: batTeam,
            ids: _squad(m, bat).where((p) => p != striker).toList(),
            name: _name,
            onAdd: (n) => _addPlayer(m, bat, n));
        if (non == null || !mounted) return;
        final bowler = await pickPlayer(context,
            title: context.tr('pick_bowler'),
            subtitle: context.repo.teamName(bowl == 0 ? m.teamA : m.teamB),
            ids: _squad(m, bowl),
            name: _name,
            onAdd: (n) => _addPlayer(m, bowl, n));
        if (bowler == null || !mounted) return;
        _add({'t': Ev.start, 'striker': striker, 'nonStriker': non, 'bowler': bowler});
      });

  Future<void> _newBatter(MatchRecord m, MatchState st) => _guard(() async {
        final bat = st.battingTeamNow;
        final id = await pickPlayer(context,
            title: context.tr('pick_new_batter'),
            ids: st.availableBatters(),
            name: _name,
            onAdd: (n) => _addPlayer(m, bat, n));
        if (id == null || !mounted) return;
        _add({'t': Ev.batter, 'player': id});
      });

  Future<void> _newBowler(MatchRecord m, MatchState st) => _guard(() async {
        final bowl = st.bowlingTeamNow;
        final last = st.current?.lastOverBowler;
        final id = await pickPlayer(context,
            title: context.tr('pick_next_bowler'),
            ids: _squad(m, bowl),
            name: _name,
            disabled: last == null ? const <String>{} : {last},
            disabledReason: context.tr('bowled_last_over'),
            onAdd: (n) => _addPlayer(m, bowl, n));
        if (id == null || !mounted) return;
        _add({'t': Ev.bowler, 'player': id});
      });

  Future<void> _endInnings(MatchRecord m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('end_innings_q')),
        content: Text(ctx.tr('end_innings_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('end_innings'))),
        ],
      ),
    );
    if (ok == true && mounted) _add({'t': Ev.endInnings});
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final m = _m;
        final p = Palette.of(context);
        if (m == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: p.bg),
            body: Center(child: EmptyState(icon: Icons.search_off_rounded, title: context.tr('match_not_found'), body: context.tr('match_not_found_body'))),
          );
        }
        final st = m.state;
        final inn = st.current;
        final batTeam = st.battingTeamNow;
        final teamName = context.repo.teamName(batTeam == 0 ? m.teamA : m.teamB);
        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Column(children: [
              _TopBar(
                title: inn == null || inn.ended ? context.tr('scoring') : context.tr('scoring_team_innings', {'team': teamName}),
                onHelp: () => showHelp(context, 'scoring'),
                menu: PopupMenuButton<String>(
                  tooltip: context.tr('more'),
                  icon: Icon(Icons.more_vert_rounded, color: p.text),
                  onSelected: (v) {
                    if (v == 'centre') Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id)));
                    if (v == 'end') _endInnings(m);
                    if (v == 'share') shareMatchCard(context, m);
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'centre', child: Text(ctx.tr('match_centre'))),
                    PopupMenuItem(value: 'share', child: Text(ctx.tr('share_score'))),
                    if (inn != null && !inn.ended && !st.finished) PopupMenuItem(value: 'end', child: Text(ctx.tr('end_innings'))),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Space.l),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0),
                      child: CelebrationLayer(key: _celebration, child: _ScoreHero(m: m, st: st)),
                    ),
                    ..._body(m, st),
                  ],
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _body(MatchRecord m, MatchState st) {
    final p = Palette.of(context);
    final inn = st.current;
    switch (st.nextStep) {
      case NextStep.finished:
        return [
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GoldButton(
                label: context.tr('open_match_centre'),
                icon: Icons.insights_rounded,
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
              ),
              const SizedBox(height: Space.s),
              OutlineBtn(label: context.tr('share_score'), icon: Icons.share_rounded, onPressed: () => shareMatchCard(context, m)),
              const SizedBox(height: Space.s),
              OutlineBtn(label: context.tr('undo_last_ball'), icon: Icons.undo_rounded, onPressed: () => _undo(m)),
            ]),
          ),
        ];
      case NextStep.startInnings:
        final second = st.innings.isNotEmpty;
        return [
          _StepCard(
            icon: Icons.sports_cricket_rounded,
            title: second ? context.tr('innings_break') : context.tr('lets_start'),
            body: second
                ? context.tr('target_body', {
                    'team': context.repo.teamName(st.battingTeamNow == 0 ? m.teamA : m.teamB),
                    'n': st.innings.first.runs + 1,
                    'overs': m.overs,
                  })
                : context.tr('pick_openers_body'),
            action: context.tr('pick_openers'),
            onAction: () => _startInnings(m, st),
          ),
          if (second)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: OutlineBtn(label: context.tr('undo_last_ball'), icon: Icons.undo_rounded, onPressed: () => _undo(m)),
            ),
        ];
      case NextStep.newBatter:
        return [
          _StepCard(
            icon: Icons.person_add_alt_1_rounded,
            title: context.tr('new_batter'),
            body: context.tr('new_batter_body'),
            action: context.tr('pick_new_batter'),
            onAction: () => _newBatter(m, st),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: OutlineBtn(label: context.tr('undo_last_ball'), icon: Icons.undo_rounded, onPressed: () => _undo(m)),
          ),
        ];
      case NextStep.newBowler:
        return [
          _PlayersRow(inn: inn!, name: _name),
          _StepCard(
            icon: Icons.sports_baseball_rounded,
            title: context.tr('over_complete'),
            body: context.tr('over_complete_body'),
            action: context.tr('pick_next_bowler'),
            onAction: () => _newBowler(m, st),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: OutlineBtn(label: context.tr('undo_last_ball'), icon: Icons.undo_rounded, onPressed: () => _undo(m)),
          ),
        ];
      case NextStep.ball:
        final i = inn!;
        return [
          _PlayersRow(inn: i, name: _name),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
            child: Row(children: [
              Text(context.tr('over_n', {'n': i.legalBalls ~/ 6 + 1}), style: Tx.label(p.text2)),
              const SizedBox(width: Space.s),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(children: [
                    for (final b in _currentOverBalls(i)) Padding(padding: const EdgeInsets.only(right: 6), child: BallChip(b.label)),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
            child: _Keypad(
              onRuns: (r) => _runs(m, st, r),
              onExtra: (k) => _extra(m, st, k),
              onWicket: () => _wicket(m, st),
              onUndo: m.events.any((e) => e['t'] == Ev.ball) ? () => _undo(m) : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
            child: Row(children: [
              Expanded(
                child: OutlineBtn(
                  label: context.tr('swap_strike'),
                  icon: Icons.swap_horiz_rounded,
                  height: 44,
                  onPressed: () {
                    _tick();
                    _add({'t': Ev.swap});
                  },
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlineBtn(
                  label: context.tr('five_runs'),
                  height: 44,
                  onPressed: () => _runs(m, st, 5),
                ),
              ),
            ]),
          ),
        ];
    }
  }

  /// Balls of the over being bowled now (empty right after an over ends).
  List<BallLog> _currentOverBalls(Innings i) {
    final over = i.legalBalls ~/ 6;
    return i.balls.where((b) => b.over == over).toList();
  }
}

// ------------------------------------------------------------ parts

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onHelp, required this.menu});
  final String title;
  final VoidCallback onHelp;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.s, Space.s),
      child: Row(children: [
        IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
            Row(children: [
              Icon(Icons.phone_android_rounded, size: 13, color: p.win),
              const SizedBox(width: 4),
              Flexible(child: Text(context.tr('saved_on_phone'), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2))),
            ]),
          ]),
        ),
        IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: onHelp),
        menu,
      ]),
    );
  }
}

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.m, required this.st});
  final MatchRecord m;
  final MatchState st;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final inn = st.current;
    final bat = inn?.battingTeam ?? st.battingTeamNow;
    final team = repo.teams[bat == 0 ? m.teamA : m.teamB];
    final runs = inn?.runs ?? 0;
    final wkts = inn?.wickets ?? 0;
    String status;
    if (st.finished) {
      status = st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB));
    } else if (inn != null && inn.number == 1 && !inn.ended) {
      final need = st.runsNeeded ?? 0;
      final left = st.ballsLeft ?? 0;
      status = context.tr('need_runs', {'n': need, 'b': left});
    } else if (inn != null && !inn.ended) {
      status = context.tr('crr_value', {'v': inn.runRate.toStringAsFixed(2)});
    } else {
      status = m.tossText.isEmpty ? context.tr('overs_match', {'n': m.overs}) : m.tossText;
    }
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Crest(color: Palette.team(team?.colorIndex ?? 0), text: team?.short ?? '', size: 40),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
              Text(st.finished ? context.tr('result') : context.tr('batting'), style: Tx.label(p.text2)),
            ]),
          ),
          const SizedBox(width: Space.s),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                AnimatedScore(text: '$runs/$wkts', style: Tx.score(52, p.text)),
                const SizedBox(height: 2),
                Text(context.tr('overs_of', {'o': inn?.overs ?? '0.0', 'n': m.overs}), style: Tx.score(17, p.text2, w: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: Space.m),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Text(status, style: Tx.body(p.goldText, w: FontWeight.w800).copyWith(fontSize: 14)),
        ),
      ]),
    );
  }
}

class _PlayersRow extends StatelessWidget {
  const _PlayersRow({required this.inn, required this.name});
  final Innings inn;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget batter(String? id, bool strike) {
      final c = id == null ? null : inn.batters[id];
      return Expanded(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderColor: strike ? p.gold : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(strike ? context.tr('on_strike') : context.tr('non_striker'), style: Tx.label(p.text2)),
            const SizedBox(height: 2),
            Text(id == null ? '—' : name(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 14)),
            if (c != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('${c.runs} (${c.balls})', style: Tx.score(20, p.text, w: FontWeight.w800)),
              ),
          ]),
        ),
      );
    }

    final bw = inn.bowler == null ? null : inn.bowlers[inn.bowler];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
      child: Column(children: [
        Row(children: [batter(inn.striker, true), const SizedBox(width: Space.s), batter(inn.nonStriker, false)]),
        if (bw != null) ...[
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${context.tr('bowling')} ', style: Tx.label(p.text2)),
                  TextSpan(text: name(bw.id), style: Tx.small(p.text, w: FontWeight.w800)),
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
                child: Text('${bw.overs}-${bw.maidens}-${bw.runs}-${bw.wickets}', style: Tx.score(17, p.text, w: FontWeight.w800)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.icon, required this.title, required this.body, required this.action, required this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
      child: AppCard(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: p.goldText, size: 22),
            ),
            const SizedBox(width: Space.m),
            Expanded(child: Text(title, style: Tx.section(p.text))),
          ]),
          const SizedBox(height: Space.s),
          Text(body, style: Tx.body(p.text2)),
          const SizedBox(height: Space.l),
          GoldButton(label: action, onPressed: onAction),
        ]),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onRuns, required this.onExtra, required this.onWicket, required this.onUndo});
  final ValueChanged<int> onRuns;
  final ValueChanged<String> onExtra;
  final VoidCallback onWicket;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget key(String label, VoidCallback? onTap, {bool number = false, Color? fg, Color? bg, Color? border, IconData? icon, String? semantic, String? id}) {
      return Pressable(
        key: ValueKey('pad_${id ?? label}'),
        onTap: onTap,
        semanticLabel: semantic ?? label,
        child: ExcludeSemantics(
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg ?? p.surface,
              borderRadius: BorderRadius.circular(Corners.button),
              border: Border.all(color: border ?? p.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg ?? p.text), const SizedBox(width: 4)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: number ? Tx.score(30, fg ?? p.text, w: FontWeight.w800) : TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg ?? p.text),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    final rows = [
      [
        key('0', () => onRuns(0), number: true, semantic: context.tr('dot_ball')),
        key('1', () => onRuns(1), number: true),
        key('2', () => onRuns(2), number: true),
        key('3', () => onRuns(3), number: true),
      ],
      [
        key('4', () => onRuns(4), number: true, fg: p.goldText, bg: p.gold.withValues(alpha: 0.12), border: p.gold.withValues(alpha: 0.5), semantic: context.tr('four')),
        key('6', () => onRuns(6), number: true, fg: p.six, bg: p.six.withValues(alpha: 0.16), border: p.six, semantic: context.tr('six')),
        key(context.tr('wide'), () => onExtra(BallKind.wide), id: 'wide'),
        key(context.tr('no_ball'), () => onExtra(BallKind.noBall), id: 'noball'),
      ],
      [
        key(context.tr('bye'), () => onExtra(BallKind.bye), id: 'bye'),
        key(context.tr('leg_bye'), () => onExtra(BallKind.legBye), id: 'legbye'),
        key(context.tr('wicket'), onWicket, id: 'wicket', fg: p.liveText, bg: p.live.withValues(alpha: 0.14), border: p.live.withValues(alpha: 0.5)),
        key(context.tr('undo'), onUndo, icon: Icons.undo_rounded, id: 'undo'),
      ],
    ];
    return Column(children: [
      for (var r = 0; r < rows.length; r++) ...[
        if (r > 0) const SizedBox(height: Space.s),
        Row(children: [
          for (var c = 0; c < rows[r].length; c++) ...[
            if (c > 0) const SizedBox(width: Space.s),
            Expanded(child: rows[r][c]),
          ],
        ]),
      ],
    ]);
  }
}
