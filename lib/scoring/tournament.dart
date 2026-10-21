// Tournaments: groups, fixtures, knockout brackets and who goes through.
// Pure Dart (no Flutter) so the rules can be unit tested.
import 'engine.dart';
import 'stats.dart';

class TFormat {
  static const league = 'league'; // everyone plays everyone, top teams to knockouts
  static const groups = 'groups'; // groups, then knockouts
  static const knockout = 'knockout'; // straight knockout
}

class Stage {
  static const group = 'group';
  static const league = 'league';
  static const quarter = 'qf';
  static const semi = 'sf';
  static const finalStage = 'final';

  static bool isKnockout(String s) => s == quarter || s == semi || s == finalStage || s.startsWith('r');
}

/// One planned game. Knockout fixtures start with [slotA]/[slotB] such as
/// "G0P1" (group A, 1st), "L2" (league 2nd) or "W:<fixture id>" (winner).
class Fixture {
  Fixture({
    required this.id,
    required this.number,
    required this.stage,
    this.group,
    this.teamA,
    this.teamB,
    this.slotA,
    this.slotB,
    this.matchId,
    this.winnerOverride,
  });

  final String id;
  final int number; // match number shown to people
  final String stage;
  final int? group;
  String? teamA;
  String? teamB;
  final String? slotA;
  final String? slotB;
  String? matchId;
  String? winnerOverride; // organiser's pick after a tie or no result

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': number,
        'stage': stage,
        if (group != null) 'g': group,
        if (teamA != null) 'a': teamA,
        if (teamB != null) 'b': teamB,
        if (slotA != null) 'sa': slotA,
        if (slotB != null) 'sb': slotB,
        if (matchId != null) 'm': matchId,
        if (winnerOverride != null) 'wo': winnerOverride,
      };

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        id: j['id'] as String,
        number: (j['n'] as num?)?.toInt() ?? 0,
        stage: (j['stage'] as String?) ?? Stage.group,
        group: (j['g'] as num?)?.toInt(),
        teamA: j['a'] as String?,
        teamB: j['b'] as String?,
        slotA: j['sa'] as String?,
        slotB: j['sb'] as String?,
        matchId: j['m'] as String?,
        winnerOverride: j['wo'] as String?,
      );
}

class Tournament {
  Tournament({
    required this.id,
    required this.name,
    required this.format,
    required this.overs,
    required this.teamIds,
    required this.groups,
    required this.fixtures,
    required this.createdAt,
    this.category = 'open',
    this.qualifiers = 2,
    this.venue = '',
  });

  final String id;
  String name;
  final String format;
  final int overs;
  final List<String> teamIds;
  final List<List<String>> groups; // empty unless format is groups
  final List<Fixture> fixtures;
  final DateTime createdAt;
  final String category; // open, women, u17, u14
  final int qualifiers; // per group (groups) or in total (league)
  String venue;

  Fixture? fixture(String id) {
    for (final f in fixtures) {
      if (f.id == id) return f;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'format': format,
        'overs': overs,
        'teams': teamIds,
        'groups': groups,
        'fixtures': [for (final f in fixtures) f.toJson()],
        'created': createdAt.toIso8601String(),
        'cat': category,
        'q': qualifiers,
        'venue': venue,
      };

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        format: (j['format'] as String?) ?? TFormat.league,
        overs: (j['overs'] as num?)?.toInt() ?? 10,
        teamIds: [for (final t in (j['teams'] as List? ?? const [])) t as String],
        groups: [
          for (final g in (j['groups'] as List? ?? const [])) [for (final t in (g as List)) t as String]
        ],
        fixtures: [for (final f in (j['fixtures'] as List? ?? const [])) Fixture.fromJson(Map<String, dynamic>.from(f as Map))],
        createdAt: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        category: (j['cat'] as String?) ?? 'open',
        qualifiers: (j['q'] as num?)?.toInt() ?? 2,
        venue: (j['venue'] as String?) ?? '',
      );
}

String groupLetter(int g) => String.fromCharCode(65 + g);

/// Splits teams into [count] groups like dealing cards, so strong seeds spread out.
List<List<String>> makeGroups(List<String> teams, int count) {
  final out = [for (var i = 0; i < count; i++) <String>[]];
  for (var i = 0; i < teams.length; i++) {
    final round = i ~/ count;
    final pos = i % count;
    out[round.isEven ? pos : count - 1 - pos].add(teams[i]);
  }
  return out;
}

/// Standard bracket order for [n] seeds (n a power of two): 1v8, 4v5, 2v7, 3v6 …
List<(int, int)> bracketPairs(int n) {
  var order = [1];
  while (order.length < n) {
    final size = order.length * 2;
    order = [for (final s in order) ...[s, size + 1 - s]];
  }
  return [for (var i = 0; i < order.length; i += 2) (order[i], order[i + 1])];
}

