// Leaderboard: top run scorers and wicket takers on all of GullyScore.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _kind = 'runs';
  int _days = 0;
  Future<List<Leader>>? _f;

  void _load() {
    final f = context.sync.social.leaderboard(kind: _kind, days: _days);
    setState(() {
      _f = f;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.sync.enabled) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('leaderboard'), style: Tx.title(p.text).copyWith(fontSize: 20))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Segmented<String>(
              values: const ['runs', 'wickets'],
              labels: [context.tr('most_runs'), context.tr('most_wickets')],
              selected: _kind,
              onChanged: (v) {
                _kind = v;
                _load();
              },
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0), children: [
              ChoiceChipX(label: context.tr('all_time'), selected: _days == 0, onTap: () {
                _days = 0;
                _load();
              }),
              const SizedBox(width: Space.s),
              ChoiceChipX(label: context.tr('last_30_days'), selected: _days == 30, onTap: () {
                _days = 30;
                _load();
              }),
            ]),
          ),
          Expanded(
            child: !context.sync.enabled
                ? EmptyState(icon: Icons.cloud_off_rounded, title: context.tr('leaderboard'), body: context.tr('online_not_set_up'))
                : FutureBuilder<List<Leader>>(
                    future: _f,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const SingleChildScrollView(child: Padding(padding: EdgeInsets.only(top: Space.m), child: LoadingList()));
                      if (snap.hasError) return Padding(padding: const EdgeInsets.only(top: Space.m), child: OnlineError(error: snap.error!, onRetry: _load));
                      final list = snap.data ?? const <Leader>[];
                      if (list.isEmpty) return EmptyState(icon: Icons.leaderboard_outlined, title: context.tr('leaderboard'), body: context.tr('leaderboard_empty'));
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl),
                        itemCount: list.length,
                        separatorBuilder: (c, i) => const SizedBox(height: Space.s),
                        itemBuilder: (c, i) {
                          final l = list[i];
                          final medal = i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}';
                          return AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            borderColor: i == 0 ? p.gold : null,
                            child: Row(children: [
                              SizedBox(width: 34, child: Text(medal, textAlign: TextAlign.center, style: Tx.score(i < 3 ? 22 : 18, p.text2, w: FontWeight.w800))),
                              const SizedBox(width: Space.s),
                              CircleAvatar(radius: 18, backgroundColor: teamColorFor(l.team.isEmpty ? l.name : l.team), child: Text(initials(l.name), style: Tx.label(Colors.white, w: FontWeight.w800))),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                                  Text([if (l.team.isNotEmpty) l.team, context.tr('matches_n', {'n': l.matches})].join(' · '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w600)),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${_kind == 'runs' ? l.runs : l.wickets}', style: Tx.score(26, i == 0 ? p.goldText : p.text, w: FontWeight.w800)),
                                Text(context.tr(_kind == 'runs' ? 'runs' : 'wickets'), style: Tx.label(p.text2)),
                              ]),
                            ]),
                          );
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
