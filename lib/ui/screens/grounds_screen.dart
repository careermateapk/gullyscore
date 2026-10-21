// Grounds near you: a Google map (when the app was built with a Maps key),
// search (GullyScore's list + Google), call to book, directions, add a ground.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'info_screens.dart';
import 'online.dart';
import 'scoring_sheets.dart';

/// Set at build time when a Google Maps key is in the app.
const mapsOn = bool.fromEnvironment('MAPS_ON');

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<Position?> _myPosition() async {
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

class GroundsScreen extends StatefulWidget {
  const GroundsScreen({super.key, this.locate = true});
  final bool locate; // tests switch the phone's location off

  @override
  State<GroundsScreen> createState() => _GroundsScreenState();
}

class _GroundsScreenState extends State<GroundsScreen> {
  Position? _pos;
  List<Ground>? _near;
  ({List<Ground> ours, List<Ground> google})? _found;
  Object? _error;
  String _filter = 'all';
  final _q = TextEditingController();
  Timer? _debounce;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.locate) _pos = await _myPosition();
    if (!mounted) return;
    await _loadNear();
  }

  Future<void> _loadNear() async {
    setState(() => _error = null);
    try {
      final r = await context.sync.social.grounds(lat: _pos?.latitude, lng: _pos?.longitude);
      if (mounted) setState(() => _near = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _search(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _found = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final r = await context.sync.social.searchGrounds(text.trim(), lat: _pos?.latitude, lng: _pos?.longitude);
        if (mounted) setState(() => _found = r);
      } catch (e) {
        if (mounted) _snack(context, onlineError(context, e));
      }
    });
  }

  bool _keep(Ground g) => switch (_filter) {
        'free' => g.fee.toLowerCase().contains('free') || g.fee.contains('मुफ़्त'),
        'turf' => g.pitch == 'turf',
        'lights' => g.lights,
        _ => true,
      };

  Future<void> _add({Ground? from}) async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_needed'));
      await loginAsPlayer(context);
      if (!sync.loggedIn || !mounted) return;
    }
    if (from == null && _pos == null && widget.locate) {
      _pos = await _myPosition();
      if (!mounted) return;
    }
    final lat = from?.lat ?? _pos?.latitude;
    final lng = from?.lng ?? _pos?.longitude;
    if (lat == null || lng == null) {
      _snack(context, context.tr('need_location'));
      return;
    }
    final g = await showAppSheet<Ground>(context, (ctx) => _AddGround(lat: lat, lng: lng, from: from));
    if (g != null && mounted) {
      _snack(context, context.tr('ground_added'));
      setState(() => _found = null);
      _q.clear();
      await _loadNear();
    }
  }

  void _focus(Ground g) {
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(g.lat, g.lng), 15));
  }

  Widget _mapView(List<Ground> list) {
    final p = Palette.of(context);
    final center = _pos != null ? LatLng(_pos!.latitude, _pos!.longitude) : (list.isNotEmpty ? LatLng(list.first.lat, list.first.lng) : const LatLng(23.5, 80.0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Corners.hero),
        child: SizedBox(
          height: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(color: p.surface),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: _pos != null || list.isNotEmpty ? 11 : 4.5),
              myLocationEnabled: _pos != null,
              myLocationButtonEnabled: _pos != null,
              mapToolbarEnabled: false,
              onMapCreated: (c) => _map = c,
              markers: {
                for (final g in list)
                  Marker(
                    markerId: MarkerId(g.id ?? g.placeId ?? '${g.lat},${g.lng}'),
                    position: LatLng(g.lat, g.lng),
                    infoWindow: InfoWindow(title: g.name, snippet: [g.fee, g.pitch].where((x) => x.isNotEmpty).join(' · ')),
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final online = context.sync.enabled;
    final shown = (_found?.ours ?? _near ?? const <Ground>[]).where(_keep).toList();
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: online
          ? FloatingActionButton.extended(
              backgroundColor: p.gold,
              foregroundColor: const Color(0xFF0B1220),
              onPressed: () => _add(),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(context.tr('add_ground'), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('grounds_near_you'), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20))),
            ]),
          ),
          if (!online)
            Expanded(child: EmptyState(icon: Icons.cloud_off_rounded, title: context.tr('grounds_near_you'), body: context.tr('online_not_set_up')))
          else
            Expanded(
              child: RefreshIndicator(
                color: p.goldText,
                onRefresh: _loadNear,
                child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                  if (mapsOn) _mapView(shown),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                    child: TextField(
                      controller: _q,
                      onChanged: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded, color: p.text2), hintText: context.tr('search_grounds')),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0), children: [
                      for (final f in ['all', 'free', 'turf', 'lights']) ...[
                        ChoiceChipX(label: context.tr('gf_$f'), selected: _filter == f, onTap: () => setState(() => _filter = f)),
                        const SizedBox(width: Space.s),
                      ],
                    ]),
                  ),
                  if (_pos == null && widget.locate && _near != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
                      child: Text(context.tr('location_off_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
                    ),
                  if (_near == null && _error == null)
                    const Padding(padding: EdgeInsets.only(top: Space.m), child: LoadingList(count: 2))
                  else if (_near == null)
                    Padding(padding: const EdgeInsets.only(top: Space.m), child: OnlineError(error: _error!, onRetry: _loadNear))
                  else ...[
                    if (_found != null) SectionHeader(context.tr('on_gullyscore')),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(Space.edge),
                        child: AppCard(child: Text(context.tr(_found == null ? 'no_grounds_near' : 'no_grounds_found'), style: Tx.small(p.text2))),
                      ),
                    for (final g in shown)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
                        child: _GroundCard(g: g, onTap: mapsOn ? () => _focus(g) : null),
                      ),
                    if (_found != null && _found!.google.isNotEmpty) ...[
                      SectionHeader(context.tr('from_google_maps')),
                      for (final g in _found!.google)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                          child: AppCard(
                            child: Row(children: [
                              Icon(Icons.place_rounded, color: p.liveText),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
                                  Text([if (g.km != null) '${g.km} km', g.address].where((x) => x.isNotEmpty).join(' · '),
                                      maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w600)),
                                ]),
                              ),
                              TextButton(onPressed: () => _add(from: g), child: Text(context.tr('add'), style: Tx.small(p.goldText, w: FontWeight.w800))),
                            ]),
                          ),
                        ),
                    ],
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _GroundCard extends StatelessWidget {
  const _GroundCard({required this.g, this.onTap});
  final Ground g;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tags = [
      if (g.pitch.isNotEmpty) context.tr('pitch_${g.pitch}'),
      if (g.fee.isNotEmpty) g.fee,
      if (g.lights) context.tr('lights'),
      if (g.toilet) context.tr('toilet'),
    ];
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
            child: const Text('🏟️', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
              Text([if (g.km != null) '📍 ${g.km} km', g.address].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w600)),
            ]),
          ),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) Tag(t)]),
        ],
        const SizedBox(height: Space.s),
        Row(children: [
          if (g.phone.isNotEmpty) ...[
            Expanded(child: GoldButton(label: context.tr('call_to_book'), icon: Icons.call_rounded, height: 42, onPressed: () => openLink(context, 'tel:${g.phone.replaceAll(' ', '')}'))),
            const SizedBox(width: Space.s),
          ],
          Expanded(
            child: OutlineBtn(
              label: context.tr('directions'),
              icon: Icons.directions_rounded,
              height: 42,
              onPressed: () => openLink(context, 'https://www.google.com/maps/dir/?api=1&destination=${g.lat},${g.lng}'),
            ),
          ),
        ]),
      ]),
    );
  }
}

