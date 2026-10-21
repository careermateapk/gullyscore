// Questions and answers: a full FAQ screen with search, and a small
// "?" sheet that shows only the answers for the screen you are on.
// Everything is inside the app, so it works offline.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'scoring_sheets.dart';

class Faq {
  const Faq(this.id, this.category, this.topics);
  final String id;
  final String category; // scoring, sharing, data, other
  final Set<String> topics; // screens where the "?" sheet shows it
}

const faqs = <Faq>[
  Faq('undo', 'scoring', {'scoring'}),
  Faq('wide', 'scoring', {'scoring'}),
  Faq('noball', 'scoring', {'scoring'}),
  Faq('strike', 'scoring', {'scoring'}),
  Faq('runout', 'scoring', {'scoring'}),
  Faq('retired', 'scoring', {'scoring'}),
  Faq('shotmap', 'scoring', {'scoring'}),
  Faq('five', 'scoring', {'scoring'}),
  Faq('missing_player', 'scoring', {'scoring', 'new_match'}),
  Faq('offline', 'data', {'scoring', 'settings'}),
  Faq('where_saved', 'data', {'settings'}),
  Faq('backup', 'data', {'settings'}),
  Faq('uninstall', 'data', {'settings'}),
  Faq('photos', 'data', {'settings'}),
  Faq('delete', 'data', {'settings'}),
  Faq('share', 'sharing', {'match_centre'}),
  Faq('live', 'sharing', {'match_centre'}),
  Faq('win_chance', 'other', {'match_centre'}),
  Faq('commentary', 'other', {'match_centre'}),
  Faq('reports', 'other', {'news'}),
  Faq('tournaments', 'other', {'series', 'tournament'}),
  Faq('tournament_formats', 'other', {'tournament'}),
  Faq('knockout_tie', 'other', {'tournament'}),
  Faq('mvp', 'other', {'tournament', 'match_centre'}),
  Faq('stats', 'other', {'series'}),
];

/// The small "?" sheet for one screen.
Future<void> showHelp(BuildContext context, String topic) {
  final items = faqs.where((f) => f.topics.contains(topic)).toList();
  return showAppSheet<void>(context, (ctx) {
    final p = Palette.of(ctx);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(
          ctx.tr('quick_help'),
          trailing: _LangSwitch(),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            children: [
              for (var i = 0; i < items.length; i++) _FaqTile(faq: items[i], initiallyOpen: i == 0),
              const SizedBox(height: Space.m),
              Row(children: [
                Icon(Icons.offline_pin_rounded, size: 18, color: p.win),
                const SizedBox(width: Space.s),
                Expanded(child: Text(ctx.tr('help_offline_note'), style: Tx.small(p.text2))),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.l),
          child: Row(children: [
            Expanded(
              child: OutlineBtn(
                label: ctx.tr('more_questions'),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqScreen()));
                },
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(child: GoldButton(label: ctx.tr('got_it'), onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      ]),
    );
  });
}

class _LangSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return SizedBox(
      width: 112,
      child: Segmented<String>(values: const ['en', 'hi'], labels: const ['EN', 'हिं'], selected: s.lang, onChanged: s.setLang),
    );
  }
}

class _FaqTile extends StatefulWidget {
  const _FaqTile({super.key, required this.faq, this.initiallyOpen = false});
  final Faq faq;
  final bool initiallyOpen;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: AppCard(
        padding: EdgeInsets.zero,
        color: _open ? (p.dark ? const Color(0xFF13223A) : const Color(0xFFFFFBF0)) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: BorderRadius.circular(Corners.card),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(children: [
                  Expanded(child: Text(context.tr('faq_${widget.faq.id}_q'), style: Tx.body(p.text, w: FontWeight.w800))),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: Motion.fade,
                    child: Icon(Icons.expand_more_rounded, color: _open ? p.goldText : p.text2),
                  ),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: context.reduceMotion ? Duration.zero : Motion.fade,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Text(context.tr('faq_${widget.faq.id}_a'), style: Tx.body(p.text2).copyWith(height: 1.55)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  String _query = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final q = _query.trim().toLowerCase();
    final list = faqs.where((f) {
      if (_cat != null && f.category != _cat) return false;
      if (q.isEmpty) return true;
      final text = '${context.tr('faq_${f.id}_q')} ${context.tr('faq_${f.id}_a')}'.toLowerCase();
      return text.contains(q);
    }).toList();
    const cats = ['scoring', 'sharing', 'data', 'other'];
    const icons = [Icons.sports_cricket_rounded, Icons.share_rounded, Icons.lock_outline_rounded, Icons.lightbulb_outline_rounded];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('help_and_faq'), style: Tx.title(p.text).copyWith(fontSize: 20))),
              _LangSwitch(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded, color: p.text2), hintText: context.tr('search_questions')),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
              children: [
                ChoiceChipX(label: context.tr('all'), selected: _cat == null, onTap: () => setState(() => _cat = null)),
                for (var i = 0; i < cats.length; i++) ...[
                  const SizedBox(width: Space.s),
                  ChoiceChipX(
                    label: context.tr('faq_cat_${cats[i]}'),
                    icon: icons[i],
                    selected: _cat == cats[i],
                    onTap: () => setState(() => _cat = _cat == cats[i] ? null : cats[i]),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: EmptyState(icon: Icons.search_off_rounded, title: context.tr('no_answers'), body: context.tr('no_answers_body')))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl),
                    children: [for (final f in list) _FaqTile(key: ValueKey(f.id), faq: f)],
                  ),
          ),
        ]),
      ),
    );
  }
}
