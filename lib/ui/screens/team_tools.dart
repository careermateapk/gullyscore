// Team tools for players of a team: "Who is coming?" and the team khata.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/models.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'scoring_sheets.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Widget _header(BuildContext context, String title, {Widget? trailing}) {
  final p = Palette.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
    child: Row(children: [
      IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
      const SizedBox(width: Space.m),
      Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 20))),
      if (trailing != null) trailing,
    ]),
  );
}

Widget _stat(BuildContext context, String label, String value, Color color) {
  final p = Palette.of(context);
  return Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.text.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.heroLine)),
      child: Column(children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: Tx.score(26, color, w: FontWeight.w900))),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
      ]),
    ),
  );
}

// ---------------------------------------------------------------- Who is coming?

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key, required this.team});
  final TeamSummary team;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  List<Ask>? _asks;
  Object? _error;
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await context.sync.social.asks(widget.team.scorerId, widget.team.id);
      if (mounted) setState(() => _asks = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _replace(Ask a) => setState(() => _asks = [for (final x in _asks ?? const <Ask>[]) x.id == a.id ? a : x]);

  Future<void> _create() async {
    final next = widget.team.next;
    final vs = next == null ? '' : '${context.tr('vs')} ${next.teamA.id == widget.team.id ? next.teamB.name : next.teamA.name}';
    final title = TextEditingController(text: vs);
    final when = TextEditingController(text: next?.scheduled == null ? '' : whenText(context, next!.scheduled!));
    final place = TextEditingController(text: next?.ground ?? '');
    var need = 11;
    final ok = await showAppSheet<bool>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final p = Palette.of(ctx);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetTitle(ctx.tr('ask_who_coming')),
            TextField(controller: title, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: ctx.tr('ask_title_hint'))),
            const SizedBox(height: Space.s),
            TextField(controller: when, decoration: InputDecoration(hintText: ctx.tr('when_hint'), prefixIcon: const Icon(Icons.schedule_rounded, size: 20))),
            const SizedBox(height: Space.s),
            TextField(controller: place, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: ctx.tr('place_hint'), prefixIcon: const Icon(Icons.place_outlined, size: 20))),
            const SizedBox(height: Space.s),
            Row(children: [
              Expanded(child: Text(ctx.tr('players_needed'), style: Tx.small(p.text2, w: FontWeight.w700))),
              IconBtn(icon: Icons.remove_rounded, tooltip: '-', onPressed: need > 2 ? () => set(() => need--) : null),
              SizedBox(width: 40, child: Text('$need', textAlign: TextAlign.center, style: Tx.score(22, p.text, w: FontWeight.w800))),
              IconBtn(icon: Icons.add_rounded, tooltip: '+', onPressed: need < 30 ? () => set(() => need++) : null),
            ]),
            const SizedBox(height: Space.m),
            GoldButton(label: ctx.tr('ask_team'), icon: Icons.campaign_rounded, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        );
      });
    });
    if (ok == true && title.text.trim().isNotEmpty && mounted) {
      try {
        final a = await context.sync.social.createAsk(widget.team.scorerId, widget.team.id, title: title.text.trim(), when: when.text.trim(), place: place.text.trim(), need: need);
        if (mounted) setState(() => _asks = [a, ...?_asks]);
      } catch (e) {
        if (mounted) _snack(context, onlineError(context, e));
      }
    }
    title.dispose();
    when.dispose();
    place.dispose();
  }

  Future<void> _answer(Ask a, String answer) async {
    try {
      _replace(await context.sync.social.answerAsk(a.id, answer));
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  Future<void> _remind(Ask a) async {
    final waiting = a.players.where((x) => x.answer.isEmpty).map((x) => x.name).toList();
    final text = context.tr('remind_text', {
      'title': a.title,
      'when': [a.when, a.place].where((x) => x.isNotEmpty).join(', '),
      'names': waiting.join(', '),
      'n': a.yes,
      'need': a.need,
    });
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.gold,
        foregroundColor: const Color(0xFF0B1220),
        onPressed: _create,
        icon: const Icon(Icons.campaign_rounded),
        label: Text(context.tr('ask_team'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context, context.tr('who_coming')),
          Expanded(
            child: RefreshIndicator(
              color: p.goldText,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                if (_asks == null && _error == null)
                  const LoadingList(count: 2)
                else if (_asks == null)
                  OnlineError(error: _error!, onRetry: _load)
                else if (_asks!.isEmpty)
                  EmptyState(icon: Icons.how_to_reg_outlined, title: context.tr('who_coming'), body: context.tr('who_coming_empty'), actionLabel: context.tr('ask_team'), onAction: _create)
                else
                  for (final a in _asks!) _askCard(context, a),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _askCard(BuildContext context, Ask a) {
    final p = Palette.of(context);
    final open = _open.contains(a.id);
    final short = a.need - a.yes;
    Widget answerBtn(String v, String label, Color c) {
      final on = a.myAnswer == v;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: on ? c : p.raised,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _answer(a, v),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: Tx.body(on ? const Color(0xFF0B1220) : p.text, w: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.m),
      child: HeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Crest(color: teamColorFor(widget.team.name), text: initials(widget.team.name), size: 36),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 17)),
                if (a.when.isNotEmpty || a.place.isNotEmpty)
                  Text('📅 ${[a.when, a.place].where((x) => x.isNotEmpty).join(' · ')}', style: Tx.small(p.text2, w: FontWeight.w600)),
              ]),
            ),
            if (a.mine)
              IconButton(
                tooltip: context.tr('delete'),
                icon: Icon(Icons.delete_outline_rounded, color: p.text2),
                onPressed: () async {
                  try {
                    await context.sync.social.deleteAsk(a.id);
                    _load();
                  } catch (e) {
                    if (context.mounted) _snack(context, onlineError(context, e));
                  }
                },
              ),
          ]),
          const SizedBox(height: Space.m),
          Row(children: [
            _stat(context, context.tr('coming'), '${a.yes}', p.win),
            const SizedBox(width: Space.s),
            _stat(context, context.tr('not_coming'), '${a.no}', p.liveText),
            const SizedBox(width: Space.s),
            _stat(context, context.tr('no_reply'), '${a.waiting + a.maybe}', p.text),
          ]),
          const SizedBox(height: Space.s),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Text(short <= 0 ? context.tr('team_full', {'need': a.need}) : context.tr('need_more', {'need': a.need, 'n': short}),
                style: Tx.small(p.text, w: FontWeight.w800)),
          ),
          const SizedBox(height: Space.m),
          Text(context.tr('are_you_coming'), style: Tx.small(p.text, w: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            answerBtn('yes', '✓ ${context.tr('yes')}', p.win),
            answerBtn('maybe', context.tr('maybe'), p.gold),
            answerBtn('no', '✕ ${context.tr('no')}', p.liveText),
          ]),
          const SizedBox(height: Space.s),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => setState(() => open ? _open.remove(a.id) : _open.add(a.id)),
                icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.text2),
                label: Text(context.tr('squad_n', {'n': a.players.length}), style: Tx.small(p.text2, w: FontWeight.w800)),
              ),
            ),
            if (a.waiting > 0)
              Flexible(
                child: TextButton.icon(
                  onPressed: () => _remind(a),
                  icon: Icon(Icons.chat_rounded, size: 18, color: p.goldText),
                  label: Text(context.tr('remind_n', {'n': a.waiting}), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.goldText, w: FontWeight.w800)),
                ),
              ),
          ]),
          if (open)
            for (final x in a.players)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  CircleAvatar(radius: 15, backgroundColor: teamColorFor(x.name), child: Text(initials(x.name), style: Tx.label(Colors.white, w: FontWeight.w800))),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w700))),
                  Tag(
                    context.tr(x.answer.isEmpty ? 'no_reply' : x.answer == 'yes' ? 'coming' : x.answer == 'no' ? 'not_coming' : 'maybe'),
                    color: x.answer == 'yes' ? p.win : x.answer == 'no' ? p.liveText : p.text2,
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Team khata

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _rupees(int n) {
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

class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key, required this.team});
  final TeamSummary team;

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Khata? _k;
  Object? _error;

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _k = null;
    });
    try {
      final k = await context.sync.social.khata(widget.team.scorerId, widget.team.id, month: _monthKey);
      if (mounted) setState(() => _k = k);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _shift(int d) {
    setState(() => _month = DateTime(_month.year, _month.month + d));
    _load();
  }

  Future<void> _add() async {
    final k = _k;
    if (k == null || k.people.isEmpty) return;
    var kind = 'expense';
    var who = k.people.first.playerId;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final p = Palette.of(ctx);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetTitle(ctx.tr('khata_add')),
            Segmented<String>(
              values: const ['expense', 'payment'],
              labels: [ctx.tr('khata_expense'), ctx.tr('khata_payment')],
              selected: kind,
              onChanged: (v) => set(() => kind = v),
            ),
            const SizedBox(height: Space.s),
            Text(ctx.tr(kind == 'expense' ? 'khata_expense_sub' : 'khata_payment_sub'), style: Tx.label(p.text2, w: FontWeight.w600)),
            const SizedBox(height: Space.m),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(hintText: ctx.tr('amount_hint'), prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20)),
            ),
            const SizedBox(height: Space.s),
            if (kind == 'expense') ...[
              TextField(controller: note, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: ctx.tr('khata_note_hint'))),
              const SizedBox(height: Space.s),
            ],
            DropdownButtonFormField<String>(
              initialValue: who,
              isExpanded: true,
              decoration: InputDecoration(labelText: ctx.tr(kind == 'expense' ? 'who_spent' : 'who_paid')),
              items: [for (final x in k.people) DropdownMenuItem(value: x.playerId, child: Text(x.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => set(() => who = v ?? who),
            ),
            const SizedBox(height: Space.m),
            GoldButton(label: ctx.tr('save'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        );
      });
    });
    final n = int.tryParse(amount.text.trim()) ?? 0;
    final text = note.text.trim();
    amount.dispose();
    note.dispose();
    if (ok != true || n <= 0 || !mounted) return;
    try {
      final r = await context.sync.social.addKhata(widget.team.scorerId, widget.team.id, kind: kind, amount: n, playerId: who, note: text, month: _monthKey);
      if (mounted) setState(() => _k = r);
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  Future<void> _askUpi() async {
    final k = _k;
    if (k == null) return;
    String upi = '';
    try {
      upi = (await SharedPreferences.getInstance()).getString('khata.upi') ?? '';
    } catch (_) {}
    if (!mounted) return;
    final ctrl = TextEditingController(text: upi);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('your_upi')),
        content: TextField(controller: ctrl, autofocus: upi.isEmpty, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(hintText: ctx.tr('upi_hint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(ctx.tr('ok'))),
        ],
      ),
    );
    ctrl.dispose();
    if (v == null || !mounted) return;
    try {
      (await SharedPreferences.getInstance()).setString('khata.upi', v);
    } catch (_) {}
    if (!mounted) return;
    final dues = k.people.where((x) => x.due > 0).map((x) => '• ${x.name}: ${_rupees(x.due)}').join('\n');
    final text = context.tr('khata_ask_text', {
      'team': widget.team.name,
      'month': '${_monthNames[_month.month - 1]} ${_month.year}',
      'spent': _rupees(k.spent),
      'share': _rupees(k.share),
      'dues': dues,
      'upi': v.isEmpty ? '' : '\nUPI: $v',
    });
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final k = _k;
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: k == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: p.gold,
              foregroundColor: const Color(0xFF0B1220),
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('khata_add'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context, context.tr('team_khata')),
          Expanded(
            child: RefreshIndicator(
              color: p.goldText,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                  child: HeroCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Crest(color: teamColorFor(widget.team.name), text: initials(widget.team.name), size: 30),
                        const SizedBox(width: Space.s),
                        Expanded(child: Text(widget.team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800))),
                      ]),
                      const SizedBox(height: Space.s),
                      Row(children: [
                        IconBtn(icon: Icons.chevron_left_rounded, tooltip: context.tr('previous_month'), onPressed: () => _shift(-1)),
                        Expanded(child: Text('${_monthNames[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: Tx.body(p.text, w: FontWeight.w800))),
                        IconBtn(icon: Icons.chevron_right_rounded, tooltip: context.tr('next_month'), onPressed: () => _shift(1)),
                      ]),
                      if (k != null) ...[
                        const SizedBox(height: Space.m),
                        Row(children: [
                          _stat(context, context.tr('spent'), _rupees(k.spent), p.text),
                          const SizedBox(width: Space.s),
                          _stat(context, context.tr('per_player'), _rupees(k.share), p.goldText),
                          const SizedBox(width: Space.s),
                          _stat(context, context.tr('to_collect'), _rupees(k.pending), k.pending > 0 ? p.liveText : p.win),
                        ]),
                        const SizedBox(height: Space.s),
                        Text(context.tr('khata_split_note', {'n': k.players}), style: Tx.label(p.text2, w: FontWeight.w600)),
                      ],
                    ]),
                  ),
                ),
                if (k == null && _error == null)
                  const Padding(padding: EdgeInsets.only(top: Space.m), child: LoadingList(count: 2))
                else if (k == null)
                  Padding(padding: const EdgeInsets.only(top: Space.m), child: OnlineError(error: _error!, onRetry: _load))
                else ...[
                  SectionHeader(context.tr('still_to_pay'), action: k.pending > 0 ? context.tr('ask_on_upi') : null, onAction: k.pending > 0 ? _askUpi : null),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                    child: AppCard(
                      child: k.people.every((x) => x.due == 0)
                          ? Text(context.tr(k.spent == 0 ? 'khata_empty' : 'all_paid'), style: Tx.small(p.text2))
                          : Column(children: [
                              for (final x in k.people.where((x) => x.due > 0))
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    CircleAvatar(radius: 16, backgroundColor: teamColorFor(x.name), child: Text(initials(x.name), style: Tx.label(Colors.white, w: FontWeight.w800))),
                                    const SizedBox(width: Space.s),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
                                        Text(context.tr('paid_of', {'a': _rupees(x.paid), 'b': _rupees(k.share)}), style: Tx.label(p.text2)),
                                      ]),
                                    ),
                                    Text(_rupees(x.due), style: Tx.score(20, p.liveText, w: FontWeight.w800)),
                                  ]),
                                ),
                            ]),
                    ),
                  ),
                  SectionHeader(context.tr('khata_entries')),
                  if (k.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                      child: AppCard(child: Text(context.tr('khata_empty'), style: Tx.small(p.text2))),
                    ),
                  for (final i in k.items)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                      child: AppCard(
                        child: Row(children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(11)),
                            child: Icon(i.expense ? Icons.receipt_long_rounded : Icons.payments_rounded, size: 20, color: i.expense ? p.goldText : p.win),
                          ),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(i.expense ? (i.note.isEmpty ? context.tr('khata_expense') : i.note) : context.tr('paid_share', {'name': i.name}),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
                              Text(i.expense ? context.tr('spent_by', {'name': i.name, 'd': dayText(context, i.created)}) : dayText(context, i.created),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                            ]),
                          ),
                          Text(_rupees(i.amount), style: Tx.score(19, i.expense ? p.text : p.win, w: FontWeight.w800)),
                          IconButton(
                            tooltip: context.tr('delete'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded, size: 18, color: p.text2),
                            onPressed: () async {
                              try {
                                final r = await context.sync.social.deleteKhata(i.id);
                                if (mounted) setState(() => _k = r);
                              } catch (e) {
                                if (context.mounted) _snack(context, onlineError(context, e));
                              }
                            },
                          ),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
