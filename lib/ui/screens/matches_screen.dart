// All matches saved on this phone, filtered by status and series.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'new_match_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int _seg = 0; // 0 in progress, 1 results, 2 all
  String? _title;

  Future<void> _confirmDelete(MatchRecord m) async {
    final repo = context.repo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_match_q')),
        content: Text(ctx.tr('delete_match_body', {'a': repo.teamName(m.teamA), 'b': repo.teamName(m.teamB)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'), style: TextStyle(color: Palette.of(ctx).liveText))),
        ],
      ),
    );
    if (ok == true) repo.deleteMatch(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final all = repo.matchList;
        final titles = {for (final m in all) if (m.title.isNotEmpty) m.title}.toList();
        final states = {for (final m in all) m.id: m.state};
        final list = all.where((m) {
          if (_title != null && m.title != _title) return false;
          final f = states[m.id]!.finished;
          return _seg == 2 || (_seg == 0 ? !f : f);
        }).toList();

        return SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
              child: Row(children: [
                Expanded(child: Semantics(header: true, child: Text(context.tr('nav_matches'), style: Tx.title(p.text)))),
                IconBtn(icon: Icons.add_rounded, tooltip: context.tr('new_match'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMatchScreen()))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.edge),
              child: Segmented<int>(
                values: const [0, 1, 2],
                labels: [context.tr('in_progress'), context.tr('results'), context.tr('all')],
                selected: _seg,
                onChanged: (v) => setState(() => _seg = v),
              ),
            ),
            if (titles.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
                  children: [
                    ChoiceChipX(label: context.tr('all_series'), selected: _title == null, onTap: () => setState(() => _title = null)),
                    for (final t in titles) ...[
                      const SizedBox(width: Space.s),
                      ChoiceChipX(label: t, selected: _title == t, onTap: () => setState(() => _title = t)),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? ListView(children: [
                      EmptyState(
                        icon: Icons.sports_cricket_outlined,
                        title: _seg == 0 ? context.tr('no_matches_in_progress') : context.tr('no_matches'),
                        body: context.tr('no_matches_body'),
                        actionLabel: context.tr('score_a_match'),
                        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMatchScreen())),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl),
                      itemCount: list.length + 1,
                      separatorBuilder: (c, i) => const SizedBox(height: Space.s),
                      itemBuilder: (c, i) {
                        if (i == list.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: Space.s),
                            child: Text(context.tr('long_press_delete'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
                          );
                        }
                        final m = list[i];
                        final st = states[m.id]!;
                        return GestureDetector(
                          onLongPress: () => _confirmDelete(m),
                          child: st.finished ? ResultCard(m: m, st: st) : SizedBox(height: 254, child: FeaturedMatchCard(m: m, st: st)),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
