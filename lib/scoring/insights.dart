// Fun numbers built from ball-by-ball data: head-to-head, levels (XP),
// Season Wrapped and the Match Story. No Flutter imports, so it is unit tested.
import 'dart:math' as math;

import 'engine.dart';
import 'stats.dart';
import 'tournament.dart';

// ---------------------------------------------------------------- head to head

class HeadToHead {
  int balls = 0; // legal balls faced from this bowler
  int runs = 0; // off the bat
  int outs = 0; // dismissals credited to the bowler
  int dots = 0;
  int fours = 0;
  int sixes = 0;
  final Set<String> matches = {};
  final Map<String, int> howOut = {};
  final List<String> sequence = []; // "•", "1", "4", "6", "W" … oldest first

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  double get economy => balls == 0 ? 0 : runs * 6 / balls;
  int get dotPercent => balls == 0 ? 0 : (dots * 100 / balls).round();

  /// Who is ahead: 1 = batter, -1 = bowler, 0 = even (or too few balls).
  int get edge {
    if (balls < 6) return 0;
    if (outs == 0) return strikeRate >= 100 ? 1 : 0;
    final ballsPerOut = balls / outs;
    if (ballsPerOut <= 12 || strikeRate < 90) return -1;
    if (ballsPerOut >= 24 && strikeRate >= 120) return 1;
    return 0;
  }
}

HeadToHead headToHead(String batter, String bowler, Iterable<StatMatch> matches) {
  final h = HeadToHead();
  for (final m in matches) {
    for (final inn in m.state.innings) {
      for (final b in inn.balls) {
        if (b.striker != batter || b.bowler != bowler) continue;
        if (b.kind == BallKind.wide) continue; // not faced
        h.matches.add(m.id);
        final out = b.isWicket && b.outPlayer == batter && OutKind.creditsBowler(b.outKind!);
        if (b.legal) h.balls++;
        final bat = (b.kind == BallKind.normal || b.kind == BallKind.noBall) ? b.runs : 0;
        h.runs += bat;
        if (b.isFour) h.fours++;
        if (b.isSix) h.sixes++;
        if (out) {
          h.outs++;
          h.howOut[b.outKind!] = (h.howOut[b.outKind!] ?? 0) + 1;
          h.sequence.add('W');
        } else if (b.legal && bat == 0) {
          h.dots++;
          h.sequence.add('•');
        } else {
          h.sequence.add('$bat');
        }
      }
    }
  }
  return h;
}