bool isPowerOfTwo(int n) => n >= 2 && (n & (n - 1)) == 0;

String _stageFor(int teamsLeft) => switch (teamsLeft) {
      2 => Stage.finalStage,
      4 => Stage.semi,
      8 => Stage.quarter,
      _ => 'r$teamsLeft',
    };

/// Creates a tournament with all its fixtures.
Tournament createTournament({
  required String id,
  required String name,
  required String format,
  required int overs,
  required List<String> teamIds,
  int groupCount = 2,
  int qualifiers = 2,
  String category = 'open',
  String venue = '',
  DateTime? now,
}) {
  var n = 0;
  String fid() => '$id-f${n + 1}';
  final fixtures = <Fixture>[];
  var groups = <List<String>>[];

  void addKnockouts(List<String> seedSlots) {
    // seedSlots[i] is the slot for seed i+1.
    var round = <String>[]; // fixture ids of the previous round
    final pairs = bracketPairs(seedSlots.length);
    for (final (a, b) in pairs) {
      final f = Fixture(id: fid(), number: ++n, stage: _stageFor(seedSlots.length), slotA: seedSlots[a - 1], slotB: seedSlots[b - 1]);
      fixtures.add(f);
      round.add(f.id);
    }
    var left = seedSlots.length ~/ 2;
    while (round.length > 1) {
      final next = <String>[];
      for (var i = 0; i < round.length; i += 2) {
        final f = Fixture(id: fid(), number: ++n, stage: _stageFor(left), slotA: 'W:${round[i]}', slotB: 'W:${round[i + 1]}');
        fixtures.add(f);
        next.add(f.id);
      }
      round = next;
      left ~/= 2;
    }
  }

  switch (format) {
    case TFormat.groups:
      groups = makeGroups(teamIds, groupCount);
      for (var g = 0; g < groups.length; g++) {
        for (final p in roundRobin(groups[g])) {
          fixtures.add(Fixture(id: fid(), number: ++n, stage: Stage.group, group: g, teamA: p[0], teamB: p[1]));
        }
      }
      // Seeds: all group winners first, then runners-up, and so on.
      final seeds = [
        for (var pos = 1; pos <= qualifiers; pos++)
          for (var g = 0; g < groups.length; g++) 'G${g}P$pos'
      ];
      if (isPowerOfTwo(seeds.length)) addKnockouts(seeds);
    case TFormat.knockout:
      if (!isPowerOfTwo(teamIds.length)) throw ArgumentError('Knockout needs 2, 4, 8 or 16 teams');
      addKnockouts([for (final t in teamIds) 'T:$t']);
    default:
      for (final p in roundRobin(teamIds)) {
        fixtures.add(Fixture(id: fid(), number: ++n, stage: Stage.league, teamA: p[0], teamB: p[1]));
      }
      if (qualifiers >= 2 && isPowerOfTwo(qualifiers)) addKnockouts([for (var i = 1; i <= qualifiers; i++) 'L$i']);
  }

  return Tournament(
    id: id,
    name: name,
    format: format,
    overs: overs,
    teamIds: List.of(teamIds),
    groups: groups,
    fixtures: fixtures,
    createdAt: now ?? DateTime.now(),
    category: category,
    qualifiers: qualifiers,
    venue: venue,
  );
}

/// Everything needed to work out tables and who goes through.
class TournamentView {
  TournamentView(this.t, this.matchState, this.matchTeams);
  final Tournament t;

  /// Match id → state, for matches that exist on this phone.
  final Map<String, MatchState> matchState;

  /// Match id → [team A id, team B id].
  final Map<String, List<String>> matchTeams;

  MatchState? stateOf(Fixture f) => f.matchId == null ? null : matchState[f.matchId];

  bool isFinished(Fixture f) => f.winnerOverride != null || (stateOf(f)?.finished ?? false);

  /// Winner's team id, or null if not decided (yet).
  String? winnerOf(Fixture f) {
    if (f.winnerOverride != null) return f.winnerOverride;
    final st = stateOf(f);
    final teams = f.matchId == null ? null : matchTeams[f.matchId];
    final r = st?.result;
    if (r == null || teams == null || r.winner == null) return null;
    return teams[r.winner!];
  }

  /// Tied or no result in a knockout: the organiser must pick who goes through.
  bool needsPick(Fixture f) {
    if (!Stage.isKnockout(f.stage) || f.winnerOverride != null) return false;
    final r = stateOf(f)?.result;
    return r != null && (r.tie || r.noResult || r.winner == null);
  }

