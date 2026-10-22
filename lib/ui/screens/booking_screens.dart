// Ground booking: free slots by day with the weather, a booking request,
// the owner's slot list and everyone's requests.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'info_screens.dart';
import 'online.dart';
import 'scoring_sheets.dart';

String slotTime(int start, int end) {
  String t(int m) {
    final h = (m ~/ 60) % 24;
    final mm = m % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return mm == 0 ? '$h12' : '$h12:${mm.toString().padLeft(2, '0')}';
  }

  String ap(int m) => (m ~/ 60) % 24 < 12 ? 'AM' : 'PM';
  return ap(start) == ap(end) ? '${t(start)}–${t(end)} ${ap(end)}' : '${t(start)} ${ap(start)}–${t(end)} ${ap(end)}';
}

String _rupees(int n) {
  final s = '$n';
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

const _dayShort = ['day_mon', 'day_tue', 'day_wed', 'day_thu', 'day_fri', 'day_sat', 'day_sun'];

DateTime _parse(String d) => DateTime.tryParse(d) ?? DateTime.now();

String bookingDate(BuildContext context, String d) {
  final x = _parse(d);
  return '${context.tr(_dayShort[x.weekday - 1])} ${x.day}/${x.month}';
}

/// The Book tab on a ground's page.
class GroundBookingTab extends StatefulWidget {
  const GroundBookingTab({super.key, required this.ground});
  final Ground ground;

  @override
  State<GroundBookingTab> createState() => _GroundBookingTabState();
}

class _GroundBookingTabState extends State<GroundBookingTab> {
  GroundSlots? _data;
  Object? _error;
  String? _date;
  String? _pick;
  List<DayWeather> _weather = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadWeather();
  }

  Future<void> _load() async {
    try {
      final d = await context.sync.social.groundSlots(widget.ground.id, date: _date);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _date ??= d.date;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadWeather() async {
    try {
      final w = await context.sync.social.weather(widget.ground.lat, widget.ground.lng);
      if (mounted) setState(() => _weather = w);
    } catch (_) {}
  }

  Future<void> _request(Slot s) async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('login_needed'))));
      await loginAsPlayer(context);
      if (!sync.loggedIn || !mounted) return;
    }
    final date = _date!;
    final ok = await showAppSheet<bool>(context, (ctx) => _RequestSheet(ground: widget.ground, slot: s, date: date));
    if (ok == true && mounted) {
      setState(() => _pick = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('booking_sent'))));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = _data;
    if (d == null) return _error == null ? const LoadingList(count: 2) : OnlineError(error: _error!, onRetry: _load);
    final owner = d.mine;
    final weather = _weather.where((w) => w.date == _date).firstOrNull;
    final picked = d.slots.where((s) => s.id == _pick).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (owner)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Row(children: [
            Expanded(
              child: OutlineBtn(
                label: context.tr('manage_slots'),
                icon: Icons.schedule_rounded,
                height: 44,
                onPressed: () async {
                  final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SlotsEditorScreen(ground: widget.ground, slots: d.slots)));
                  if (saved == true) _load();
                },
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: OutlineBtn(
                label: context.tr('booking_requests'),
                icon: Icons.inbox_rounded,
                height: 44,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingsScreen(owner: true))),
              ),
            ),
          ]),
        ),
      if (d.slots.isEmpty)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr(owner ? 'no_slots_owner' : 'no_slots'), style: Tx.body(p.text, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(context.tr(owner ? 'no_slots_owner_body' : 'no_slots_body'), style: Tx.small(p.text2)),
          ]),
        )
      else ...[
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: d.days.length,
            separatorBuilder: (c, i) => const SizedBox(width: Space.s),
            itemBuilder: (c, i) {
              final (date, free) = d.days[i];
              final x = _parse(date);
              final on = date == _date;
              return Semantics(
                button: true,
                selected: on,
                label: '${bookingDate(context, date)} · ${context.tr('free_slots_n', {'n': free})}',
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _date = date;
                      _pick = null;
                    });
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: Motion.fade,
                    width: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: on ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7A3), Color(0xFFF4C247)]) : null,
                      color: on ? null : p.surface,
                      border: Border.all(color: on ? Colors.transparent : p.line),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        FittedBox(fit: BoxFit.scaleDown, child: Text(context.tr(_dayShort[x.weekday - 1]), style: Tx.label(on ? const Color(0xFF0B1220) : p.text2, w: FontWeight.w800))),
                        Text('${x.day}', style: Tx.score(22, on ? const Color(0xFF0B1220) : p.text, w: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: free > 0 ? p.win : Colors.transparent)),
                      ]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.m),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - Space.s) / 2;
          return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (final s in d.slots) SizedBox(width: w, child: _SlotCard(slot: s, picked: s.id == _pick, onTap: s.status == 'free' ? () => setState(() => _pick = s.id) : null)),
          ]);
        }),
        if (weather != null) ...[
          const SizedBox(height: Space.m),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Text(weather.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  context.tr('weather_line', {'d': bookingDate(context, weather.date), 'max': weather.max ?? '-', 'min': weather.min ?? '-', 'rain': weather.rain ?? 0}),
                  style: Tx.small(p.text, w: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: Space.m),
        if (!owner)
          GoldButton(
            label: picked == null ? context.tr('pick_a_slot') : context.tr('send_booking_request_for', {'p': _rupees(picked.price)}),
            icon: Icons.event_available_rounded,
            onPressed: picked == null ? null : () => _request(picked),
          ),
        const SizedBox(height: Space.s),
        Text(context.tr('booking_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
      ],
    ]);
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.picked, this.onTap});
  final Slot slot;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = slot;
    final (sub, color) = switch (s.status) {
      'booked' => (context.tr('slot_booked'), p.text2),
      'mine' => (context.tr('slot_mine'), p.win),
      'requested' => (context.tr('slot_requested'), p.goldText),
      'closed' => (context.tr('slot_closed'), p.text2),
      _ => (picked ? '${_rupees(s.price)} · ${context.tr('selected')} ✓' : _rupees(s.price), picked ? p.goldText : p.win),
    };
    final dim = s.status == 'booked' || s.status == 'closed';
    return Semantics(
      button: onTap != null,
      selected: picked,
      label: '${s.label} ${slotTime(s.start, s.end)} · $sub',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fade,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: picked ? p.gold.withValues(alpha: 0.12) : p.surface,
            border: Border.all(color: picked ? p.gold : p.line, width: picked ? 1.5 : 1),
          ),
          child: ExcludeSemantics(
            child: Opacity(
              opacity: dim ? 0.55 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.label.isNotEmpty) Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w800)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(slotTime(s.start, s.end), style: Tx.score(19, p.text, w: FontWeight.w800))),
                const SizedBox(height: 4),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(color, w: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.ground, required this.slot, required this.date});
  final Ground ground;
  final Slot slot;
  final String date;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _team = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final repo = context.repo;
    final mine = repo.teamList.firstOrNull;
    if (mine != null) _team.text = mine.name;
  }

  @override
  void dispose() {
    _team.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_team.text.trim().isEmpty || _phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = context.tr('booking_need_team_phone'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.sync.social.requestBooking(widget.ground.id, slotId: widget.slot.id!, date: widget.date, team: _team.text.trim(), phone: _phone.text.trim(), note: _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = onlineError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = widget.slot;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('book_ground'), subtitle: '${widget.ground.name} · ${bookingDate(context, widget.date)} · ${slotTime(s.start, s.end)} · ${_rupees(s.price)}'),
        const SizedBox(height: Space.s),
        TextField(controller: _team, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.tr('team_name'))),
        const SizedBox(height: Space.s),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('your_mobile'))),
        const SizedBox(height: Space.s),
        TextField(controller: _note, decoration: InputDecoration(labelText: context.tr('note_optional'))),
        const SizedBox(height: Space.s),
        Text(context.tr('booking_phone_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(_error!, style: Tx.small(p.liveText))),
        const SizedBox(height: Space.m),
        GoldButton(label: _busy ? context.tr('sending') : context.tr('send_booking_request'), icon: Icons.send_rounded, onPressed: _busy ? null : _send),
      ]),
    );
  }
}

