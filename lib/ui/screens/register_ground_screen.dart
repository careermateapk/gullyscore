// Register (or edit) a ground in 3 steps: place, photos & facilities,
// fees & contact. Photos are made small on the phone before upload.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'grounds_screen.dart';
import 'online.dart';
import 'scoring_sheets.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// A JPEG under ~280 KB, as base64 (runs off the main thread).
Uint8List? _shrink(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  for (final (side, q) in [(1280, 72), (1024, 62), (800, 55)]) {
    final r = im.width >= im.height ? img.copyResize(im, width: im.width > side ? side : im.width) : img.copyResize(im, height: im.height > side ? side : im.height);
    final out = Uint8List.fromList(img.encodeJpg(r, quality: q));
    if (out.length < 280 * 1024) return out;
  }
  return null;
}

/// Camera or gallery → small JPEG as base64, or null.
Future<String?> pickGroundPhoto(BuildContext context) async {
  final camera = await showAppSheet<bool>(context, (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetTitle(ctx.tr('add_photo')),
      ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(ctx.tr('take_photo')), onTap: () => Navigator.pop(ctx, true)),
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(ctx.tr('choose_from_gallery')), onTap: () => Navigator.pop(ctx, false)),
      const SizedBox(height: Space.m),
    ]);
  });
  if (camera == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (x == null) return null;
    final small = await compute(_shrink, await File(x.path).readAsBytes());
    if (small == null) return null;
    return base64Encode(small);
  } catch (_) {
    if (context.mounted) _snack(context, context.tr('photo_failed'));
    return null;
  }
}

class RegisterGroundScreen extends StatefulWidget {
  const RegisterGroundScreen({super.key, this.near, this.edit, this.locate = true});
  final Place? near;
  final Ground? edit;
  final bool locate;

  @override
  State<RegisterGroundScreen> createState() => _RegisterGroundScreenState();
}

class _RegisterGroundScreenState extends State<RegisterGroundScreen> {
  int _step = 0;
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _city = TextEditingController(text: widget.edit?.city ?? widget.near?.name ?? '');
  late final _address = TextEditingController(text: widget.edit?.address ?? '');
  late final _bMin = TextEditingController(text: _n(widget.edit?.boundaryMin));
  late final _bMax = TextEditingController(text: _n(widget.edit?.boundaryMax));
  late final _feeMin = TextEditingController(text: _n(widget.edit?.feeMin));
  late final _feeMax = TextEditingController(text: _n(widget.edit?.feeMax));
  late final _feeNote = TextEditingController(text: widget.edit?.fee ?? '');
  late final _phone = TextEditingController(text: widget.edit?.phone ?? '');
  late final _phone2 = TextEditingController(text: widget.edit?.phone2 ?? '');
  late final _timings = TextEditingController(text: widget.edit?.timings ?? '');
  late final Set<String> _pitches = {...?widget.edit?.pitches};
  late final Set<String> _fac = {...?widget.edit?.facilities};
  final List<String> _photos = []; // base64 JPEGs waiting to upload
  late double? _lat = widget.edit?.lat;
  late double? _lng = widget.edit?.lng;
  String _where = '';
  bool _busy = false;
  String? _error;

