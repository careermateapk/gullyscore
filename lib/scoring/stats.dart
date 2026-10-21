// Player career stats, tournament points table and leaderboards.
import 'engine.dart';

/// A finished or live match, ready for stats.
class StatMatch {
  StatMatch({required this.id, required this.teamIds, required this.state});
  final String id;
  final List<String> teamIds; // [teamA id, teamB id]
  final MatchState state;
}

class PlayerStats {
  int matches = 0;
  // batting
  int innings = 0;
  int runs = 0;
  int balls = 0;
  int notOuts = 0;
  int fours = 0;
  int sixes = 0;
  int highest = 0;
  bool highestNotOut = false;
  int fifties = 0;
  int hundreds = 0;
  int ducks = 0;
  // bowling
  int bowlInnings = 0;
  int ballsBowled = 0;
  int runsConceded = 0;
  int wickets = 0;
  int maidens = 0;
  int bestWkts = 0;
  int bestRuns = 0;
  int threeW = 0;
  int fiveW = 0;
  // fielding
  int catches = 0;
  int runOuts = 0;
  int stumpings = 0;

  int get outs => innings - notOuts;
  double get average => outs == 0 ? runs.toDouble() : runs / outs;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  double get economy => ballsBowled == 0 ? 0 : runsConceded * 6 / ballsBowled;
  double? get bowlAverage => wickets == 0 ? null : runsConceded / wickets;
  String get best => bowlInnings == 0 ? '-' : '$bestWkts/$bestRuns';
  String get highestText => innings == 0 ? '-' : '$highest${highestNotOut ? '*' : ''}';
}

PlayerStats playerStats(String playerId, Iterable<StatMatch> matches) {
  final s = PlayerStats();
  for (final m in matches) {
    final st = m.state;
    if (!st.setup.playersA.contains(playerId) && !st.setup.playersB.contains(playerId)) continue;
    s.matches++;
    for (final inn in st.innings) {
      final bat = inn.batters[playerId];
      if (bat != null) {
        s.innings++;
        s.runs += bat.runs;
        s.balls += bat.balls;
        s.fours += bat.fours;
        s.sixes += bat.sixes;
        if (!bat.out) s.notOuts++;
        if (bat.runs > s.highest || (bat.runs == s.highest && !bat.out)) {
          s.highest = bat.runs;
          s.highestNotOut = !bat.out;
        }
        if (bat.runs >= 100) {
          s.hundreds++;
        } else if (bat.runs >= 50) {
          s.fifties++;
        }
        if (bat.out && bat.runs == 0) s.ducks++;
      }
      final bowl = inn.bowlers[playerId];
      if (bowl != null && (bowl.balls > 0 || bowl.runs > 0)) {
        s.bowlInnings++;
        s.ballsBowled += bowl.balls;
        s.runsConceded += bowl.runs;
        s.wickets += bowl.wickets;
        s.maidens += bowl.maidens;
        if (bowl.wickets > s.bestWkts || (bowl.wickets == s.bestWkts && (s.bowlInnings == 1 || bowl.runs < s.bestRuns))) {
          s.bestWkts = bowl.wickets;
          s.bestRuns = bowl.runs;
        }
        if (bowl.wickets >= 5) {
          s.fiveW++;
        } else if (bowl.wickets >= 3) {
          s.threeW++;
        }
      }
      for (final b in inn.batters.values) {
        if (b.fielderId != playerId) continue;
        if (b.outKind == OutKind.caught) s.catches++;
        if (b.outKind == OutKind.runOut) s.runOuts++;
        if (b.outKind == OutKind.stumped) s.stumpings++;
      }
    }
  }
  return s;
}

class PointsRow {
  PointsRow(this.teamId);
  final String teamId;
  int played = 0;
  int won = 0;
  int lost = 0;
  int tied = 0;
  int noResult = 0;
  int runsFor = 0;
  int ballsFaced = 0;
  int runsAgainst = 0;
  int ballsBowled = 0;

  int get points => won * 2 + tied + noResult;

  double get nrr {
    if (ballsFaced == 0 || ballsBowled == 0) return 0;
    return runsFor * 6 / ballsFaced - runsAgainst * 6 / ballsBowled;
  }
}

/// Points table: 2 for a win, 1 for a tie or no result. NRR counts an
/// all-out innings as the full quota of overs.
List<PointsRow> pointsTable(List<String> teamIds, Iterable<StatMatch> matches) {
  final rows = {for (final t in teamIds) t: PointsRow(t)};
  for (final m in matches) {
    final st = m.state;
    final r = st.result;
    if (r == null) continue;
    final a = rows[m.teamIds[0]];
    final b = rows[m.teamIds[1]];
    if (a == null || b == null) continue;
    final teamRow = [a, b];
    a.played++;
    b.played++;
    if (r.noResult) {
      a.noResult++;
      b.noResult++;
      continue;
    }
    if (r.tie) {
      a.tied++;
      b.tied++;
    } else {
      teamRow[r.winner!].won++;
      teamRow[1 - r.winner!].lost++;
    }
    for (final inn in st.innings) {
      final bat = teamRow[inn.battingTeam];
      final bowl = teamRow[1 - inn.battingTeam];
      final balls = inn.allOut ? st.setup.overs * 6 : inn.legalBalls;
      bat.runsFor += inn.runs;
      bat.ballsFaced += balls;
      bowl.runsAgainst += inn.runs;
      bowl.ballsBowled += balls;
    }
  }
  final list = rows.values.toList();
  list.sort((x, y) {
    final p = y.points.compareTo(x.points);
    if (p != 0) return p;
    return y.nrr.compareTo(x.nrr);
  });
  return list;
}

class Leader {
  Leader(this.playerId, this.value, this.detail);
  final String playerId;
  final int value;
  final String detail; // balls faced (runs list) or runs given (wickets list)
}

List<Leader> topRunScorers(Iterable<StatMatch> matches, {int limit = 10}) {
  final runs = <String, int>{};
  final balls = <String, int>{};
  for (final m in matches) {
    for (final inn in m.state.innings) {
      for (final b in inn.batters.values) {
        runs[b.id] = (runs[b.id] ?? 0) + b.runs;
        balls[b.id] = (balls[b.id] ?? 0) + b.balls;
      }
    }
  }
  final list = runs.entries
      .where((e) => e.value > 0)
      .map((e) => Leader(e.key, e.value, '${balls[e.key]}'))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return list.take(limit).toList();
}

List<Leader> topWicketTakers(Iterable<StatMatch> matches, {int limit = 10}) {
  final wkts = <String, int>{};
  final runs = <String, int>{};
  for (final m in matches) {
    for (final inn in m.state.innings) {
      for (final b in inn.bowlers.values) {
        wkts[b.id] = (wkts[b.id] ?? 0) + b.wickets;
        runs[b.id] = (runs[b.id] ?? 0) + b.runs;
      }
    }
  }
  final list = wkts.entries
      .where((e) => e.value > 0)
      .map((e) => Leader(e.key, e.value, '${runs[e.key]}'))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return list.take(limit).toList();
}

/// Round-robin fixtures (every team plays every other team once).
List<List<String>> roundRobin(List<String> teams) {
  final t = List<String?>.of(teams);
  if (t.length.isOdd) t.add(null);
  final n = t.length;
  final out = <List<String>>[];
  for (var round = 0; round < n - 1; round++) {
    for (var i = 0; i < n ~/ 2; i++) {
      final a = t[i];
      final b = t[n - 1 - i];
      if (a != null && b != null) out.add([a, b]);
    }
    // rotate all but the first
    final last = t.removeLast();
    t.insert(1, last);
  }
  return out;
}
