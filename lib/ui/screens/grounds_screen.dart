// Grounds near you: pick a place (your location or search a city/area),
// filter and sort, and open a ground. No Google billing: maps and
// directions open in the Google Maps app.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'ground_detail_screen.dart';
import 'register_ground_screen.dart';
import 'scoring_sheets.dart';

const groundPitches = ['turf', 'matting', 'cement', 'mud', 'astroturf'];
const groundFacilities = ['lights', 'washrooms', 'water', 'nets', 'umpires', 'scorers', 'parking', 'pavilion', 'cafeteria', 'sightscreen', 'balls'];
const facilityIcons = {
  'lights': '💡',
  'washrooms': '🚻',
  'water': '💧',
  'nets': '🏏',
  'umpires': '🧑‍⚖️',
  'scorers': '📝',
  'parking': '🅿️',
  'pavilion': '🏠',
  'cafeteria': '☕',
  'sightscreen': '⬜',
  'balls': '⚾',
};

String rupees(int n) {
  final s = n.toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

String feeText(BuildContext context, Ground g) {
  if (g.feeMin == 0 && g.feeMax == 0) return g.fee.isNotEmpty ? g.fee : context.tr('fee_ask');
  final f = g.feeMax > g.feeMin ? '${rupees(g.feeMin)} – ${rupees(g.feeMax)}' : rupees(g.feeMin);
  return g.fee.isNotEmpty ? '$f · ${g.fee}' : f;
}

/// The phone's location, or null when it is off or not allowed.
Future<Position?> myPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
  } catch (_) {
    return null;
  }
}

/// A ground's first photo, or a drawn field when there is none.
class GroundPhoto extends StatelessWidget {
  const GroundPhoto({super.key, required this.groundId, this.photoId, this.height = 150});
  final String groundId;
  final String? photoId;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = context.sync.cloud.baseUrl;
    final placeholder = Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3F7D33), Color(0xFF16351A)]),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.sports_cricket_rounded, size: height * 0.35, color: Colors.white.withValues(alpha: 0.35)),
    );
    if (photoId == null || base.isEmpty) return placeholder;
    return Image.network(
      context.sync.social.photoUrl(base, groundId, photoId!),
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => placeholder,
      loadingBuilder: (c, child, p) => p == null ? child : placeholder,
    );
  }
}

