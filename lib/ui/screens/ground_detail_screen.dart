// One ground: photos, call / Google Maps / share, and tabs for About,
// Photos, Reviews, Matches, Tournaments and Insights.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'grounds_screen.dart';
import 'info_screens.dart';
import 'match_centre_screen.dart';
import 'online.dart';
import 'ratings_screens.dart';
import 'register_ground_screen.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String mapsLink(Ground g) => 'https://www.google.com/maps/search/?api=1&query=${g.lat},${g.lng}';

class GroundDetailScreen extends StatefulWidget {
  const GroundDetailScreen({super.key, required this.groundId, this.lat, this.lng});
  final String groundId;
  final double? lat, lng;

  @override
  State<GroundDetailScreen> createState() => _GroundDetailScreenState();
}

const _tabs = ['about', 'photos', 'reviews', 'matches', 'tournaments', 'insights'];

class _GroundDetailScreenState extends State<GroundDetailScreen> {
  Ground? _g;
  Object? _error;
  String _tab = 'about';
  int _page = 0;
  Future<List<GroundReview>>? _reviews;
  Future<({List<MatchListItem> matches, List<(String, int)> tournaments})>? _matches;
  Future<GroundInsights>? _insights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await context.sync.social.ground(widget.groundId, lat: widget.lat, lng: widget.lng);
      if (mounted) setState(() => _g = g);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _openTab(String t) {
    final social = context.sync.social;
    setState(() {
      _tab = t;
      if (t == 'reviews') _reviews ??= social.groundReviews(widget.groundId);
      if (t == 'matches' || t == 'tournaments') _matches ??= social.groundMatches(widget.groundId);
      if (t == 'insights') _insights ??= social.groundInsights(widget.groundId);
    });
  }