// ---------------------------------------------------------------- owner: slots

class SlotsEditorScreen extends StatefulWidget {
  const SlotsEditorScreen({super.key, required this.ground, required this.slots});
  final Ground ground;
  final List<Slot> slots;

  @override
  State<SlotsEditorScreen> createState() => _SlotsEditorScreenState();
}

class _SlotsEditorScreenState extends State<SlotsEditorScreen> {
  late final List<Slot> _slots = [for (final s in widget.slots) Slot(id: s.id, label: s.label, start: s.start, end: s.end, price: s.price, days: s.days)];
  bool _busy = false;

  static const _presets = [('slot_morning', 360, 600), ('slot_day', 600, 840), ('slot_afternoon', 840, 1080), ('slot_night', 1140, 1380)];

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('saved');
    try {
      await context.sync.social.saveGroundSlots(widget.ground.id, _slots);
      messenger.showSnackBar(SnackBar(content: Text(saved)));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(onlineError(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _price(Slot s) async {
    final ctrl = TextEditingController(text: s.price == 0 ? '' : '${s.price}');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('slot_price')),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) setState(() => s.price = int.tryParse(v.replaceAll(RegExp(r'\D'), '')) ?? 0);
  }

  Future<void> _time(Slot s, bool start) async {
    final cur = start ? s.start : s.end;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60));
    if (t == null) return;
    setState(() {
      final m = t.hour * 60 + t.minute;
      if (start) {
        s.start = m;
        if (s.end <= m) s.end = (m + 120).clamp(0, 1440);
      } else {
        s.end = m <= s.start ? (s.start + 60).clamp(0, 1440) : m;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.bg, title: Text(context.tr('manage_slots'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: [
        Text(context.tr('slots_help'), style: Tx.small(p.text2)),
        const SizedBox(height: Space.m),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (k, a, b) in _presets)
            ChoiceChipX(
              label: '+ ${context.tr(k)}',
              selected: false,
              onTap: () => setState(() => _slots.add(Slot(label: context.tr(k), start: a, end: b, price: 1500))),
            ),
        ]),
        const SizedBox(height: Space.m),
        for (final (i, s) in _slots.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(s.label.isEmpty ? context.tr('slot_n', {'n': i + 1}) : s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800))),
                  IconBtn(icon: Icons.delete_outline_rounded, tooltip: context.tr('delete'), onPressed: () => setState(() => _slots.removeAt(i))),
                ]),
                const SizedBox(height: Space.s),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ChoiceChipX(label: '${context.tr('from')} ${slotTime(s.start, s.start).split('–').first}', icon: Icons.schedule_rounded, selected: false, onTap: () => _time(s, true)),
                  ChoiceChipX(label: '${context.tr('to')} ${slotTime(s.end, s.end).split('–').first}', icon: Icons.schedule_rounded, selected: false, onTap: () => _time(s, false)),
                  ChoiceChipX(label: _rupees(s.price), icon: Icons.currency_rupee_rounded, selected: false, onTap: () => _price(s)),
                ]),
                const SizedBox(height: Space.s),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (var d = 0; d < 7; d++)
                    ChoiceChipX(
                      label: context.tr(_dayShort[d]),
                      selected: s.days & (1 << d) != 0,
                      onTap: () => setState(() {
                        final next = s.days ^ (1 << d);
                        if (next != 0) s.days = next;
                      }),
                    ),
                ]),
              ]),
            ),
          ),
        if (_slots.isEmpty) Text(context.tr('no_slots_owner_body'), style: Tx.small(p.text2)),
        const SizedBox(height: Space.m),
        GoldButton(label: _busy ? context.tr('saving') : context.tr('save'), icon: Icons.check_rounded, onPressed: _busy ? null : _save),
      ]),
    );
  }
}

