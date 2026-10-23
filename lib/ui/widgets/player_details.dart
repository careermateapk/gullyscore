// A player's details: photo, name, mobile, role, batting hand, bowling style,
// captain / vice-captain. Opened from the squad list.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../screens/scoring_sheets.dart' show showAppSheet, SheetTitle;
import 'avatar.dart';
import 'common.dart';

const playerRoles = ['Batter', 'Bowler', 'All-rounder', 'Wicket keeper'];
const bowlingStyles = ['Fast', 'Medium', 'Off spin', 'Leg spin', 'Left-arm spin', 'None'];

String roleKey(String v) => 'role_${v.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '_')}';

/// One line about the player for lists, e.g. "Batter · Left hand · Off spin". Empty if nothing set.
String playerLine(BuildContext context, Player p) => [
      if (p.role.isNotEmpty) playerRoles.contains(p.role) ? context.tr(roleKey(p.role)) : p.role,
      if (p.leftHanded) context.tr('left_hand_bat'),
      if (p.bowling.isNotEmpty && p.bowling != 'None') context.tr(roleKey(p.bowling)),
    ].join(' · ');

Future<void> editPlayerDetails(BuildContext context, String playerId, {Team? team}) =>
    showAppSheet<void>(context, (ctx) => _DetailsSheet(playerId: playerId, team: team));

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.playerId, this.team});
  final String playerId;
  final Team? team;
  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final Player _p = context.repo.players[widget.playerId]!;
  late final _name = TextEditingController(text: _p.name);
  late final _phone = TextEditingController(text: _p.phone);
  late String _role = _p.role;
  late bool _left = _p.leftHanded;
  late String _bowl = _p.bowling;
  late bool _cap = widget.team?.captain == _p.id;
  late bool _vc = widget.team?.viceCaptain == _p.id;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    final repo = context.repo;
    repo.updatePlayer(_p, name: _name.text, phone: _phone.text, role: _role, leftHanded: _left, bowling: _bowl);
    final t = widget.team;
    if (t != null) {
      var cap = t.captain;
      var vc = t.viceCaptain;
      if (_cap) {
        cap = _p.id;
      } else if (cap == _p.id) {
        cap = null;
      }
      if (_vc) {
        vc = _p.id;
      } else if (vc == _p.id) {
        vc = null;
      }
      if (cap == vc) vc = null;
      repo.setLeaders(t, captain: cap, viceCaptain: vc);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget label(String k) => Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: 6),
          child: Text(context.tr(k).toUpperCase(), style: Tx.label(p.text2).copyWith(letterSpacing: 0.5)),
        );
    Widget chips(List<String> values, String selected, ValueChanged<String> onPick) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in values) ChoiceChip(label: Text(context.tr(roleKey(v))), selected: selected == v, onSelected: (_) => setState(() => onPick(selected == v ? '' : v))),
        ]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(context.tr('player_details'), subtitle: context.tr('photo_stays_on_phone')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: ListenableBuilder(listenable: context.repo, builder: (context, _) => EditableAvatar(playerId: _p.id, size: 76))),
              const SizedBox(height: Space.m),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.tr('player_name'), prefixIcon: const Icon(Icons.person_outline_rounded)),
              ),
              const SizedBox(height: Space.s),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: context.tr('mobile_optional'), helperText: context.tr('mobile_for_login'), prefixIcon: const Icon(Icons.phone_android_rounded)),
              ),
              label('role'),
              chips(playerRoles, _role, (v) => _role = v),
              label('batting'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: Text(context.tr('right_hand')), selected: !_left, onSelected: (_) => setState(() => _left = false)),
                ChoiceChip(label: Text(context.tr('left_hand')), selected: _left, onSelected: (_) => setState(() => _left = true)),
              ]),
              label('bowling'),
              chips(bowlingStyles, _bowl, (v) => _bowl = v),
              if (widget.team != null) ...[
                label('team_role'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilterChip(
                    label: Text('© ${context.tr('captain')}'),
                    selected: _cap,
                    onSelected: (v) => setState(() {
                      _cap = v;
                      if (v) _vc = false;
                    }),
                  ),
                  FilterChip(
                    label: Text(context.tr('vice_captain')),
                    selected: _vc,
                    onSelected: (v) => setState(() {
                      _vc = v;
                      if (v) _cap = false;
                    }),
                  ),
                ]),
              ],
              const SizedBox(height: Space.l),
              GoldButton(label: context.tr('save'), icon: Icons.check_rounded, onPressed: _save),
            ]),
          ),
        ]),
      ),
    );
  }
}