  Future<void> _addPhoto() async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_needed'));
      await loginAsPlayer(context);
      if (!sync.loggedIn || !mounted) return;
    }
    final b64 = await pickGroundPhoto(context);
    if (b64 == null || !mounted) return;
    try {
      await sync.social.addGroundPhoto(widget.groundId, b64);
      await _load();
      if (mounted) _snack(context, context.tr('photo_added'));
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  Future<void> _review() async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_needed'));
      await loginAsPlayer(context);
      if (!sync.loggedIn || !mounted) return;
    }
    var stars = 0;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(ctx.tr('rate_ground')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Stars(value: stars.toDouble(), size: 30, onChanged: (v) => set(() => stars = v)),
            const SizedBox(height: Space.m),
            TextField(controller: ctrl, maxLines: 3, maxLength: 600, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: ctx.tr('comment_optional'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            TextButton(onPressed: stars == 0 ? null : () => Navigator.pop(ctx, true), child: Text(ctx.tr('submit_rating'))),
          ],
        ),
      ),
    );
    final body = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    try {
      await sync.social.reviewGround(widget.groundId, stars, body);
      setState(() => _reviews = sync.social.groundReviews(widget.groundId));
      await _load();
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final g = _g;
    if (g == null) {
      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(backgroundColor: p.bg),
        body: _error == null ? const LoadingList(count: 2) : OnlineError(error: _error!, onRetry: _load),
      );
    }
    final photos = g.photoIds;
    return Scaffold(
      backgroundColor: p.bg,
      body: RefreshIndicator(
        color: p.goldText,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
          Stack(children: [
            SizedBox(
              height: 230,
              child: photos.isEmpty
                  ? GroundPhoto(groundId: g.id, height: 230)
                  : PageView(
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [for (final ph in photos) GroundPhoto(groundId: g.id, photoId: ph, height: 230)],
                    ),
            ),
            Positioned(
              left: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: _RoundBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onTap: () => Navigator.maybePop(context)),
            ),
            Positioned(
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: Row(children: [
                if (g.mine) ...[
                  _RoundBtn(
                    icon: Icons.edit_outlined,
                    tooltip: context.tr('edit'),
                    onTap: () async {
                      final r = await Navigator.push<Ground>(context, MaterialPageRoute(builder: (_) => RegisterGroundScreen(edit: g)));
                      if (r != null) _load();
                    },
                  ),
                  const SizedBox(width: Space.s),
                ],
                _RoundBtn(
                  icon: Icons.share_rounded,
                  tooltip: context.tr('share'),
                  onTap: () => SharePlus.instance.share(ShareParams(text: '🏏 ${g.name}\n${g.address}\n${feeText(context, g)}\n${mapsLink(g)}')),
                ),
              ]),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < photos.length; i++)
                    Container(
                      width: i == _page ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(color: i == _page ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(9)),
                    ),
                ]),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(g.name, style: Tx.title(p.text).copyWith(fontSize: 21)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (g.rating != null) Tag('★ ${g.rating!.toStringAsFixed(1)}', color: p.win),
                Text(
                  [
                    g.reviews == 0 ? context.tr('no_reviews_yet') : context.tr('reviews_n', {'n': g.reviews}),
                    if (g.km != null) '🚗 ${g.km} km',
                    if (g.pitches.isNotEmpty) context.tr('pitch_${g.pitches.first}'),
                  ].join(' · '),
                  style: Tx.small(p.text2, w: FontWeight.w600),
                ),
              ]),
              const SizedBox(height: Space.m),
              Row(children: [
                if (g.phone.isNotEmpty) ...[
                  Expanded(child: GoldButton(label: context.tr('call_to_book'), icon: Icons.call_rounded, height: 46, onPressed: () => openLink(context, 'tel:${g.phone.replaceAll(' ', '')}'))),
                  const SizedBox(width: Space.s),
                ],
                Expanded(child: OutlineBtn(label: context.tr('google_maps'), icon: Icons.map_outlined, height: 46, onPressed: () => openLink(context, mapsLink(g)))),
              ]),
              if (g.fromMap) ...[
                const SizedBox(height: Space.m),
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Corners.card), border: Border.all(color: p.gold.withValues(alpha: 0.4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('🗺 ${context.tr('map_ground_note')}', style: Tx.body(p.text, w: FontWeight.w600)),
                const SizedBox(height: Space.s),
                GoldButton(
                  label: context.tr('add_details'),
                  icon: Icons.edit_outlined,
                  height: 44,
                  onPressed: () async {
                    final r = await Navigator.push<Ground>(context, MaterialPageRoute(builder: (_) => RegisterGroundScreen(edit: g)));
                    if (r != null) _load();
                  },
                ),
              ]),
            ),
          ],
            ]),
          ),
          const SizedBox(height: Space.m),
          SizedBox(
            height: 46,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.edge), child: Row(children: [
              for (final t in _tabs)
                InkWell(
                  onTap: () => _openTab(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    margin: const EdgeInsets.only(right: 18),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == t ? p.gold : Colors.transparent, width: 2))),
                    alignment: Alignment.center,
                    child: Text(context.tr('gtab_$t'), style: Tx.body(_tab == t ? p.text : p.text2, w: FontWeight.w700)),
                  ),
                ),
            ])),
          ),
          Divider(height: 1, color: p.line),
          Padding(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0), child: _body(context, g)),
        ]),
      ),
    );
  }

  Widget _label(BuildContext context, String k) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Text(context.tr(k).toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 0.4)),
    );
  }

  Widget _kv(BuildContext context, String label, String value, String sub, {Color? color}) {
    final p = Palette.of(context);
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Tx.score(24, color ?? p.text, w: FontWeight.w800))),
          if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, Ground g) {
    final p = Palette.of(context);
    switch (_tab) {
      case 'about':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _kv(context, context.tr('fee'), feeText(context, g), context.tr('per_match'), color: p.goldText),
            const SizedBox(width: Space.s),
            _kv(context, context.tr('boundary'), g.boundaryMin == 0 ? '-' : '${g.boundaryMin}–${g.boundaryMax} m', context.tr('shortest_longest')),
          ]),
          if (g.pitches.isNotEmpty) ...[
            _label(context, 'pitch_type'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final x in g.pitches) Tag(context.tr('pitch_$x'))]),
          ],
          if (g.facilities.isNotEmpty) ...[
            _label(context, 'facilities'),
            Wrap(spacing: 14, runSpacing: 8, children: [
              for (final x in g.facilities) Text('${facilityIcons[x] ?? '•'} ${context.tr('fac_$x')}', style: Tx.body(p.text, w: FontWeight.w600)),
            ]),
          ],
          if (g.address.isNotEmpty) ...[_label(context, 'address'), Text([g.address, g.city].where((x) => x.isNotEmpty).join(', '), style: Tx.body(p.text2))],
          if (g.timings.isNotEmpty) ...[_label(context, 'timings'), Text(g.timings, style: Tx.body(p.text2))],
          if (g.phone2.isNotEmpty) ...[
            _label(context, 'other_number'),
            InkWell(onTap: () => openLink(context, 'tel:${g.phone2.replaceAll(' ', '')}'), child: Text('📞 ${g.phone2}', style: Tx.body(p.goldText, w: FontWeight.w700))),
          ],
        ]);
      case 'photos':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlineBtn(label: context.tr('add_photo'), icon: Icons.add_a_photo_outlined, height: 44, onPressed: _addPhoto),
          const SizedBox(height: Space.m),
          if (g.photoIds.isEmpty)
            Text(context.tr('no_photos_yet'), style: Tx.small(p.text2))
          else
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - Space.s) / 2;
              return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final ph in g.photoIds) ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: w, child: GroundPhoto(groundId: g.id, photoId: ph, height: w))),
              ]);
            }),
        ]);
      case 'reviews':
        return FutureBuilder<List<GroundReview>>(
          future: _reviews,
          builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlineBtn(label: context.tr('rate_ground'), icon: Icons.star_outline_rounded, height: 44, onPressed: _review),
            const SizedBox(height: Space.m),
            if (snap.connectionState != ConnectionState.done)
              const LoadingList(count: 1)
            else if (snap.hasError)
              OnlineError(error: snap.error!, onRetry: () => setState(() => _reviews = context.sync.social.groundReviews(g.id)))
            else if (snap.data!.isEmpty)
              Text(context.tr('no_reviews_yet'), style: Tx.small(p.text2))
            else
              for (final r in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800))),
                        Stars(value: r.stars.toDouble(), size: 14),
                      ]),
                      Text(agoText(context, r.created), style: Tx.label(p.text2)),
                      if (r.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.body, style: Tx.body(p.text))),
                    ]),
                  ),
                ),
          ]),
        );
      case 'matches':
      case 'tournaments':
        return FutureBuilder(
          future: _matches,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingList(count: 2);
            if (snap.hasError) return OnlineError(error: snap.error!, onRetry: () => setState(() => _matches = context.sync.social.groundMatches(g.id)));
            final d = snap.data!;
            if (_tab == 'matches') {
              if (d.matches.isEmpty) return Text(context.tr('no_ground_matches'), style: Tx.small(p.text2));
              return Column(children: [
                for (final m in d.matches) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: OnlineMatchCard(m: m, onTap: () => openFollowed(context, m.id))),
              ]);
            }
            if (d.tournaments.isEmpty) return Text(context.tr('no_ground_tournaments'), style: Tx.small(p.text2));
            return Column(children: [
              for (final t in d.tournaments)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: AppCard(
                    child: Row(children: [
                      Icon(Icons.emoji_events_rounded, color: p.goldText),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(t.$1, style: Tx.body(p.text, w: FontWeight.w800))),
                      Text(context.tr('matches_n', {'n': t.$2}), style: Tx.small(p.text2)),
                    ]),
                  ),
                ),
            ]);
          },
        );
      default:
        return FutureBuilder<GroundInsights>(
          future: _insights,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingList(count: 2);
            if (snap.hasError) return OnlineError(error: snap.error!, onRetry: () => setState(() => _insights = context.sync.social.groundInsights(g.id)));
            final s = snap.data!;
            if (s.matches == 0) return Text(context.tr('insights_empty'), style: Tx.small(p.text2));
            const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            final maxDay = s.days.fold<int>(1, (a, b) => b > a ? b : a);
            final best = s.days.indexOf(maxDay);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _kv(context, context.tr('matches_played'), '${s.matches}', ''),
                const SizedBox(width: Space.s),
                _kv(context, context.tr('avg_first_innings'), s.avgFirst == null ? '-' : '${s.avgFirst}', ''),
              ]),
              const SizedBox(height: Space.s),
              Row(children: [
                _kv(context, context.tr('highest_total'), '${s.highest?['score'] ?? '-'}', '${s.highest?['team'] ?? ''}'),
                const SizedBox(width: Space.s),
                _kv(context, context.tr('lowest_total'), '${s.lowest?['score'] ?? '-'}', '${s.lowest?['team'] ?? ''}'),
              ]),
              if (s.batFirstWinPct != null) ...[
                const SizedBox(height: Space.s),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.tr('who_wins_here'), style: Tx.body(p.text, w: FontWeight.w800)),
                    const SizedBox(height: Space.s),
                    _PctBar(label: context.tr('bat_first'), pct: s.batFirstWinPct!, color: p.gold),
                    _PctBar(label: context.tr('chasing'), pct: 100 - s.batFirstWinPct!, color: const Color(0xFF5B9BFF)),
                  ]),
                ),
              ],
              if (s.topRuns.isNotEmpty || s.topWickets.isNotEmpty) ...[
                const SizedBox(height: Space.s),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.tr('top_players_here'), style: Tx.body(p.text, w: FontWeight.w800)),
                    if (s.topRuns.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Text('🏏 ${s.topRuns.first.$1} · ${context.tr('most_runs_n', {'n': s.topRuns.first.$2})}', style: Tx.small(p.text, w: FontWeight.w700)),
                      ),
                    if (s.topWickets.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Text('🎯 ${s.topWickets.first.$1} · ${context.tr('most_wickets_n', {'n': s.topWickets.first.$2})}', style: Tx.small(p.text, w: FontWeight.w700)),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: Space.s),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(context.tr('busiest_days'), style: Tx.body(p.text, w: FontWeight.w800)),
                  const SizedBox(height: Space.m),
                  SizedBox(
                    height: 90,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Container(
                                height: 4 + 56 * s.days[i] / maxDay,
                                decoration: BoxDecoration(color: i == best ? p.gold : p.raised, borderRadius: BorderRadius.circular(5)),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(fit: BoxFit.scaleDown, child: Text(dayNames[i], style: Tx.label(p.text2))),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ]);
          },
        );
    }
  }
}

class _PctBar extends StatelessWidget {
  const _PctBar({required this.label, required this.pct, required this.color});
  final String label;
  final int pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2, w: FontWeight.w700))),
        Expanded(
          flex: 3,
          child: ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: p.raised, color: color)),
        ),
        const SizedBox(width: 8),
        Text('$pct%', style: Tx.small(p.text, w: FontWeight.w800)),
      ]),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x99070F1E),
        borderRadius: BorderRadius.circular(12),
        child: IconButton(tooltip: tooltip, icon: Icon(icon, color: Colors.white), onPressed: onTap),
      );
}
