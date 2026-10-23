// Create a team or edit it: logo (ready designs or a cropped photo), colour,
// and the squad — every player's photo and details right here.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/photos.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import '../widgets/player_details.dart';
import '../widgets/team_logo.dart';

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
  bool _createdHere = false;
  String? _pendingLogo; // logo picked before the team is saved
  late int _color;

  @override
  void initState() {
    super.initState();
    _teamId = widget.teamId;
    final t = _teamId == null ? null : context.repo.teams[_teamId];
    _name = TextEditingController(text: t?.name ?? '');
    _color = t?.colorIndex ?? context.repo.teams.length % 8;
  }

  @override
  void dispose() {
    _name.dispose();
    _player.dispose();
    _bulk.dispose();
    super.dispose();
  }

  String get _letters => initials(_name.text.trim().isEmpty ? '?' : _name.text);

  Future<void> _create() async {
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
    final repo = context.repo;
    final t = repo.addTeam(name, playerNames: players);
    repo.setTeamColor(t, _color);
    if (_pendingLogo != null) await repo.setTeamLogo(t, _pendingLogo);
    if (!mounted) return;
    setState(() {
      _teamId = t.id;
      _createdHere = true;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('team_saved_add_details'))));
  }

  Future<void> _logo(Team? team) async {
    if (team != null) return editTeamLogo(context, team.id);
    final failed = context.tr('photo_failed');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await pickLogo(
        context,
        letters: _letters,
        prefix: 'logo_new',
        current: Crest(logo: _pendingLogo, color: Palette.team(_color), text: _letters, size: 80),
        canRemove: _pendingLogo != null,
      );
      if (name == null || !mounted) return;
      final old = _pendingLogo;
      setState(() => _pendingLogo = name.isEmpty ? null : name);
      if (old != null && old != _pendingLogo) await PhotoStore.delete(old);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  void _addOne(Team t) {
    final n = _player.text.trim();
    if (n.isEmpty) return;
    context.repo.addPlayer(t, n);
    _player.clear();
  }

  void _close() => Navigator.pop(context, _createdHere ? _teamId : null);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListenableBuilder(
        listenable: context.repo,
        builder: (context, _) {
          final repo = context.repo;
          final team = _teamId == null ? null : repo.teams[_teamId];
          final color = team?.colorIndex ?? _color;
          return Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
                  child: Row(children: [
                    IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: _close),
                    const SizedBox(width: Space.m),
                    Expanded(child: Text(team == null ? context.tr('new_team') : team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20))),
                  ]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.xl), children: [
                    // logo + name
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Pressable(
                        onTap: () => _logo(team),
                        semanticLabel: context.tr('team_logo'),
                        child: SizedBox(
                          width: 76,
                          height: 82,
                          child: Stack(children: [
                            Crest(logo: team?.logo ?? _pendingLogo, color: Palette.team(color), text: team?.short ?? _letters, size: 72),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(color: p.gold, shape: BoxShape.circle, border: Border.all(color: p.bg, width: 2)),
                                child: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF0B1220)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.tr('team_name'), style: Tx.label(p.text2)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(hintText: context.tr('team_name_hint')),
                            onChanged: team == null ? (_) => setState(() {}) : null,
                            onSubmitted: team == null ? null : (v) => repo.renameTeam(team, v),
                            onTapOutside: team == null ? null : (_) => repo.renameTeam(team, _name.text),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: Space.s),
                    OutlineBtn(
                      label: (team?.logo ?? _pendingLogo) == null ? context.tr('add_team_logo') : context.tr('change_team_logo'),
                      icon: Icons.add_photo_alternate_outlined,
                      height: 46,
                      onPressed: () => _logo(team),
                    ),
                    const SizedBox(height: Space.m),
                    Text(context.tr('team_colour'), style: Tx.label(p.text2)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var i = 0; i < 8; i++)
                        Semantics(
                          button: true,
                          selected: color == i,
                          label: '${context.tr('team_colour')} ${i + 1}',
                          child: GestureDetector(
                            onTap: () {
                              if (team != null) {
                                repo.setTeamColor(team, i);
                              } else {
                                setState(() => _color = i);
                              }
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Palette.team(i),
                                shape: BoxShape.circle,
                                border: Border.all(color: color == i ? p.goldText : Colors.transparent, width: 3),
                              ),
                            ),
                          ),
                        ),
                    ]),
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
                      const SizedBox(height: 6),
                      Text(context.tr('details_after_save'), style: Tx.small(p.text2)),
                      if (_error != null) ...[
                        const SizedBox(height: Space.s),
                        Text(_error!, style: Tx.small(p.liveText)),
                      ],
                      const SizedBox(height: Space.l),
                      GoldButton(label: context.tr('save_team_next'), icon: Icons.arrow_forward_rounded, onPressed: _create),
                    ] else ...[
                      Text(context.tr('squad_n', {'n': team.playerIds.length}), style: Tx.section(p.text).copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(context.tr('squad_tap_help'), style: Tx.small(p.text2)),
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
                      const SizedBox(height: Space.s),
                      for (final id in team.playerIds) _row(team, id),
                      if (_createdHere) ...[
                        const SizedBox(height: Space.m),
                        GoldButton(label: context.tr('squad_ready_n', {'n': team.playerIds.length}), icon: Icons.check_rounded, onPressed: _close),
                      ],
                    ],
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _row(Team team, String id) {
    final p = Palette.of(context);
    final repo = context.repo;
    final pl = repo.players[id];
    if (pl == null) return const SizedBox.shrink();
    final line = playerLine(context, pl);
    final badge = team.captain == id ? 'C' : (team.viceCaptain == id ? 'VC' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        onTap: () => editPlayerDetails(context, id, team: team),
        child: Row(children: [
          EditableAvatar(playerId: id, size: 40, color: Palette.team(team.colorIndex)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800))),
                if (badge != null) ...[const SizedBox(width: 6), Tag(badge, color: p.goldText)],
              ]),
              Text(line.isEmpty ? context.tr('add_details') : line,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(line.isEmpty ? p.liveText : p.text2)),
            ]),
          ),
          IconButton(
            tooltip: context.tr('edit_details_for', {'name': pl.name}),
            onPressed: () => editPlayerDetails(context, id, team: team),
            icon: Icon(Icons.edit_rounded, color: p.goldText),
          ),
        ]),
      ),
    );
  }
}