// ---------------------------------------------------------------- bookings list

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, this.owner = false});
  final bool owner; // open on "Requests for my grounds"

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late bool _incoming = widget.owner;
  ({List<Booking> asked, List<Booking> incoming})? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.sync.social.bookings();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _answer(Booking b, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.sync.social.answerBooking(b.id, action);
      _load();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(onlineError(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    final d = _data;
    final list = d == null ? const <Booking>[] : (_incoming ? d.incoming : d.asked);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.bg, title: Text(context.tr('my_bookings'))),
      body: !sync.loggedIn
          ? ListView(children: [
              EmptyState(icon: Icons.event_outlined, title: context.tr('my_bookings'), body: context.tr('login_needed'), actionLabel: context.tr('login'), onAction: () async {
                await loginAsPlayer(context);
                if (mounted) _load();
              }),
            ])
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.xl), children: [
                Segmented<bool>(
                  values: const [false, true],
                  labels: [context.tr('bookings_mine'), context.tr('bookings_incoming')],
                  selected: _incoming,
                  onChanged: (v) => setState(() => _incoming = v),
                ),
                const SizedBox(height: Space.m),
                if (d == null && _error == null)
                  const LoadingList(count: 2)
                else if (d == null)
                  OnlineError(error: _error!, onRetry: _load)
                else if (list.isEmpty)
                  EmptyState(icon: Icons.event_available_outlined, title: context.tr(_incoming ? 'no_incoming_bookings' : 'no_bookings'), body: context.tr(_incoming ? 'no_incoming_bookings_body' : 'no_bookings_body'))
                else
                  for (final b in list) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: _BookingCard(b: b, incoming: _incoming, onAnswer: (a) => _answer(b, a))),
              ]),
            ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.b, required this.incoming, required this.onAnswer});
  final Booking b;
  final bool incoming;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = switch (b.status) { 'accepted' => p.win, 'requested' => p.goldText, _ => p.text2 };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(incoming ? (b.team.isEmpty ? b.by : b.team) : b.groundName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800))),
          Tag(context.tr('booking_${b.status}'), color: color),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            bookingDate(context, b.date),
            if (b.start != null && b.end != null) slotTime(b.start!, b.end!),
            if (b.price > 0) _rupees(b.price),
            if (incoming) b.groundName,
          ].join(' · '),
          style: Tx.small(p.text2),
        ),
        if (b.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${b.note}”', style: Tx.small(p.text))),
        if (incoming && (b.phone ?? '').isNotEmpty && b.status != 'declined' && b.status != 'cancelled') ...[
          const SizedBox(height: Space.s),
          OutlineBtn(label: '${context.tr('call')} ${b.phone}', icon: Icons.call_rounded, height: 40, onPressed: () => openLink(context, 'tel:${b.phone!.replaceAll(' ', '')}')),
        ],
        if (incoming && b.status == 'requested') ...[
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(child: OutlineBtn(label: context.tr('decline'), height: 42, onPressed: () => onAnswer('decline'))),
            const SizedBox(width: Space.s),
            Expanded(child: GoldButton(label: context.tr('accept'), height: 42, onPressed: () => onAnswer('accept'))),
          ]),
        ],
        if (!incoming && (b.status == 'requested' || b.status == 'accepted')) ...[
          const SizedBox(height: Space.s),
          OutlineBtn(label: context.tr('cancel_booking'), height: 40, onPressed: () => onAnswer('cancel')),
        ],
      ]),
    );
  }
}