const _pitches = ['turf', 'matting', 'cement', 'mud'];

class _AddGround extends StatefulWidget {
  const _AddGround({required this.lat, required this.lng, this.from});
  final double lat, lng;
  final Ground? from;

  @override
  State<_AddGround> createState() => _AddGroundState();
}

class _AddGroundState extends State<_AddGround> {
  late final _name = TextEditingController(text: widget.from?.name ?? '');
  late final _address = TextEditingController(text: widget.from?.address ?? '');
  final _fee = TextEditingController();
  final _phone = TextEditingController();
  String _pitch = '';
  bool _lights = false, _toilet = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _fee, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final g = await context.sync.social.addGround({
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'lat': widget.lat,
        'lng': widget.lng,
        if (widget.from?.placeId != null) 'placeId': widget.from!.placeId,
        'pitch': _pitch,
        'fee': _fee.text.trim(),
        'phone': _phone.text.trim(),
        'lights': _lights,
        'toilet': _toilet,
      });
      nav.pop(g);
    } catch (e) {
      if (mounted) {
        _snack(context, onlineError(context, e));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('add_ground'), subtitle: widget.from == null ? context.tr('ground_here_note') : null),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('ground_name_hint'))),
        const SizedBox(height: Space.s),
        TextField(controller: _address, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('ground_address_hint'))),
        const SizedBox(height: Space.m),
        Text(context.tr('pitch'), style: Tx.small(p.text2, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in _pitches) ChoiceChipX(label: context.tr('pitch_$x'), selected: _pitch == x, onTap: () => setState(() => _pitch = _pitch == x ? '' : x)),
        ]),
        const SizedBox(height: Space.s),
        TextField(controller: _fee, decoration: InputDecoration(hintText: context.tr('ground_fee_hint'), prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20))),
        const SizedBox(height: Space.s),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: context.tr('ground_phone_hint'), prefixIcon: const Icon(Icons.call_outlined, size: 20))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _lights, onChanged: (v) => setState(() => _lights = v), title: Text(context.tr('lights'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _toilet, onChanged: (v) => setState(() => _toilet = v), title: Text(context.tr('toilet'))),
        const SizedBox(height: Space.s),
        GoldButton(label: context.tr('save'), onPressed: _busy ? null : _save),
      ]),
    );
  }
}
