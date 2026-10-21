// Set up a new match: two teams, squads, overs and toss.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'help.dart';
import 'match_centre_screen.dart';
import '../widgets/online_cards.dart';
import 'scoring_screen.dart';
import 'scoring_sheets.dart';
import 'team_screen.dart';

class NewMatchScreen extends StatefulWidget {
  const NewMatchScreen({super.key, this.tournamentId, this.fixtureId, this.teamA, this.teamB, this.overs, this.title, this.venue});

  /// Set when starting a tournament fixture: teams and overs are then fixed.
  final String? tournamentId;
  final String? fixtureId;
  final String? teamA;
  final String? teamB;
  final int? overs;
  final String? title;
  final String? venue;

  bool get fromFixture => fixtureId != null;

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  String? _a;
  String? _b;
  final Map<String, Set<String>> _squads = {};
  int _overs = 10;
  int _tossWinner = 0; // 0 = team A
  bool _tossBat = true;
  final _venue = TextEditingController();
  final _title = TextEditingController();
  String? _error;
  bool _later = false; // schedule for later instead of starting now
  DateTime? _when;

  @override
  void initState() {
    super.initState();
    _a = widget.teamA;
    _b = widget.teamB;
    if (widget.overs != null) _overs = widget.overs!;
    _title.text = widget.title ?? '';
    _venue.text = widget.venue ?? '';
  }

  @override
  void dispose() {
    _venue.dispose();
    _title.dispose();
    super.dispose();
  }

  Set<String> _squad(Team t) => _squads.putIfAbsent(t.id, () => t.playerIds.toSet());

