// Bottom sheets used while scoring: pick a player, extras, wicket, shot.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../scoring/commentary.dart';
import '../../scoring/engine.dart';
import '../widgets/common.dart';
import '../widgets/ground_map.dart';

Future<T?> showAppSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.m),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Tx.section(p.text).copyWith(fontSize: 19)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: Tx.small(p.text2))],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

// ------------------------------------------------------------ player picker

/// Lets the scorer pick a player, or add one who was missing from the list.
Future<String?> pickPlayer(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> ids,
  required String Function(String) name,
  Set<String> disabled = const {},
  String? disabledReason,
  Future<String?> Function(String name)? onAdd,
}) {
  return showAppSheet<String>(context, (ctx) => _PlayerPicker(
        title: title,
        subtitle: subtitle,
        ids: ids,
        name: name,
        disabled: disabled,
        disabledReason: disabledReason,
        onAdd: onAdd,
      ));
}

class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker({required this.title, this.subtitle, required this.ids, required this.name, required this.disabled, this.disabledReason, this.onAdd});
  final String title;
  final String? subtitle;
  final List<String> ids;
  final String Function(String) name;
  final Set<String> disabled;
  final String? disabledReason;
  final Future<String?> Function(String name)? onAdd;

  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final n = _ctrl.text.trim();
    if (n.isEmpty || widget.onAdd == null) return;
    final id = await widget.onAdd!(n);
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(widget.title, subtitle: widget.subtitle),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            children: [
              for (final id in widget.ids)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: widget.disabled.contains(id) ? null : () => Navigator.pop(context, id),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: p.raised,
                        child: Text(initialsOf(widget.name(id)), style: Tx.label(p.text, w: FontWeight.w800)),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(widget.name(id), style: Tx.body(p.text, w: FontWeight.w700))),
                      if (widget.disabled.contains(id) && widget.disabledReason != null)
                        Flexible(child: Text(widget.disabledReason!, textAlign: TextAlign.right, style: Tx.label(p.text2))),
                    ]),
                  ),
                ),
              if (widget.ids.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Text(context.tr('no_players_left'), textAlign: TextAlign.center, style: Tx.body(p.text2)),
                ),
            ],
          ),
        ),
        if (widget.onAdd != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(hintText: context.tr('add_missing_player')),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: Space.s),
              GoldButton(label: context.tr('add'), onPressed: _add, height: 50),
            ]),
          )
        else
          const SizedBox(height: Space.l),
      ]),
    );
  }
}

String initialsOf(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  if (w.length == 1) return w.first.substring(0, 1).toUpperCase();
  return (w[0][0] + w[1][0]).toUpperCase();
}

// ------------------------------------------------------------ runs picker