  static String _n(int? v) => v == null || v == 0 ? '' : '$v';

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _bMin, _bMax, _feeMin, _feeMax, _feeNote, _phone, _phone2, _timings]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _here() async {
    if (!widget.locate) return;
    setState(() => _where = context.tr('finding_location'));
    final pos = await myPosition();
    if (!mounted) return;
    setState(() {
      if (pos == null) {
        _where = context.tr('location_failed');
      } else {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _where = context.tr('location_set_here');
      }
    });
  }

  bool _check() {
    String? e;
    if (_step == 0) {
      if (_name.text.trim().isEmpty) e = context.tr('ground_name_needed');
      if (e == null && (_lat == null || _lng == null)) e = context.tr('ground_location_needed');
    }
    if (_step == 1 && _pitches.isEmpty) e = context.tr('pitch_needed');
    setState(() => _error = e);
    return e == null;
  }

  Future<void> _submit() async {
    if (!_check()) return;
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_needed'));
      await loginAsPlayer(context);
      if (!sync.loggedIn || !mounted) return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final body = {
      'name': _name.text.trim(),
      'city': _city.text.trim(),
      'address': _address.text.trim(),
      'lat': _lat,
      'lng': _lng,
      'pitches': _pitches.toList(),
      'facilities': _fac.toList(),
      'boundaryMin': int.tryParse(_bMin.text.trim()) ?? 0,
      'boundaryMax': int.tryParse(_bMax.text.trim()) ?? 0,
      'feeMin': int.tryParse(_feeMin.text.trim()) ?? 0,
      'feeMax': int.tryParse(_feeMax.text.trim()) ?? 0,
      'fee': _feeNote.text.trim(),
      'phone': _phone.text.trim(),
      'phone2': _phone2.text.trim(),
      'timings': _timings.text.trim(),
    };
    try {
      final g = widget.edit == null ? await sync.social.addGround(body) : await sync.social.editGround(widget.edit!.id, body);
      for (final ph in _photos) {
        await sync.social.addGroundPhoto(g.id, ph);
      }
      if (mounted) _snack(context, context.tr(widget.edit == null ? 'ground_added' : 'saved'));
      nav.pop(g);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = onlineError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget field(TextEditingController c, String hint, {TextInputType? type, IconData? icon, bool digits = false}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: TextField(
            controller: c,
            keyboardType: type,
            inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
            textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
            decoration: InputDecoration(hintText: hint, prefixIcon: icon == null ? null : Icon(icon, size: 20)),
          ),
        );
    Widget label(String k) => Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.s),
          child: Text(context.tr(k).toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800)),
        );
    final steps = [
      // 1. Name and place
      [
        field(_name, context.tr('ground_name_hint')),
        field(_city, context.tr('ground_city_hint')),
        field(_address, context.tr('ground_address_hint')),
        label('ground_location'),
        AppCard(
          onTap: _here,
          child: Row(children: [
            Icon(_lat == null ? Icons.my_location_rounded : Icons.check_circle_rounded, color: _lat == null ? p.goldText : p.win),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(_lat == null ? 'use_my_location_here' : 'location_saved'), style: Tx.body(p.text, w: FontWeight.w800)),
                Text(_where.isNotEmpty ? _where : context.tr('stand_at_ground'), style: Tx.small(p.text2)),
              ]),
            ),
          ]),
        ),
        if (widget.near != null && _lat == null)
          TextButton(
            onPressed: () => setState(() {
              _lat = widget.near!.lat;
              _lng = widget.near!.lng;
              _where = widget.near!.name;
            }),
            child: Text(context.tr('use_place', {'name': widget.near!.name})),
          ),
      ],
      // 2. Photos, pitch, facilities, boundary
      [
        label('photos_up_to'),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 2 * Space.s) / 3;
          return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(_photos[i]), width: w, height: w, fit: BoxFit.cover)),
                Positioned(
                  right: 2,
                  top: 2,
                  child: InkWell(
                    onTap: () => setState(() => _photos.removeAt(i)),
                    child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
                  ),
                ),
              ]),
            if (_photos.length < 6)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final b = await pickGroundPhoto(context);
                  if (b != null && mounted) setState(() => _photos.add(b));
                },
                child: Container(
                  width: w,
                  height: w,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 2)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_a_photo_outlined, color: p.text2),
                    Text(context.tr('add_photo'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w700)),
                  ]),
                ),
              ),
          ]);
        }),
        label('pitch_type'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in groundPitches)
            ChoiceChipX(label: context.tr('pitch_$x'), selected: _pitches.contains(x), onTap: () => setState(() => _pitches.contains(x) ? _pitches.remove(x) : _pitches.add(x))),
        ]),
        label('facilities'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in groundFacilities)
            ChoiceChipX(label: '${facilityIcons[x]} ${context.tr('fac_$x')}', selected: _fac.contains(x), onTap: () => setState(() => _fac.contains(x) ? _fac.remove(x) : _fac.add(x))),
        ]),
        label('boundary_m'),
        Row(children: [
          Expanded(child: field(_bMin, context.tr('shortest'), type: TextInputType.number, digits: true)),
          const SizedBox(width: Space.s),
          Expanded(child: field(_bMax, context.tr('longest'), type: TextInputType.number, digits: true)),
        ]),
      ],
      // 3. Fees and contact
      [
        label('fee_per_match'),
        Row(children: [
          Expanded(child: field(_feeMin, context.tr('min_fee'), type: TextInputType.number, digits: true, icon: Icons.currency_rupee_rounded)),
          const SizedBox(width: Space.s),
          Expanded(child: field(_feeMax, context.tr('max_fee_short'), type: TextInputType.number, digits: true, icon: Icons.currency_rupee_rounded)),
        ]),
        field(_feeNote, context.tr('fee_note_hint')),
        label('contact'),
        field(_phone, context.tr('ground_phone_hint'), type: TextInputType.phone, icon: Icons.call_outlined),
        field(_phone2, context.tr('second_phone_hint'), type: TextInputType.phone, icon: Icons.call_outlined),
        field(_timings, context.tr('timings_hint'), icon: Icons.schedule_rounded),
      ],
    ];
    final titles = ['reg_step_place', 'reg_step_photos', 'reg_step_fees'];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.close_rounded, tooltip: context.tr('close'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(context.tr(widget.edit == null ? 'register_ground' : 'edit_ground'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(color: i <= _step ? p.gold : p.line, borderRadius: BorderRadius.circular(9)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 6, Space.edge, 0),
            child: Text(context.tr('step_of', {'n': _step + 1, 'title': context.tr(titles[_step])}), style: Tx.label(p.text2, w: FontWeight.w700)),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.l), children: [
              ...steps[_step],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(_error!, style: Tx.small(p.liveText, w: FontWeight.w700))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
            decoration: BoxDecoration(color: p.nav, border: Border(top: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(
                child: OutlineBtn(
                  label: context.tr(_step == 0 ? 'cancel' : 'back'),
                  height: 48,
                  onPressed: _busy ? null : () => _step == 0 ? Navigator.maybePop(context) : setState(() => _step--),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                flex: 2,
                child: GoldButton(
                  label: context.tr(_step < 2 ? 'next' : (widget.edit == null ? 'register_ground' : 'save')),
                  height: 48,
                  onPressed: _busy
                      ? null
                      : () {
                          if (_step < 2) {
                            if (_check()) setState(() => _step++);
                          } else {
                            _submit();
                          }
                        },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