/// Opponents this player has faced (as batter) or bowled to, most balls first.
List<(String, int)> rivals(String playerId, Iterable<StatMatch> matches, {required bool asBatter}) {
  final count = <String, int>{};
  for (final m in matches) {
    for (final inn in m.state.innings) {
      for (final b in inn.balls) {
        if (!b.legal) continue;
        if (asBatter && b.striker == playerId && b.bowler.isNotEmpty) count[b.bowler] = (count[b.bowler] ?? 0) + 1;
        if (!asBatter && b.bowler == playerId && b.striker.isNotEmpty) count[b.striker] = (count[b.striker] ?? 0) + 1;
      }
    }
  }
  return [for (final e in count.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
}

// ---------------------------------------------------------------- levels (XP)

class XpRule {
  const XpRule(this.key, this.xp);
  final String key; // strings key, e.g. "xp_run"
  final int xp;
}

const xpRules = [
  XpRule('xp_match', 10),
  XpRule('xp_run', 1),
  XpRule('xp_wicket', 20),
  XpRule('xp_catch', 10),
  XpRule('xp_fifty', 25),
  XpRule('xp_hundred', 75),
  XpRule('xp_potm', 100),
];

/// Tiers, each with three steps (I, II, III) except the last.
const levelTiers = ['rookie', 'club', 'pro', 'star', 'legend'];
const levelEmoji = ['🌱', '🏏', '⚡', '⭐', '👑'];

class Level {
  Level(this.xp);
  final int xp;

  /// XP needed to reach level n (n = 0 is the start). Grows gently.
  static int needed(int n) => n <= 0 ? 0 : (150 * n + 25 * n * n);

  /// 13 steps: Rookie I–III, Club I–III, Pro I–III, Star I–III, Legend.
  static const maxLevel = 12;

  int get number {
    var n = 0;
    while (n < maxLevel && xp >= needed(n + 1)) {
      n++;
    }
    return n;
  }

  int get tier => math.min(number ~/ 3, levelTiers.length - 1);
  int get step => number >= maxLevel ? 0 : number % 3 + 1; // 1..3, 0 for Legend
  bool get isMax => number >= maxLevel;
  int get nextAt => needed(number + 1);
  int get thisAt => needed(number);
  double get progress => isMax ? 1 : ((xp - thisAt) / (nextAt - thisAt)).clamp(0, 1).toDouble();
  int get toNext => isMax ? 0 : nextAt - xp;
  int get nextTier => math.min((number + 1) ~/ 3, levelTiers.length - 1);
}

int xpOf(PlayerStats s, {int potm = 0}) =>
    s.matches * 10 + s.runs + s.wickets * 20 + (s.catches + s.runOuts + s.stumpings) * 10 + s.fifties * 25 + s.hundreds * 75 + potm * 100;

int potmCount(String playerId, Iterable<StatMatch> matches) => matches.where((m) => playerOfMatch(m.state) == playerId).length;

// ---------------------------------------------------------------- season wrapped

class Wrapped {
  int matches = 0;
  int runs = 0;
  int balls = 0;
  int wickets = 0;
  int sixes = 0;
  int fours = 0;
  int catches = 0;
  int potm = 0;
  int bestRuns = -1;
  bool bestNotOut = false;
  String? bestAgainst; // team id
  String? favouriteGround;
  int favouriteGroundMatches = 0;
  int? bestWeekday; // 1 Monday … 7 Sunday
  double bestWeekdayAvg = 0;
  String? nemesis; // bowler who got this player out most
  int nemesisOuts = 0;
  String? bunny; // batter this player got out most
  int bunnyOuts = 0;
  String? partner;
  int partnerRuns = 0;
  int deathRuns = 0; // runs in the last 5 overs
  int powerplayRuns = 0; // first 6 overs
  int rank = 0; // by runs among players on this phone
  int rankOf = 0;
  String personality = 'all_round'; // strings key suffix: persona_<x>

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  int get deathShare => runs == 0 ? 0 : (deathRuns * 100 / runs).round();
}

class WrappedMatch {
  WrappedMatch(this.stat, this.date, this.ground, {this.opponentOf});
  final StatMatch stat;
  final DateTime date;
  final String ground;
  final String Function(String playerId)? opponentOf; // team id the player played against
}

Wrapped seasonWrapped(String id, List<WrappedMatch> list, {Map<String, int> runsByPlayer = const {}}) {
  final w = Wrapped();
  final grounds = <String, int>{};
  final dayRuns = <int, int>{};
  final dayInns = <int, int>{};
  final outBy = <String, int>{};
  final gotOut = <String, int>{};
  final partners = <String, int>{};
  for (final wm in list) {
    final st = wm.stat.state;
    if (!st.setup.playersA.contains(id) && !st.setup.playersB.contains(id)) continue;
    w.matches++;
    if (wm.ground.isNotEmpty) grounds[wm.ground] = (grounds[wm.ground] ?? 0) + 1;
    if (playerOfMatch(st) == id) w.potm++;
    for (final inn in st.innings) {
      final bat = inn.batters[id];
      if (bat != null) {
        w.runs += bat.runs;
        w.balls += bat.balls;
        w.sixes += bat.sixes;
        w.fours += bat.fours;
        final d = wm.date.weekday;
        dayRuns[d] = (dayRuns[d] ?? 0) + bat.runs;
        dayInns[d] = (dayInns[d] ?? 0) + 1;
        if (bat.runs > w.bestRuns || (bat.runs == w.bestRuns && !bat.out)) {
          w.bestRuns = bat.runs;
          w.bestNotOut = !bat.out;
          w.bestAgainst = wm.opponentOf?.call(id);
        }
        if (bat.out && bat.bowlerId != null && bat.outKind != null && OutKind.creditsBowler(bat.outKind!)) {
          outBy[bat.bowlerId!] = (outBy[bat.bowlerId!] ?? 0) + 1;
        }
      }
      final bowl = inn.bowlers[id];
      if (bowl != null) w.wickets += bowl.wickets;
      for (final b in inn.batters.values) {
        if (b.fielderId == id && (b.outKind == OutKind.caught || b.outKind == OutKind.stumped || b.outKind == OutKind.runOut)) w.catches++;
        if (b.out && b.bowlerId == id && b.outKind != null && OutKind.creditsBowler(b.outKind!)) gotOut[b.id] = (gotOut[b.id] ?? 0) + 1;
      }
      for (final pt in inn.partnerships) {
        final other = pt.a == id ? pt.b : (pt.b == id ? pt.a : null);
        if (other != null && other.isNotEmpty) partners[other] = (partners[other] ?? 0) + pt.runs;
      }
      // the partnership still going when the innings stopped
      if ((inn.striker == id || inn.nonStriker == id) && inn.partnershipRuns > 0) {
        final other = inn.striker == id ? inn.nonStriker : inn.striker;
        if (other != null) partners[other] = (partners[other] ?? 0) + inn.partnershipRuns;
      }
      final overs = st.setup.overs;
      for (final b in inn.balls) {
        if (b.striker != id) continue;
        final r = (b.kind == BallKind.normal || b.kind == BallKind.noBall) ? b.runs : 0;
        if (b.over >= overs - 5 && overs > 6) w.deathRuns += r;
        if (b.over < 6 && overs > 6) w.powerplayRuns += r;
      }
    }
  }
  (String, int)? top(Map<String, int> m) {
    if (m.isEmpty) return null;
    final e = m.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (e.key, e.value);
  }

  final g = top(grounds);
  if (g != null) {
    w.favouriteGround = g.$1;
    w.favouriteGroundMatches = g.$2;
  }
  final nem = top(outBy);
  if (nem != null && nem.$2 >= 2) {
    w.nemesis = nem.$1;
    w.nemesisOuts = nem.$2;
  }
  final bun = top(gotOut);
  if (bun != null && bun.$2 >= 2) {
    w.bunny = bun.$1;
    w.bunnyOuts = bun.$2;
  }
  final par = top(partners);
  if (par != null && par.$2 > 0) {
    w.partner = par.$1;
    w.partnerRuns = par.$2;
  }
  for (final d in dayInns.keys) {
    if ((dayInns[d] ?? 0) < 2) continue;
    final avg = (dayRuns[d] ?? 0) / dayInns[d]!;
    if (avg > w.bestWeekdayAvg) {
      w.bestWeekdayAvg = avg;
      w.bestWeekday = d;
    }
  }
  if (runsByPlayer.isNotEmpty) {
    final sorted = runsByPlayer.values.toList()..sort((a, b) => b.compareTo(a));
    w.rank = sorted.indexWhere((r) => r <= w.runs) + 1;
    if (w.rank == 0) w.rank = sorted.length;
    w.rankOf = sorted.length;
  }
  w.personality = _persona(w);
  return w;
}

String _persona(Wrapped w) {
  if (w.matches == 0) return 'new';
  final batting = w.runs >= w.wickets * 20;
  if (w.runs >= 50 && w.deathShare >= 45) return 'finisher';
  if (w.runs >= 50 && w.sixes * 6 >= w.runs * 0.35) return 'six_hitter';
  if (w.runs >= 50 && w.powerplayRuns * 100 >= w.runs * 50) return 'opener';
  if (w.wickets >= 5 && w.runs >= 100) return 'all_round';
  if (!batting && w.wickets >= 3) return 'wicket_taker';
  if (w.catches >= 5) return 'safe_hands';
  if (w.strikeRate > 0 && w.strikeRate < 90 && w.runs >= 50) return 'anchor';
  return 'team_player';
}

// ---------------------------------------------------------------- match story

/// Chance (0–100) the chasing side wins, from runs needed, balls and wickets left.
int chaseWinChance(int need, int ballsLeft, int wicketsLeft) {
  if (need <= 0) return 100;
  if (ballsLeft <= 0 || wicketsLeft <= 0) return 0;
  final resource = math.pow(wicketsLeft / 10, 0.55).toDouble();
  final canScore = ballsLeft / 6 * 8.2 * resource; // runs a side can make with what is left
  final x = (canScore - need) / (6 + need * 0.18);
  return (100 / (1 + math.exp(-x * 1.6))).round().clamp(1, 99);
}

class StoryOver {
  StoryOver(this.innings, this.over, this.balls, this.runs, this.wickets, this.bowler, this.chanceBefore, this.chanceAfter);
  final int innings;
  final int over; // 0-based
  final List<BallLog> balls;
  final int runs;
  final int wickets;
  final String bowler;
  final int? chanceBefore; // chasing side, if second innings
  final int? chanceAfter;
  int get swing => chanceBefore == null ? 0 : (chanceAfter! - chanceBefore!).abs();
}

class MatchStory {
  MatchStory({required this.chase, required this.turning, required this.bestOver, required this.chances});
  final List<int> chances; // chasing side's chance after each over of the chase (starts before ball 1)
  final StoryOver? turning; // biggest swing in the chase, else the over with most wickets
  final StoryOver? bestOver; // most runs in one over
  final bool chase;
}

MatchStory matchStory(MatchState st) {
  final overs = <StoryOver>[];
  final chances = <int>[];
  final players = [st.setup.playersA.length, st.setup.playersB.length];
  for (final inn in st.innings) {
    final byOver = <int, List<BallLog>>{};
    for (final b in inn.balls) {
      byOver.putIfAbsent(b.over, () => []).add(b);
    }
    final chase = inn.number == 1 && st.innings.isNotEmpty;
    final target = st.innings[0].runs + 1;
    final maxW = math.max(1, players[inn.battingTeam] - 1);
    int wl(int w) => ((maxW - w) * 10 / maxW).round();
    var runsBefore = 0, wktsBefore = 0, ballsBefore = 0;
    if (chase) chances.add(chaseWinChance(target, st.setup.overs * 6, wl(0)));
    for (final o in (byOver.keys.toList()..sort())) {
      final balls = byOver[o]!;
      final runs = balls.fold<int>(0, (a, b) => a + b.teamRuns);
      final wk = balls.where((b) => b.isWicket).length;
      final legal = balls.where((b) => b.legal).length;
      int? before, after;
      if (chase) {
        before = chaseWinChance(target - runsBefore, st.setup.overs * 6 - ballsBefore, wl(wktsBefore));
        after = chaseWinChance(target - runsBefore - runs, st.setup.overs * 6 - ballsBefore - legal, wl(wktsBefore + wk));
        chances.add(after);
      }
      overs.add(StoryOver(inn.number, o, balls, runs, wk, balls.first.bowler, before, after));
      runsBefore += runs;
      wktsBefore += wk;
      ballsBefore += legal;
    }
  }
  StoryOver? turning;
  final chaseOvers = overs.where((o) => o.chanceBefore != null && o.swing >= 12).toList();
  if (chaseOvers.isNotEmpty) {
    turning = chaseOvers.reduce((a, b) => b.swing > a.swing ? b : a);
  } else {
    final w = overs.where((o) => o.wickets >= 2).toList();
    if (w.isNotEmpty) turning = w.reduce((a, b) => b.wickets > a.wickets || (b.wickets == a.wickets && b.runs < a.runs) ? b : a);
  }
  final best = overs.isEmpty ? null : overs.reduce((a, b) => b.runs > a.runs ? b : a);
  return MatchStory(chase: chances.isNotEmpty, turning: turning, bestOver: (best?.runs ?? 0) >= 12 ? best : null, chances: chances);
}
