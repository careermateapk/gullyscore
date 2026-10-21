// Badges a player earns from their matches (from My Cricket data).
import '../data/cloud.dart';

class BadgeDef {
  const BadgeDef(this.id, this.emoji, this.color);
  final String id; // text keys: badge_<id> and badge_<id>_how
  final String emoji;
  final int color; // ARGB of the medal
}

const badgeDefs = <BadgeDef>[
  BadgeDef('debut', '🎽', 0xFF3B82F6),
  BadgeDef('fifty', '🏏', 0xFF3B82F6),
  BadgeDef('century', '💯', 0xFFFFC94A),
  BadgeDef('six_hitter', '💥', 0xFFFF8A3D),
  BadgeDef('three_wickets', '🔥', 0xFFEF4444),
  BadgeDef('five_wickets', '🖐️', 0xFFA855F7),
  BadgeDef('hat_trick', '🎩', 0xFFA855F7),
  BadgeDef('safe_hands', '🧤', 0xFF2BD38A),
  BadgeDef('ten_matches', '🔟', 0xFF5B9BFF),
  BadgeDef('fifty_matches', '🏟️', 0xFF5B9BFF),
  BadgeDef('thousand_runs', '🏆', 0xFFFFC94A),
  BadgeDef('fifty_wickets', '⚡', 0xFFFF8A3D),
];

class EarnedBadge {
  EarnedBadge(this.def, this.match, this.detail);
  final BadgeDef def;
  final MatchListItem? match; // the match where it was earned
  final String detail; // e.g. "104* (58)"
}

int _i(Object? v) => v is num ? v.toInt() : 0;

/// Badges earned, oldest first. Matches must carry `me` lines.
List<EarnedBadge> earnedBadges(List<MatchListItem> matches) {
  final played = matches.where((m) => !m.upcoming && m.me != null).toList()..sort((a, b) => a.updated.compareTo(b.updated));
  final got = <String, EarnedBadge>{};
  var count = 0, runs = 0, wkts = 0;
  void give(String id, MatchListItem m, String detail) {
    if (got.containsKey(id)) return;
    got[id] = EarnedBadge(badgeDefs.firstWhere((d) => d.id == id), m, detail);
  }

  for (final m in played) {
    final me = m.me!;
    count++;
    final r = _i(me['r']), b = _i(me['b']), w = _i(me['w']);
    runs += r;
    wkts += w;
    final bat = me['r'] == null ? '' : '$r${me['notOut'] == true ? '*' : ''} ($b)';
    final bowl = me['w'] == null ? '' : '$w/${_i(me['rc'])}';
    if (count == 1) give('debut', m, '');
    if (r >= 50) give('fifty', m, bat);
    if (r >= 100) give('century', m, bat);
    if (_i(me['6s']) >= 5) give('six_hitter', m, '${me['6s']} × 6');
    if (w >= 3) give('three_wickets', m, bowl);
    if (w >= 5) give('five_wickets', m, bowl);
    if (me['hat'] == true) give('hat_trick', m, bowl);
    if (_i(me['ct']) >= 3) give('safe_hands', m, '${me['ct']} ct');
    if (count >= 10) give('ten_matches', m, '$count');
    if (count >= 50) give('fifty_matches', m, '$count');
    if (runs >= 1000) give('thousand_runs', m, '$runs');
    if (wkts >= 50) give('fifty_wickets', m, '$wkts');
  }
  return got.values.toList();
}
