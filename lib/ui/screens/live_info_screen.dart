// Menu → Live streaming: what you get, how to go live, what you need, and
// answers to common questions. Free — no plans.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../live/youtube_embed.dart';
import '../widgets/common.dart';
import 'live_stream_screen.dart';

const _gold = Color(0xFFF4C247);
const _goldLight = Color(0xFFFFE7A3);

class LiveInfoScreen extends StatelessWidget {
  const LiveInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget heading(String a, String b, {String? sub}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.xl, Space.edge, Space.s),
          child: Column(children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$a '),
                TextSpan(text: b, style: TextStyle(color: p.goldText)),
              ]),
              textAlign: TextAlign.center,
              style: Tx.title(p.text).copyWith(fontSize: 22),
            ),
            if (sub != null) ...[const SizedBox(height: 4), Text(sub, textAlign: TextAlign.center, style: Tx.small(p.text2))],
          ]),
        );
    final features = [
      (Icons.subtitles_rounded, 'li_f1_t', 'li_f1_b'),
      (Icons.auto_awesome_rounded, 'li_f2_t', 'li_f2_b'),
      (Icons.replay_rounded, 'li_f3_t', 'li_f3_b'),
      (Icons.movie_filter_rounded, 'li_f4_t', 'li_f4_b'),
      (Icons.storefront_rounded, 'li_f5_t', 'li_f5_b'),
      (Icons.smart_display_rounded, 'li_f6_t', 'li_f6_b'),
    ];
    final steps = [('li_s1_t', 'li_s1_b'), ('li_s2_t', 'li_s2_b'), ('li_s3_t', 'li_s3_b'), ('li_s4_t', 'li_s4_b')];
    final needs = [
      ('assets/live/phone.png', 'li_n1_t', 'li_n1_b'),
      ('assets/live/internet.png', 'li_n2_t', 'li_n2_b'),
      ('assets/live/powerbank.png', 'li_n3_t', 'li_n3_b'),
      ('assets/live/tripod.png', 'li_n4_t', 'li_n4_b'),
    ];
    final faqs = List.generate(8, (i) => ('li_q${i + 1}', 'li_a${i + 1}'));
    Widget goLive() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: GoldButton(label: context.tr('li_go'), icon: Icons.fiber_manual_record_rounded, onPressed: () => pickMatchToStream(context)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('live_streaming'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        // ---------- hero
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                const TextSpan(children: [TextSpan(text: 'GULLYSCORE '), TextSpan(text: 'LIVE', style: TextStyle(color: _gold))]),
                style: TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 40, color: p.text, height: 1),
              ),
            ),
            const SizedBox(height: 6),
            Text(context.tr('li_sub'), textAlign: TextAlign.center, style: Tx.body(p.text2)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: const AspectRatio(aspectRatio: 16 / 9, child: _Sample(six: false)),
          ),
        ),
        goLive(),
        const SizedBox(height: 8),
        Text('✓ ${context.tr('li_free')}', textAlign: TextAlign.center, style: Tx.small(p.win, w: FontWeight.w800)),
        // ---------- what you get
        heading(context.tr('li_get_a'), context.tr('li_get_b')),
        for (final (i, f) in features.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, 8),
            child: AppCard(
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
                  child: Icon(f.$1, color: p.goldText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('0${i + 1}  ${context.tr(f.$2)}', style: Tx.body(p.text, w: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(context.tr(f.$3), style: Tx.small(p.text2)),
                  ]),
                ),
              ]),
            ),
          ),
        // ---------- how
        heading(context.tr('li_how_a'), context.tr('li_how_b'), sub: context.tr('li_how_sub')),
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, 8),
            child: AppCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 30, child: Text('${i + 1}', style: TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 30, color: p.goldText.withValues(alpha: 0.6), height: 1))),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr(s.$1), style: Tx.body(p.text, w: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(context.tr(s.$2), style: Tx.small(p.text2)),
                  ]),
                ),
              ]),
            ),
          ),
        // ---------- what you need
        heading(context.tr('li_need_a'), context.tr('li_need_b')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final n in needs)
                SizedBox(
                  width: w,
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(Corners.card)),
                        child: Container(
                          height: w * 0.86,
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1, colors: [Colors.white, Color(0xFFEEF1F6), Color(0xFFDDE3EC)]),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(n.$1, fit: BoxFit.contain),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                        child: Column(children: [
                          Text(context.tr(n.$2), textAlign: TextAlign.center, style: Tx.small(p.text, w: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(context.tr(n.$3), textAlign: TextAlign.center, style: Tx.label(p.text2)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]);
          }),
        ),
        // ---------- how it looks
        heading(context.tr('li_look_a'), context.tr('li_look_b'), sub: context.tr('li_look_sub')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: ClipRRect(borderRadius: BorderRadius.circular(18), child: const AspectRatio(aspectRatio: 16 / 9, child: _Sample(six: true))),
        ),
        // ---------- questions
        heading(context.tr('li_faq_a'), context.tr('li_faq_b')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(children: [
                for (final (i, f) in faqs.indexed)
                  ExpansionTile(
                    initiallyExpanded: i == 0,
                    title: Text(context.tr(f.$1), style: Tx.body(p.text, w: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedAlignment: Alignment.centerLeft,
                    children: [
                      Text(context.tr(f.$2), style: Tx.small(p.text2)),
                      if (f.$1 == 'li_q7')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton(onPressed: () => explainViewers(context), child: Text('👁 ${context.tr('viewers_what')}')),
                        ),
                    ],
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        goLive(),
      ]),
    );
  }
}

/// A sample of what the live video looks like (drawn).
class _Sample extends StatelessWidget {
  const _Sample({required this.six});
  final bool six;
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(child: FieldPicture()),
      Positioned(left: 10, top: 10, child: liveTag('LIVE')),
      if (six)
        Positioned(
          left: 10,
          top: 36,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: const Text('Sharma Hardware', style: TextStyle(color: Color(0xFF7B1E14), fontWeight: FontWeight.w800, fontSize: 10)),
          ),
        ),
      if (six)
        Center(
          child: Transform.rotate(
            angle: -0.07,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              color: const Color(0xFF8B3FE8),
              child: const Text('SIX!', style: TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 36, color: Colors.white)),
            ),
          ),
        )
      else
        Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
          ),
        ),
      Positioned(
        left: 8,
        right: 8,
        bottom: 8,
        height: 24,
        child: MediaQuery.withNoTextScaling(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [_gold, _goldLight])),
                child: const Text('MAD 142/3', style: TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0B1220))),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xF00B1220),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.centerLeft,
                  child: const Text('16.4 ov   Suraj 51*', maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5)),
                ),
              ),
              Container(
                color: const Color(0xFFE53935),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                child: const Text('NEED 33', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
