// Matches: every match on GullyScore (live, upcoming, results) from the
// online service, or the matches saved on this phone.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'online.dart';
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
  bool _everyone = true; // All of GullyScore (online) vs this phone

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

        final online = context.sync.enabled;
        final everyone = online && _everyone;
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
            if (online)
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s), children: [
                  ChoiceChipX(label: context.tr('all_gullyscore'), icon: Icons.public_rounded, selected: _everyone, onTap: () => setState(() => _everyone = true)),
                  const SizedBox(width: Space.s),
                  ChoiceChipX(label: context.tr('my_phone'), icon: Icons.phone_android_rounded, selected: !_everyone, onTap: () => setState(() => _everyone = false)),
                ]),
              ),
            if (everyone) const Expanded(child: FeedView()),
            if (!everyone) ...[
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
            ],
          ]),
        );
      },
    );
  }
}

/// Every match on GullyScore: Live, Upcoming and Results tabs.
class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  String _kind = 'live';
  final Map<String, List<MatchListItem>> _lists = {};
  int _live = 0, _upcoming = 0;
  Object? _error;
  bool _loading = false, _more = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final kind = _kind;
    try {
      final old = _lists[kind] ?? const <MatchListItem>[];
      final before = more && old.isNotEmpty ? old.last.updated : 0;
      final r = await context.sync.social.feed(kind, before: before);
      if (!mounted) return;
      setState(() {
        _lists[kind] = more ? [...old, ...r.matches] : r.matches;
        _live = r.live;
        _upcoming = r.upcoming;
        _more = kind == 'results' && r.matches.length >= 30;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final list = _lists[_kind];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.edge),
        child: Segmented<String>(
          values: const ['live', 'upcoming', 'results'],
          labels: [
            _live > 0 ? '${context.tr('live')} · $_live' : context.tr('live'),
            _upcoming > 0 ? '${context.tr('upcoming')} · $_upcoming' : context.tr('upcoming'),
            context.tr('results'),
          ],
          selected: _kind,
          onChanged: (v) {
            setState(() => _kind = v);
            _load();
          },
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          color: p.goldText,
          backgroundColor: p.surface,
          onRefresh: () => _load(),
          child: ListView(padding: const EdgeInsets.only(top: Space.m, bottom: Space.xl), children: [
            if (list == null && _error == null)
              const LoadingList()
            else if (_error != null && (list == null || list.isEmpty))
              OnlineError(error: _error!, onRetry: _load)
            else if (list!.isEmpty)
              EmptyState(
                icon: _kind == 'upcoming' ? Icons.event_outlined : Icons.sports_cricket_outlined,
                title: context.tr(_kind == 'live' ? 'no_live_now' : _kind == 'upcoming' ? 'no_upcoming' : 'no_matches'),
                body: context.tr(_kind == 'upcoming' ? 'no_upcoming_body' : 'feed_empty_body'),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.m),
                child: Row(children: [
                  Icon(Icons.public_rounded, size: 16, color: p.win),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(context.tr('feed_note'), style: Tx.label(p.text2, w: FontWeight.w600))),
                ]),
              ),
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                  child: OnlineMatchCard(m: m, onTap: () => openFollowed(context, m.id)),
                ),
              if (_more)
                Padding(
                  padding: const EdgeInsets.all(Space.edge),
                  child: OutlineBtn(label: context.tr('load_more'), height: 44, onPressed: _loading ? null : () => _load(more: true)),
                ),
            ],
          ]),
        ),
      ),
    ]);
  }
}