Future<int?> pickRuns(BuildContext context, {required String title, String? subtitle, required List<int> options, String Function(int)? label}) {
  return showAppSheet<int>(context, (ctx) {
    final p = Palette.of(ctx);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(title, subtitle: subtitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: Space.s,
            crossAxisSpacing: Space.s,
            childAspectRatio: 1.25,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final r in options)
                Pressable(
                  onTap: () => Navigator.pop(ctx, r),
                  semanticLabel: label?.call(r) ?? '$r',
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Corners.button), border: Border.all(color: p.line)),
                    child: Text(label?.call(r) ?? '$r', style: Tx.score(26, p.text, w: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  });
}

// ------------------------------------------------------------ wicket

class WicketResult {
  WicketResult({required this.kind, required this.outPlayer, this.fielder, this.runs = 0});
  final String kind;
  final String outPlayer;
  final String? fielder;
  final int runs;
}

Future<WicketResult?> pickWicket(
  BuildContext context, {
  required String striker,
  required String nonStriker,
  required List<String> fielders,
  required String Function(String) name,
}) {
  return showAppSheet<WicketResult>(context, (ctx) => _WicketSheet(striker: striker, nonStriker: nonStriker, fielders: fielders, name: name));
}

class _WicketSheet extends StatefulWidget {
  const _WicketSheet({required this.striker, required this.nonStriker, required this.fielders, required this.name});
  final String striker;
  final String nonStriker;
  final List<String> fielders;
  final String Function(String) name;

  @override
  State<_WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<_WicketSheet> {
  String? _kind;
  late String _out = widget.striker;
  String? _fielder;
  int _runs = 0;

  void _save() {
    final k = _kind;
    if (k == null) return;
    final pickOut = k == OutKind.runOut || k == OutKind.retired;
    Navigator.pop(
      context,
      WicketResult(
        kind: k,
        outPlayer: pickOut ? _out : widget.striker,
        fielder: OutKind.needsFielder(k) ? _fielder : null,
        runs: k == OutKind.runOut ? _runs : 0,
      ),
    );
  }

  String _kindLabel(BuildContext c, String k) => c.tr('out_${k.replaceAll(' ', '_')}');

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final kind = _kind;
    final needsFielder = kind != null && OutKind.needsFielder(kind);
    final ready = kind != null && (!needsFielder || _fielder != null || kind == OutKind.runOut);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(context.tr('how_out')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              for (final k in OutKind.all)
                ChoiceChipX(label: _kindLabel(context, k), selected: _kind == k, onTap: () => setState(() => _kind = k)),
            ]),
          ),
          if (kind == OutKind.runOut || kind == OutKind.retired) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
              child: Text(context.tr('who_is_out'), style: Tx.label(p.text2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: Segmented<String>(
                values: [widget.striker, widget.nonStriker],
                labels: [widget.name(widget.striker), widget.name(widget.nonStriker)],
                selected: _out,
                onChanged: (v) => setState(() => _out = v),
              ),
            ),
          ],
          if (kind == OutKind.runOut) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
              child: Text(context.tr('runs_completed'), style: Tx.label(p.text2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: Segmented<int>(values: const [0, 1, 2, 3], labels: const ['0', '1', '2', '3'], selected: _runs, onChanged: (v) => setState(() => _runs = v)),
            ),
          ],
          if (needsFielder) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
              child: Text(kind == OutKind.runOut ? context.tr('fielder_optional') : context.tr('fielder'), style: Tx.label(p.text2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final f in widget.fielders)
                  ChoiceChipX(label: widget.name(f), selected: _fielder == f, onTap: () => setState(() => _fielder = f)),
              ]),
            ),
          ],
          const SizedBox(height: Space.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: GoldButton(
              label: context.tr('save_wicket'),
              icon: Icons.check_rounded,
              onPressed: ready ? _save : null,
            ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ shot direction

class ShotResult {
  ShotResult({this.zone, this.shot, this.angle, this.dist});
  final String? zone;
  final String? shot;
  final double? angle;
  final double? dist;

  Map<String, dynamic> toEvent() => {
        if (zone != null) 'zone': zone,
        if (shot != null) 'shot': shot,
        if (angle != null) 'ang': double.parse(angle!.toStringAsFixed(1)),
        if (dist != null) 'dist': double.parse(dist!.toStringAsFixed(2)),
      };
}

/// Returns a [ShotResult] (empty when skipped) or null when the scorer backs out.
Future<ShotResult?> pickShot(
  BuildContext context, {
  required int runs,
  required String kind,
  required String strikerName,
  required String bowlerName,
  required bool leftHanded,
}) {
  return showAppSheet<ShotResult>(context, (ctx) => _ShotSheet(runs: runs, kind: kind, strikerName: strikerName, bowlerName: bowlerName, leftHanded: leftHanded));
}

class _ShotSheet extends StatefulWidget {
  const _ShotSheet({required this.runs, required this.kind, required this.strikerName, required this.bowlerName, required this.leftHanded});
  final int runs;
  final String kind;
  final String strikerName;
  final String bowlerName;
  final bool leftHanded;

  @override
  State<_ShotSheet> createState() => _ShotSheetState();
}

class _ShotSheetState extends State<_ShotSheet> {
  double? _angle;
  double? _dist;
  String? _zone;
  String? _shot;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lang = context.settings.lang;
    final preview = previewCommentary(
      bowler: widget.bowlerName,
      striker: widget.strikerName,
      kind: widget.kind,
      runs: widget.runs,
      zone: _zone,
      shot: _shot,
      lang: lang,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(
            context.tr('where_did_it_go'),
            subtitle: '${widget.strikerName} · ${widget.leftHanded ? context.tr('left_hand_bat') : context.tr('right_hand_bat')}',
            trailing: TextButton(
              onPressed: () => Navigator.pop(context, ShotResult()),
              style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(56, 44)),
              child: Text(context.tr('skip'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Row(children: [
              Flexible(child: Text(widget.leftHanded ? context.tr('off_side') : context.tr('leg_side'), style: Tx.label(p.text2))),
              const Spacer(),
              Flexible(child: Text(widget.leftHanded ? context.tr('leg_side') : context.tr('off_side'), style: Tx.label(p.text2))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: TapGround(
              leftHanded: widget.leftHanded,
              selected: _zone,
              tap: _angle == null ? null : ShotPoint(_angle!, _dist ?? 0.8, widget.runs),
              onTap: (a, d) => setState(() {
                _angle = a;
                _dist = d;
                _zone = Zone.fromAngle(a);
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Text(context.tr('shot_optional'), style: Tx.label(p.text2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              for (final s in Shot.all)
                ChoiceChipX(label: Shot.name(s, lang), selected: _shot == s, onTap: () => setState(() => _shot = _shot == s ? null : s)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(Corners.chip)),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${context.tr('commentary_preview')} ', style: Tx.small(p.text2, w: FontWeight.w700)),
              TextSpan(text: preview.headline, style: Tx.small(p.text, w: FontWeight.w800)),
              if (preview.detail.isNotEmpty) TextSpan(text: ' ${preview.detail}', style: Tx.small(p.text)),
            ])),
          ),
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: GoldButton(
              label: context.tr('save_ball'),
              onPressed: () => Navigator.pop(context, ShotResult(zone: _zone, shot: _shot, angle: _angle, dist: _dist)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Names for a ball kind in the extras sheet.
String extraTitle(BuildContext context, String kind) => switch (kind) {
      BallKind.wide => context.tr('wide'),
      BallKind.noBall => context.tr('no_ball'),
      BallKind.bye => context.tr('bye'),
      _ => context.tr('leg_bye'),
    };