class GroundCard extends StatelessWidget {
  const GroundCard({super.key, required this.g, required this.onTap});
  final Ground g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Corners.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corners.card), border: Border.all(color: p.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              GroundPhoto(groundId: g.id, photoId: g.photo),
              if (g.km != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xC0070F1E), borderRadius: BorderRadius.circular(9)),
                    child: Text('🚗 ${g.km} km', style: Tx.label(Colors.white, w: FontWeight.w800)),
                  ),
                ),
              if (g.photo == null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xB0070F1E), borderRadius: BorderRadius.circular(8)),
                    child: Text(context.tr('no_photo_yet'), style: Tx.label(Colors.white, w: FontWeight.w700)),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (g.rating != null) Tag('★ ${g.rating!.toStringAsFixed(1)}', color: p.win),
                  Text(g.reviews == 0 ? context.tr('no_reviews_yet') : context.tr('reviews_n', {'n': g.reviews}), style: Tx.label(p.text2, w: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Text(
                  ['📍 ${g.area}', if (g.pitches.isNotEmpty) context.tr('pitch_${g.pitches.first}'), context.tr('matches_n', {'n': g.matches})].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Tx.label(p.text2, w: FontWeight.w600),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.05), border: Border(top: BorderSide(color: p.line))),
              child: Row(children: [
                Expanded(child: Text(feeText(context, g), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.score(19, p.goldText, w: FontWeight.w800))),
                Text('${context.tr('view')} ›', style: Tx.small(p.goldText, w: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Filters {
  String sort = 'distance';
  final Set<String> pitches = {};
  final Set<String> facilities = {};
  int? feeMax;
  int get count => pitches.length + facilities.length + (feeMax != null ? 1 : 0);
}

class GroundsScreen extends StatefulWidget {
  const GroundsScreen({super.key, this.locate = true});
  final bool locate; // tests switch the phone's location off

  @override
  State<GroundsScreen> createState() => _GroundsScreenState();
}

class _GroundsScreenState extends State<GroundsScreen> {
  Place? _place; // null = my location
  Position? _pos;
  int _km = 15;
  final _f = _Filters();
  String _quick = 'all';
  List<Ground>? _list;
  int _total = 0;
  Object? _error;

  double? get _lat => _place?.lat ?? _pos?.latitude;
  double? get _lng => _place?.lng ?? _pos?.longitude;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (widget.locate) _pos = await myPosition();
    if (_pos == null) {
      try {
        final p = await SharedPreferences.getInstance();
        final recent = p.getStringList('grounds.recent') ?? const [];
        if (recent.isNotEmpty) _place = Place.fromJson(jsonDecode(recent.first) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (mounted) await _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final pitch = {..._f.pitches, if (_quick == 'turf') 'turf'}.toList();
    final fac = {..._f.facilities, if (_quick == 'lights') 'lights'}.toList();
    final feeMax = _quick == 'cheap' ? 2000 : _f.feeMax;
    try {
      final r = await context.sync.social.grounds(lat: _lat, lng: _lng, km: _km, pitch: pitch, fac: fac, feeMax: feeMax, sort: _f.sort);
      if (mounted) {
        setState(() {
          _list = r.grounds;
          _total = r.total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _chooseLocation() async {
    final r = await showAppSheet<(Place?, int)>(context, (ctx) => _LocationSheet(km: _km, locate: widget.locate));
    if (r == null || !mounted) return;
    if (r.$1 == null && widget.locate) _pos = await myPosition();
    setState(() {
      _place = r.$1;
      _km = r.$2;
      _list = null;
    });
    await _load();
  }

  Future<void> _filters() async {
    final ok = await showAppSheet<bool>(context, (ctx) => _FilterSheet(f: _f));
    if (ok == true && mounted) {
      setState(() => _list = null);
      await _load();
    }
  }

  void _open(Ground g) => Navigator.push(context, MaterialPageRoute(builder: (_) => GroundDetailScreen(groundId: g.id, lat: _lat, lng: _lng)));

  Future<void> _register() async {
    final g = await Navigator.push<Ground>(context, MaterialPageRoute(builder: (_) => RegisterGroundScreen(near: _place, locate: widget.locate)));
    if (g != null && mounted) {
      await _load();
      if (mounted) _open(g);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final online = context.sync.enabled;
    final where = _place != null ? _place!.name : (_pos != null ? context.tr('current_location') : context.tr('choose_location'));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(_list == null ? context.tr('grounds') : context.tr('grounds_n', {'n': _total}),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20)),
              ),
              if (online)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: GoldButton(label: context.tr('register'), icon: Icons.add_rounded, height: 42, onPressed: _register),
                  ),
                ),
            ]),
          ),
          if (!online)
            Expanded(child: EmptyState(icon: Icons.cloud_off_rounded, title: context.tr('grounds_near_you'), body: context.tr('online_not_set_up')))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: Material(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _chooseLocation,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
                    child: Row(children: [
                      const Text('📍', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${context.tr('near')} ', style: Tx.small(p.text, w: FontWeight.w800)),
                            TextSpan(text: '$where · ${_km} km ', style: Tx.small(p.goldText, w: FontWeight.w800)),
                            TextSpan(text: '(${context.tr('change')})', style: Tx.small(p.text2, w: FontWeight.w700)),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Badge(
                        isLabelVisible: _f.count > 0,
                        label: Text('${_f.count}'),
                        backgroundColor: p.gold,
                        textColor: const Color(0xFF0B1220),
                        child: IconBtn(icon: Icons.tune_rounded, tooltip: context.tr('filters'), onPressed: _filters),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0), children: [
                for (final q in ['all', 'turf', 'lights', 'cheap']) ...[
                  ChoiceChipX(
                    label: context.tr('gq_$q'),
                    selected: _quick == q,
                    onTap: () {
                      setState(() => _quick = q);
                      _load();
                    },
                  ),
                  const SizedBox(width: Space.s),
                ],
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                color: p.goldText,
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(0, Space.m, 0, Space.xl), children: [
                  if (_lat == null && _list != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                      child: AppCard(
                        onTap: _chooseLocation,
                        child: Row(children: [
                          Icon(Icons.location_off_outlined, color: p.goldText),
                          const SizedBox(width: Space.m),
                          Expanded(child: Text(context.tr('location_off_note'), style: Tx.small(p.text2, w: FontWeight.w600))),
                        ]),
                      ),
                    ),
                  if (_list == null && _error == null)
                    const LoadingList(count: 2)
                  else if (_list == null)
                    OnlineError(error: _error!, onRetry: _load)
                  else if (_list!.isEmpty)
                    EmptyState(icon: Icons.stadium_outlined, title: context.tr('no_grounds_near'), body: context.tr('no_grounds_body'), actionLabel: context.tr('register'), onAction: _register)
                  else
                    for (final g in _list!)
                      Padding(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.m), child: GroundCard(g: g, onTap: () => _open(g))),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Search a city or area, or use the phone's location; and how far to look.
class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.km, required this.locate});
  final int km;
  final bool locate;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  late int _km = widget.km;
  List<Place> _found = const [];
  List<Place> _recent = const [];
  Timer? _t;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final r = [
        for (final s in p.getStringList('grounds.recent') ?? const <String>[])
          if (jsonDecode(s) is Map) Place.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)),
      ];
      if (mounted) setState(() => _recent = r);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _t?.cancel();
    if (q.trim().length < 2) {
      setState(() => _found = const []);
      return;
    }
    _t = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searching = true);
      try {
        final r = await context.sync.social.places(q.trim());
        if (mounted) setState(() => _found = r);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pick(Place? pl) async {
    if (pl != null) {
      try {
        final p = await SharedPreferences.getInstance();
        final list = [jsonEncode(pl.toJson()), ...(p.getStringList('grounds.recent') ?? const []).where((s) => !s.contains('"name":"${pl.name}"'))].take(5).toList();
        await p.setStringList('grounds.recent', list);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, (pl, _km));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget row(String icon, String title, String sub, VoidCallback onTap, {bool gold = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(gold ? p.goldText : p.text, w: FontWeight.w800)),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('choose_location')),
        TextField(
          autofocus: true,
          onChanged: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: p.text2),
            hintText: context.tr('search_city_area'),
            suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
        const SizedBox(height: Space.s),
        if (widget.locate) row('🎯', context.tr('use_my_location'), '', () => _pick(null), gold: true),
        for (final pl in _found) row('📍', pl.name, pl.detail, () => _pick(pl)),
        if (_found.isEmpty && _recent.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(context.tr('recent').toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800))),
          for (final pl in _recent) row('🕘', pl.name, pl.detail, () => _pick(pl)),
        ],
        const SizedBox(height: Space.m),
        Text(context.tr('distance').toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800)),
        const SizedBox(height: Space.s),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in [5, 15, 30, 50]) ChoiceChipX(label: '$k km', selected: _km == k, onTap: () => setState(() => _km = k)),
        ]),
        const SizedBox(height: Space.s),
        Text(context.tr('places_osm_note'), style: Tx.label(p.text2, w: FontWeight.w500)),
      ]),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.f});
  final _Filters f;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _fee = TextEditingController(text: widget.f.feeMax?.toString() ?? '');

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final f = widget.f;
    Widget label(String k) => Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.s),
          child: Text(context.tr(k).toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800)),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('filters'),
            trailing: TextButton(
              onPressed: () => setState(() {
                f.pitches.clear();
                f.facilities.clear();
                f.feeMax = null;
                f.sort = 'distance';
                _fee.clear();
              }),
              child: Text(context.tr('clear_all')),
            )),
        label('sort_by'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in ['distance', 'rating', 'matches', 'fee', 'name']) ChoiceChipX(label: context.tr('gsort_$s'), selected: f.sort == s, onTap: () => setState(() => f.sort = s)),
        ]),
        label('pitch_type'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in groundPitches)
            ChoiceChipX(label: context.tr('pitch_$x'), selected: f.pitches.contains(x), onTap: () => setState(() => f.pitches.contains(x) ? f.pitches.remove(x) : f.pitches.add(x))),
        ]),
        label('facilities'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in groundFacilities)
            ChoiceChipX(
              label: '${facilityIcons[x]} ${context.tr('fac_$x')}',
              selected: f.facilities.contains(x),
              onTap: () => setState(() => f.facilities.contains(x) ? f.facilities.remove(x) : f.facilities.add(x)),
            ),
        ]),
        label('max_fee'),
        TextField(
          controller: _fee,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: context.tr('max_fee_hint'), prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20)),
          onChanged: (v) => f.feeMax = int.tryParse(v.trim()),
        ),
        const SizedBox(height: Space.l),
        GoldButton(label: context.tr('show_grounds'), onPressed: () => Navigator.pop(context, true)),
      ]),
    );
  }
}