  List<StatMatch> _finishedIn(Iterable<Fixture> fs) => [
        for (final f in fs)
          if (f.matchId != null && matchState[f.matchId]?.finished == true && matchTeams[f.matchId] != null)
            StatMatch(id: f.matchId!, teamIds: matchTeams[f.matchId]!, state: matchState[f.matchId]!),
      ];

  List<PointsRow> table({int? group}) {
    final teams = group == null ? t.teamIds : t.groups[group];
    final fs = t.fixtures.where((f) => group == null ? f.stage == Stage.league : (f.stage == Stage.group && f.group == group));
    return pointsTable(teams, _finishedIn(fs));
  }

  bool stageComplete(String stage, {int? group}) {
    final fs = t.fixtures.where((f) => f.stage == stage && (group == null || f.group == group)).toList();
    return fs.isNotEmpty && fs.every(isFinished);
  }

  /// Team id for a slot, or null while it is still unknown.
  String? resolve(String? slot) {
    if (slot == null) return null;
    if (slot.startsWith('T:')) return slot.substring(2);
    if (slot.startsWith('W:')) {
      final f = t.fixture(slot.substring(2));
      return f == null ? null : winnerOf(f);
    }
    if (slot.startsWith('L')) {
      if (!stageComplete(Stage.league)) return null;
      final pos = int.tryParse(slot.substring(1)) ?? 0;
      final tb = table();
      return pos >= 1 && pos <= tb.length ? tb[pos - 1].teamId : null;
    }
    if (slot.startsWith('G')) {
      final m = RegExp(r'^G(\d+)P(\d+)$').firstMatch(slot);
      if (m == null) return null;
      final g = int.parse(m.group(1)!);
      final pos = int.parse(m.group(2)!);
      if (g >= t.groups.length || !stageComplete(Stage.group, group: g)) return null;
      final tb = table(group: g);
      return pos <= tb.length ? tb[pos - 1].teamId : null;
    }
    return null;
  }

  /// Teams for a fixture: fixed ones, or resolved slots.
  (String?, String?) teamsOf(Fixture f) => (f.teamA ?? resolve(f.slotA), f.teamB ?? resolve(f.slotB));

  /// The champion once the last knockout (or the whole league) is done.
  String? champion() {
    final ko = t.fixtures.where((f) => Stage.isKnockout(f.stage)).toList();
    if (ko.isNotEmpty) return winnerOf(ko.last);
    if (t.format == TFormat.league && stageComplete(Stage.league)) {
      final tb = table();
      return tb.isEmpty ? null : tb.first.teamId;
    }
    return null;
  }

  int get played => t.fixtures.where(isFinished).length;

  List<StatMatch> get allFinished => _finishedIn(t.fixtures);
}

// ------------------------------------------------------------ player of the match

/// Points for one player in one match:
/// 1 per run, +1 per four, +2 per six, +8 for 50, +16 for 100,
/// 25 per wicket, +8 for 3 wickets, 8 per maiden, 8 per catch, 10 per run out or stumping.
double mvpPoints(String playerId, MatchState st) {
  var pts = 0.0;
  for (final inn in st.innings) {
    final b = inn.batters[playerId];
    if (b != null) {
      pts += b.runs + b.fours + b.sixes * 2;
      if (b.runs >= 100) {
        pts += 16;
      } else if (b.runs >= 50) {
        pts += 8;
      }
    }
    final w = inn.bowlers[playerId];
    if (w != null) {
      pts += w.wickets * 25 + w.maidens * 8;
      if (w.wickets >= 3) pts += 8;
    }
    for (final c in inn.batters.values) {
      if (c.fielderId != playerId) continue;
      if (c.outKind == OutKind.caught) pts += 8;
      if (c.outKind == OutKind.runOut || c.outKind == OutKind.stumped) pts += 10;
    }
  }
  return pts;
}

/// Best player of a finished match; ties go to the winning side.
String? playerOfMatch(MatchState st) {
  if (!st.finished) return null;
  final winner = st.result?.winner;
  String? best;
  var bestPts = -1.0;
  var bestOnWinner = false;
  for (var team = 0; team < 2; team++) {
    for (final id in st.setup.players(team)) {
      final pts = mvpPoints(id, st);
      final onWinner = team == winner;
      if (pts > bestPts || (pts == bestPts && onWinner && !bestOnWinner)) {
        best = id;
        bestPts = pts;
        bestOnWinner = onWinner;
      }
    }
  }
  return bestPts > 0 ? best : null;
}

/// Total MVP points per player across matches, best first.
List<(String, double)> mvpTable(Iterable<MatchState> states) {
  final pts = <String, double>{};
  for (final st in states) {
    for (var team = 0; team < 2; team++) {
      for (final id in st.setup.players(team)) {
        pts[id] = (pts[id] ?? 0) + mvpPoints(id, st);
      }
    }
  }
  final list = [for (final e in pts.entries) if (e.value > 0) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}
