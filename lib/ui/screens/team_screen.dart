// Create a team or edit its players.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

/// Opens the team editor. Returns the team id when a new team was created.
Future<String?> openTeamEditor(BuildContext context, {String? teamId}) {
  return Navigator.push<String>(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: teamId)));
}

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, this.teamId});
  final String? teamId;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late final TextEditingController _name;
  final _player = TextEditingController();
  final _bulk = TextEditingController();
  String? _teamId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teamId = widget.teamId;
    final t = _teamId == null ? null : context.repo.teams[_teamId];
    _name = TextEditingController(text: t?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _player.dispose();
    _bulk.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    final players = _bulk.text.split(RegExp(r'[\n,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (name.isEmpty) {
      setState(() => _error = context.tr('team_name_needed'));
      return;
    }
    if (players.length < 2) {
      setState(() => _error = context.tr('two_players_needed'));
      return;
    }
    final t = context.repo.addTeam(name, playerNames: players);
    Navigator.pop(context, t.id);
  }

  void _addOne(Team t) {
    final n = _player.text.trim();
    if (n.isEmpty) return;
    context.repo.addPlayer(t, n);
    _player.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final team = _teamId == null ? null : repo.teams[_teamId];
        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
                child: Row(children: [
                  IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(team == null ? context.tr('new_team') : team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20))),
                  if (team != null) Crest(color: Palette.team(team.colorIndex), text: team.short, size: 36),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.xl), children: [
                  Text(context.tr('team_name'), style: Tx.label(p.text2)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(hintText: context.tr('team_name_hint')),
                    onSubmitted: team == null ? null : (v) => repo.renameTeam(team, v),
                    onTapOutside: team == null ? null : (_) => repo.renameTeam(team, _name.text),
                  ),
                  const SizedBox(height: Space.l),
                  if (team == null) ...[
                    Text(context.tr('players_one_per_line'), style: Tx.label(p.text2)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bulk,
                      minLines: 6,
                      maxLines: 14,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(hintText: context.tr('players_hint')),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.s),
                      Text(_error!, style: Tx.small(p.liveText)),
                    ],
                    const SizedBox(height: Space.l),
                    GoldButton(label: context.tr('save_team'), icon: Icons.check_rounded, onPressed: _create),
                  ] else ...[
                    Row(children: [
                      Expanded(child: Text(context.tr('players_n', {'n': team.playerIds.length}), style: Tx.section(p.text).copyWith(fontSize: 15))),
                      Text(context.tr('left_handed_q'), style: Tx.label(p.text2)),
                    ]),
                    const SizedBox(height: Space.s),
                    for (final id in team.playerIds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: AppCard(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: Row(children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: id))),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(repo.playerName(id), style: Tx.small(p.text, w: FontWeight.w700).copyWith(fontSize: 14)),
                                ),
                              ),
                            ),
                            Semantics(
                              label: context.tr('left_handed_for', {'name': repo.playerName(id)}),
                              child: Switch(
                                value: repo.players[id]?.leftHanded ?? false,
                                onChanged: (v) {
                                  final pl = repo.players[id];
                                  if (pl != null) repo.updatePlayer(pl, leftHanded: v);
                                },
                              ),
                            ),
                          ]),
                        ),
                      ),
                    const SizedBox(height: Space.s),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _player,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(hintText: context.tr('add_player')),
                          onSubmitted: (_) => _addOne(team),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      GoldButton(label: context.tr('add'), onPressed: () => _addOne(team), height: 50),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
