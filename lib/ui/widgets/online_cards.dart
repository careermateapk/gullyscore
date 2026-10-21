// Cards for matches that come from the online service (feed, My Cricket,
// team pages), plus small helpers for dates and loading/error states.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/models.dart';
import 'common.dart';

/// Same colour for a team name everywhere (online teams carry no colour).
Color teamColorFor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return Palette.team(h);
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String timeText(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today", "Tomorrow" or "Thu 22 Oct".
String dayText(BuildContext context, DateTime t) {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = d.difference(d0).inDays;
  if (diff == 0) return context.tr('today');
  if (diff == 1) return context.tr('tomorrow');
  if (diff == -1) return context.tr('yesterday');
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

String whenText(BuildContext context, DateTime t) => '${dayText(context, t)} · ${timeText(t)}';

/// A score line from the summary for one team, e.g. ("133/6", "(20)").
(String, String)? _score(MatchListItem m, String teamName) {
  for (final i in (m.summary['innings'] as List? ?? const [])) {
    if (i is Map && i['team'] == teamName) return ('${i['score']}', '(${i['overs']})');
  }
  return null;
}

class OnlineMatchCard extends StatelessWidget {
  const OnlineMatchCard({super.key, required this.m, required this.onTap, this.showMe = false});
  final MatchListItem m;
  final VoidCallback onTap;
  final bool showMe;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = m.teamA.name.isNotEmpty ? m.teamA.name : '${m.summary['title'] ?? ''}'.split(' vs ').first;
    final b = m.teamB.name.isNotEmpty ? m.teamB.name : '${m.summary['title'] ?? ''}'.split(' vs ').last.split(' · ').first;
    final innings = (m.summary['innings'] as List? ?? const []);
    final batting = innings.isEmpty ? null : (innings.last as Map)['team'];
    Widget row(String name) {
      final s = m.upcoming ? null : _score(m, name);
      final bold = m.live ? batting == name : (m.winner.isNotEmpty && (m.winner == m.teamA.id ? a : b) == name);
      return Row(children: [
        Crest(color: teamColorFor(name), text: initials(name), size: 24),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(bold ? p.text : p.text2, w: bold ? FontWeight.w800 : FontWeight.w700)),
        ),
        if (s != null)
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(s.$1, style: Tx.score(bold ? 22 : 19, bold ? p.text : p.text2, w: FontWeight.w800)),
                const SizedBox(width: 4),
                Text(s.$2, style: Tx.score(14, p.text2, w: FontWeight.w700)),
              ]),
            ),
          ),
      ]);
    }

    final top = <Widget>[
      if (m.live)
        LiveBadge(label: context.tr('live'))
      else if (m.upcoming)
        Tag(m.scheduled == null ? context.tr('upcoming') : whenText(context, m.scheduled!))
      else
        Tag(context.tr('result'), color: p.win),
      const SizedBox(width: Space.s),
      Expanded(
        child: Text(
          [if (m.ground.isNotEmpty) m.ground, if (m.title.isNotEmpty) m.title].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: Tx.label(p.text2, w: FontWeight.w700),
        ),
      ),
    ];
    final me = m.me;
    final meText = me == null ? null : _meText(context, me);
    return AppCard(
      onTap: onTap,
      borderColor: m.live ? p.heroLine : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: top),
        const SizedBox(height: Space.s + 2),
        row(a),
        const SizedBox(height: 6),
        row(b),
        if (!m.upcoming && m.headline.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text(m.headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(m.live ? p.goldText : p.win, w: FontWeight.w800)),
        ],
        if (showMe && meText != null) ...[
          const SizedBox(height: Space.s),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Text(meText, style: Tx.small(p.text, w: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }
}

/// "You: 58* (31) · 2/18 (4.0)"
String? _meText(BuildContext context, Map<String, dynamic> me) {
  final parts = <String>[];
  if (me['r'] != null) parts.add('${me['r']}${me['notOut'] == true ? '*' : ''} (${me['b']})');
  if (me['w'] != null) parts.add('${me['w']}/${me['rc']} (${me['o']})');
  if (parts.isEmpty) return null;
  return '${context.tr('you')}: ${parts.join(' · ')}';
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            const Padding(padding: EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s), child: SkeletonBox(height: 120, radius: Corners.card)),
        ]),
      );
}

/// Friendly message when a call to the service fails.
String onlineError(BuildContext context, Object e) {
  if (e is CloudError && e.offline) return context.tr('needs_internet');
  if (e is CloudError && e.status == 401) return context.tr('login_needed');
  if (e is CloudError && e.status == 429) return context.tr('too_many_posts');
  return context.tr('online_failed');
}

class OnlineError extends StatelessWidget {
  const OnlineError({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.edge),
      child: AppCard(
        onTap: onRetry,
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, color: p.text2),
          const SizedBox(width: Space.m),
          Expanded(child: Text(onlineError(context, error), style: Tx.small(p.text2))),
          Text(context.tr('try_again'), style: Tx.small(p.goldText, w: FontWeight.w800)),
        ]),
      ),
    );
  }
}
