// Tournament sponsors: a banner on live scores, and a sheet to manage them.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/tournament.dart';
import '../screens/scoring_sheets.dart';
import 'common.dart';

const sponsorRoles = ['title', 'six', 'potm', 'other'];

class SponsorBanner extends StatelessWidget {
  const SponsorBanner({super.key, required this.sponsors});
  final List<Sponsor> sponsors;

  @override
  Widget build(BuildContext context) {
    if (sponsors.isEmpty) return const SizedBox.shrink();
    final p = Palette.of(context);
    final title = sponsors.where((s) => s.role == 'title').firstOrNull ?? sponsors.first;
    final rest = sponsors.where((s) => !identical(s, title)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Color(0xFF3A2A00), Color(0xFF1B1400)]),
            border: Border.all(color: const Color(0xFF6B5212)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.gold, borderRadius: BorderRadius.circular(10)),
              child: Text(initials(title.name), style: Tx.small(const Color(0xFF0B1220), w: FontWeight.w900)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('sponsor_${title.role}').toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(const Color(0xFFE9C46A), w: FontWeight.w800).copyWith(letterSpacing: 0.6)),
                Text(title.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(Colors.white, w: FontWeight.w800)),
                if (title.phone.isNotEmpty || title.place.isNotEmpty)
                  Text([if (title.phone.isNotEmpty) '📞 ${title.phone}', if (title.place.isNotEmpty) title.place].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(const Color(0xFFCDBF96), w: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in rest) Tag('${context.tr('sponsor_${s.role}')}: ${s.name}', color: p.goldText),
          ]),
        ],
      ]),
    );
  }
}

Future<void> showSponsorsSheet(BuildContext context, Tournament t) {
  return showAppSheet<void>(context, (ctx) => _SponsorsSheet(t: t));
}

class _SponsorsSheet extends StatefulWidget {
  const _SponsorsSheet({required this.t});
  final Tournament t;

  @override
  State<_SponsorsSheet> createState() => _SponsorsSheetState();
}

class _SponsorsSheetState extends State<_SponsorsSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _place = TextEditingController();
  String _role = 'title';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _place.dispose();
    super.dispose();
  }

  void _add() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    context.repo.addSponsor(widget.t, Sponsor(name: n, role: _role, phone: _phone.text.trim(), place: _place.text.trim()));
    _name.clear();
    _phone.clear();
    _place.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = widget.t;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('sponsors'), subtitle: context.tr('sponsors_sub')),
        for (var i = 0; i < t.sponsors.length; i++)
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.sponsors[i].name, style: Tx.body(p.text, w: FontWeight.w800)),
                  Text(context.tr('sponsor_${t.sponsors[i].role}'), style: Tx.label(p.goldText, w: FontWeight.w700)),
                ]),
              ),
              IconButton(
                tooltip: context.tr('delete'),
                icon: Icon(Icons.delete_outline_rounded, color: p.text2),
                onPressed: () {
                  context.repo.removeSponsor(t, i);
                  setState(() {});
                },
              ),
            ]),
          ),
        const SizedBox(height: Space.m),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in sponsorRoles) ChoiceChipX(label: context.tr('sponsor_$r'), selected: _role == r, onTap: () => setState(() => _role = r)),
        ]),
        const SizedBox(height: Space.s),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('sponsor_name_hint'))),
        const SizedBox(height: Space.s),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: context.tr('sponsor_phone_hint'))),
        const SizedBox(height: Space.s),
        TextField(controller: _place, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: context.tr('sponsor_place_hint'))),
        const SizedBox(height: Space.m),
        GoldButton(label: context.tr('add_sponsor'), icon: Icons.add_rounded, onPressed: _add),
      ]),
    );
  }
}