  Future<void> _pickTeam(bool first) async {
    final repo = context.repo;
    final other = first ? _b : _a;
    final id = await showAppSheet<String>(context, (ctx) {
      final p = Palette.of(ctx);
      final teams = repo.teamList.where((t) => t.id != other).toList();
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(ctx.tr('choose_team')),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: Space.edge), children: [
              for (final t in teams)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () => Navigator.pop(ctx, t.id),
                    child: Row(children: [
                      Crest(logo: t.logo, color: Palette.team(t.colorIndex), text: t.short, size: 30),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(t.name, style: Tx.body(p.text, w: FontWeight.w700))),
                      Text(ctx.tr('players_n', {'n': t.playerIds.length}), style: Tx.label(p.text2)),
                    ]),
                  ),
                ),
              if (teams.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Text(ctx.tr('no_teams_yet'), textAlign: TextAlign.center, style: Tx.body(p.text2)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
            child: GoldButton(label: ctx.tr('create_new_team'), icon: Icons.add_rounded, onPressed: () => Navigator.pop(ctx, '__new__')),
          ),
        ]),
      );
    });
    if (!mounted || id == null) return;
    var chosen = id;
    if (id == '__new__') {
      final created = await openTeamEditor(context);
      if (!mounted || created == null) return;
      chosen = created;
    }
    setState(() {
      if (first) {
        _a = chosen;
      } else {
        _b = chosen;
      }
      _error = null;
    });
  }

  Future<void> _editSquad(Team t) async {
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          final p = Palette.of(ctx);
          final sel = _squad(t);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetTitle(ctx.tr('playing_squad'), subtitle: '${t.name} · ${ctx.tr('selected_n', {'n': sel.length})}'),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: Space.edge), children: [
                  for (final id in t.playerIds)
                    CheckboxListTile(
                      value: sel.contains(id),
                      activeColor: p.gold,
                      checkColor: const Color(0xFF0B1220),
                      title: Text(context.repo.playerName(id), style: Tx.body(p.text, w: FontWeight.w600)),
                      onChanged: (v) {
                        setSheet(() => v == true ? sel.add(id) : sel.remove(id));
                        setState(() {});
                      },
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: GoldButton(label: ctx.tr('done'), onPressed: () => Navigator.pop(ctx)),
              ),
            ]),
          );
        }));
  }

  void _start() {
    final repo = context.repo;
    final a = _a == null ? null : repo.teams[_a];
    final b = _b == null ? null : repo.teams[_b];
    if (a == null || b == null) {
      setState(() => _error = context.tr('pick_both_teams'));
      return;
    }
    final pa = a.playerIds.where(_squad(a).contains).toList();
    final pb = b.playerIds.where(_squad(b).contains).toList();
    if (pa.length < 2 || pb.length < 2) {
      setState(() => _error = context.tr('two_players_each'));
      return;
    }
    if (_later && _when == null) {
      setState(() => _error = context.tr('pick_date_time'));
      return;
    }
    final winner = _tossWinner == 0 ? a : b;
    final first = _later ? 0 : (_tossBat ? _tossWinner : 1 - _tossWinner);
    final toss = _later ? '' : context.tr(_tossBat ? 'toss_bat' : 'toss_bowl', {'team': winner.name});
    final m = repo.createMatch(
      a: a,
      b: b,
      playersA: pa,
      playersB: pb,
      overs: _overs,
      firstBatting: first,
      venue: _venue.text.trim(),
      title: _title.text.trim(),
      tossText: toss,
      tournamentId: widget.tournamentId,
      fixtureId: widget.fixtureId,
      scheduledAt: _later ? _when : null,
    );
    if (_later) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('match_scheduled', {'t': whenText(context, _when!)}))));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id)));
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id)));
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final start = _when ?? DateTime(now.year, now.month, now.day + 1, 7);
    final d = await showDatePicker(context: context, initialDate: start, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final a = _a == null ? null : repo.teams[_a];
        final b = _b == null ? null : repo.teams[_b];

        Widget teamSlot(Team? t, bool first) {
          return AppCard(
            onTap: widget.fromFixture ? null : () => _pickTeam(first),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              if (t == null)
                Container(
                  width: 36,
                  height: 40,
                  decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.add_rounded, color: p.goldText),
                )
              else
                Crest(logo: t.logo, color: Palette.team(t.colorIndex), text: t.short, size: 36),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t?.name ?? (first ? context.tr('choose_team_a') : context.tr('choose_team_b')),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(t == null ? p.text2 : p.text, w: FontWeight.w800)),
                  if (t != null) Text(context.tr('playing_n_of_m', {'n': _squad(t).length, 'm': t.playerIds.length}), style: Tx.label(p.text2)),
                ]),
              ),
              if (t != null)
                TextButton(
                  onPressed: () => _editSquad(t),
                  style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(48, 44)),
                  child: Text(context.tr('squad')),
                ),
            ]),
          );
        }

        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
                child: Row(children: [
                  IconBtn(icon: Icons.close_rounded, tooltip: context.tr('close'), onPressed: () => Navigator.maybePop(context)),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(context.tr('new_match'), style: Tx.title(p.text).copyWith(fontSize: 20))),
                  IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'new_match')),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.xl), children: [
                  Segmented<bool>(
                    values: const [false, true],
                    labels: [context.tr('start_now'), context.tr('schedule_later')],
                    selected: _later,
                    onChanged: (v) => setState(() => _later = v),
                  ),
                  if (_later) ...[
                    const SizedBox(height: Space.s),
                    AppCard(
                      onTap: _pickWhen,
                      child: Row(children: [
                        Icon(Icons.event_rounded, color: p.goldText),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Text(_when == null ? context.tr('pick_date_time') : whenText(context, _when!),
                              style: Tx.body(_when == null ? p.text2 : p.text, w: FontWeight.w800)),
                        ),
                        Icon(Icons.edit_calendar_rounded, color: p.text2),
                      ]),
                    ),
                  ],
                  const SizedBox(height: Space.m),
                  teamSlot(a, true),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(child: Text(context.tr('vs'), style: Tx.score(18, p.text2, w: FontWeight.w800))),
                  ),
                  teamSlot(b, false),
                  const SizedBox(height: Space.xl),
                  if (widget.fromFixture)
                    AppCard(
                      child: Row(children: [
                        Icon(Icons.emoji_events_rounded, color: p.goldText),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text(context.tr('fixture_settings', {'n': _overs}), style: Tx.small(p.text, w: FontWeight.w700))),
                      ]),
                    )
                  else ...[
                  Text(context.tr('overs_per_side'), style: Tx.section(p.text).copyWith(fontSize: 15)),
                  const SizedBox(height: Space.s),
                  Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                    for (final o in const [5, 6, 8, 10, 12, 15, 20])
                      ChoiceChipX(label: '$o', selected: _overs == o, onTap: () => setState(() => _overs = o)),
                  ]),
                  const SizedBox(height: Space.s),
                  Row(children: [
                    Expanded(child: Text(context.tr('other_overs'), style: Tx.small(p.text2))),
                    IconBtn(icon: Icons.remove_rounded, tooltip: context.tr('fewer_overs'), onPressed: _overs > 1 ? () => setState(() => _overs--) : null),
                    SizedBox(width: 48, child: Text('$_overs', textAlign: TextAlign.center, style: Tx.score(24, p.text, w: FontWeight.w800))),
                    IconBtn(icon: Icons.add_rounded, tooltip: context.tr('more_overs'), onPressed: _overs < 50 ? () => setState(() => _overs++) : null),
                  ]),
                  ],
                  if (a != null && b != null && !_later) ...[
                    const SizedBox(height: Space.xl),
                    Text(context.tr('toss'), style: Tx.section(p.text).copyWith(fontSize: 15)),
                    const SizedBox(height: Space.s),
                    Text(context.tr('who_won_toss'), style: Tx.label(p.text2)),
                    const SizedBox(height: 6),
                    Segmented<int>(values: const [0, 1], labels: [a.name, b.name], selected: _tossWinner, onChanged: (v) => setState(() => _tossWinner = v)),
                    const SizedBox(height: Space.m),
                    Text(context.tr('chose_to'), style: Tx.label(p.text2)),
                    const SizedBox(height: 6),
                    Segmented<bool>(values: const [true, false], labels: [context.tr('bat'), context.tr('bowl')], selected: _tossBat, onChanged: (v) => setState(() => _tossBat = v)),
                  ],
                  const SizedBox(height: Space.xl),
                  Text(context.tr('match_details_optional'), style: Tx.section(p.text).copyWith(fontSize: 15)),
                  const SizedBox(height: Space.s),
                  TextField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: context.tr('match_title_hint'))),
                  const SizedBox(height: Space.s),
                  TextField(controller: _venue, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('ground_hint'))),
                  if (_error != null) ...[
                    const SizedBox(height: Space.m),
                    Text(_error!, style: Tx.small(p.liveText, w: FontWeight.w700)),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
                child: GoldButton(
                  label: context.tr(_later ? 'schedule_match' : 'start_match'),
                  icon: _later ? Icons.event_available_rounded : Icons.sports_cricket_rounded,
                  onPressed: _start,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
