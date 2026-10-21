// Pick a registered ground for a match (nearest first, or search by name).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'grounds_screen.dart';
import 'scoring_sheets.dart';

Future<Ground?> pickGround(BuildContext context, {bool locate = true}) => showAppSheet<Ground>(context, (ctx) => _GroundPicker(locate: locate));

class _GroundPicker extends StatefulWidget {
  const _GroundPicker({required this.locate});
  final bool locate;

  @override
  State<_GroundPicker> createState() => _GroundPickerState();
}

class _GroundPickerState extends State<_GroundPicker> {
  List<Ground>? _list;
  double? _lat, _lng;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.locate) {
      final pos = await myPosition();
      _lat = pos?.latitude;
      _lng = pos?.longitude;
    }
    await _load('');
  }

  Future<void> _load(String q) async {
    try {
      final r = await context.sync.social.grounds(lat: _lat, lng: _lng, km: 30, q: q);
      if (mounted) setState(() => _list = r.grounds);
    } catch (_) {
      if (mounted) setState(() => _list = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('pick_ground')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: TextField(
            onChanged: (v) {
              _t?.cancel();
              _t = Timer(const Duration(milliseconds: 400), () => _load(v.trim().length >= 2 ? v.trim() : ''));
            },
            decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded, color: p.text2), hintText: context.tr('search_grounds')),
          ),
        ),
        Flexible(
          child: _list == null
              ? const Padding(padding: EdgeInsets.all(Space.l), child: LoadingList(count: 2))
              : _list!.isEmpty
                  ? Padding(padding: const EdgeInsets.all(Space.l), child: Text(context.tr('no_grounds_near'), style: Tx.small(p.text2)))
                  : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(0, Space.s, 0, Space.l), children: [
                      for (final g in _list!)
                        ListTile(
                          leading: const Text('🏟️', style: TextStyle(fontSize: 24)),
                          title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w700)),
                          subtitle: Text([if (g.km != null) '${g.km} km', g.area].where((x) => x.isNotEmpty).join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2)),
                          onTap: () => Navigator.pop(context, g),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
