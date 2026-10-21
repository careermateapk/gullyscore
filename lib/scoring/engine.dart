// Ball-by-ball cricket scoring engine.
//
// A match is stored as a list of events. The whole match state is rebuilt
// by replaying those events from the start, so "undo" is simply removing
// the last events. This file has no Flutter imports so it can be unit tested.

/// Kinds of delivery.
class BallKind {
  static const normal = 'normal';
  static const wide = 'wide';
  static const noBall = 'noball';
  static const bye = 'bye';
  static const legBye = 'legbye';
}

/// Ways a batter can be out.
class OutKind {
  static const bowled = 'bowled';
  static const caught = 'caught';
  static const lbw = 'lbw';
  static const runOut = 'run out';
  static const stumped = 'stumped';
  static const hitWicket = 'hit wicket';
  static const retired = 'retired';

  static const all = [bowled, caught, lbw, runOut, stumped, hitWicket, retired];

  /// Wickets the bowler gets credit for.
  static bool creditsBowler(String kind) =>
      kind == bowled || kind == caught || kind == lbw || kind == stumped || kind == hitWicket;

  /// Wickets that need a fielder name.
  static bool needsFielder(String kind) => kind == caught || kind == runOut || kind == stumped;
}

/// Event types stored in the match.
class Ev {
  static const start = 'start'; // {striker, nonStriker, bowler}
  static const ball = 'ball'; // {kind, runs, out?: {kind, player, fielder}}
  static const batter = 'batter'; // {player}
  static const bowler = 'bowler'; // {player}
  static const swap = 'swap'; // swap strike
  static const endInnings = 'end'; // end innings early
}

class BatterCard {
  BatterCard(this.id);
  final String id;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  bool out = false;
  String howOut = 'not out';
  String? outKind;
  String? bowlerId;
  String? fielderId;

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlerCard {
  BowlerCard(this.id);
  final String id;
  int balls = 0; // legal balls
  int runs = 0;
  int wickets = 0;
  int maidens = 0;
  int wides = 0;
  int noBalls = 0;

  String get overs => oversText(balls);
  double get economy => balls == 0 ? 0 : runs * 6 / balls;
}

class Extras {
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;
  int get total => wides + noBalls + byes + legByes;
}

/// One delivery, with everything needed to show it and write commentary.
class BallLog {
  BallLog(
    this.label,
    this.legal,
    this.over, {
    this.ballInOver = 0,
    this.striker = '',
    this.bowler = '',
    this.kind = BallKind.normal,
    this.runs = 0,
    this.outKind,
    this.outPlayer,
    this.fielder,
    this.zone,
    this.shot,
    this.angle,
    this.dist,
    this.scoreRuns = 0,
    this.scoreWickets = 0,
    this.index = 0,
  });
  final String label;
  final bool legal;
  final int over; // over number (0-based) the ball belongs to
  final int ballInOver; // 1-6 for legal balls; for extras, the next legal ball number
  final String striker;
  final String bowler;
  final String kind;
  final int runs; // runs off the bat or run (not counting the 1 for wide/no-ball)
  final String? outKind;
  final String? outPlayer;
  final String? fielder;
  final String? zone; // where the ball went, e.g. "cover"
  final String? shot; // e.g. "drive"
  final double? angle; // degrees, 0 = straight back past the bowler, clockwise, right-hander's view
  final double? dist; // 0-1, how far from the bat (1 = boundary)
  final int scoreRuns; // team score after this ball
  final int scoreWickets;
  final int index; // position in the innings' ball list

  /// "11.2" style label (over.ball, 1-based ball).
  String get overBall => '$over.$ballInOver';
  bool get isFour => runs == 4 && (kind == BallKind.normal || kind == BallKind.noBall);
  bool get isSix => runs == 6 && (kind == BallKind.normal || kind == BallKind.noBall);
  bool get isWicket => outKind != null && outKind != OutKind.retired;
  /// Total runs this delivery added to the team.
  int get teamRuns => (kind == BallKind.wide || kind == BallKind.noBall) ? runs + 1 : runs;
}

class Innings {
  Innings(this.battingTeam, this.number);
  final int battingTeam; // 0 = team A, 1 = team B
  final int number; // 0 or 1
  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  final Extras extras = Extras();
  final Map<String, BatterCard> batters = {};
  final List<String> battingOrder = [];
  final Map<String, BowlerCard> bowlers = {};
  final List<String> bowlingOrder = [];
  final List<FallOfWicket> fallOfWickets = [];
  final List<BallLog> balls = [];
  String? striker;
  String? nonStriker;
  String? bowler;
  String? lastOverBowler;
  bool ended = false;
  bool allOut = false;
  int _overRuns = 0; // runs against bowler in current over (for maidens)
  int partnershipRuns = 0;
  int partnershipBalls = 0;
  final List<Partnership> partnerships = [];

  String get overs => oversText(legalBalls);
  double get runRate => legalBalls == 0 ? 0 : runs * 6 / legalBalls;

  BatterCard batterCard(String id) {
    return batters.putIfAbsent(id, () {
      battingOrder.add(id);
      return BatterCard(id);
    });
  }

  BowlerCard bowlerCard(String id) {
    return bowlers.putIfAbsent(id, () {
      bowlingOrder.add(id);
      return BowlerCard(id);
    });
  }

  /// Balls of the over currently being bowled (or the last finished one).
  List<BallLog> get thisOver {
    if (balls.isEmpty) return [];
    final current = balls.last.legal && legalBalls % 6 == 0 && legalBalls > 0
        ? balls.last.over
        : legalBalls ~/ 6;
    return balls.where((b) => b.over == current).toList();
  }
}

class Partnership {
  Partnership(this.a, this.b, this.runs, this.balls);
  final String a;
  final String b;
  final int runs;
  final int balls;
}

class FallOfWicket {
  FallOfWicket(this.runs, this.wicket, this.player, this.overs);
  final int runs;
  final int wicket;
  final String player;
  final String overs;
}

String oversText(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

/// Settings needed to replay a match.
class MatchSetup {
  MatchSetup({
    required this.overs,
    required this.playersA,
    required this.playersB,
    required this.firstBatting,
  });

  final int overs;
  final List<String> playersA;
  final List<String> playersB;
  final int firstBatting; // 0 = team A bats first

  List<String> players(int team) => team == 0 ? playersA : playersB;
}

/// What the scorer must do next.
enum NextStep {
  startInnings, // pick openers and bowler
  newBatter, // pick the next batter
  newBowler, // pick the bowler for the next over
  ball, // score the next ball
  finished, // match over
}

class MatchState {
  MatchState(this.setup);
  final MatchSetup setup;
  final List<Innings> innings = [];

  Innings? get current => innings.isEmpty ? null : innings.last;

  int? get target => innings.isNotEmpty && innings.length == 2 ? innings[0].runs + 1 : null;

  bool get finished {
    if (innings.length < 2) return false;
    if (innings[1].ended) return true;
    return false;
  }

  NextStep get nextStep {
    if (finished) return NextStep.finished;
    final inn = current;
    if (inn == null || inn.ended) return NextStep.startInnings;
    if (inn.striker == null || inn.nonStriker == null) return NextStep.newBatter;
    if (inn.bowler == null) return NextStep.newBowler;
    return NextStep.ball;
  }

  /// Team batting in the innings that is about to start / is running.
  int get battingTeamNow {
    if (innings.isEmpty) return setup.firstBatting;
    final inn = innings.last;
    if (inn.ended) return 1 - inn.battingTeam;
    return inn.battingTeam;
  }

  int get bowlingTeamNow => 1 - battingTeamNow;

  /// Batters who can still come in.
  List<String> availableBatters() {
    final inn = current;
    final team = battingTeamNow;
    if (inn == null || inn.ended) return List.of(setup.players(team));
    return setup
        .players(team)
        .where((p) => !(inn.batters[p]?.out ?? false) && p != inn.striker && p != inn.nonStriker)
        .toList();
  }

  /// Runs still needed in the chase.
  int? get runsNeeded {
    final t = target;
    if (t == null || innings.length < 2) return null;
    return t - innings[1].runs;
  }

  int? get ballsLeft {
    final inn = current;
    if (inn == null) return null;
    return setup.overs * 6 - inn.legalBalls;
  }

  /// Result text, e.g. "Tigers won by 5 wickets".
  String resultText(String nameA, String nameB) {
    final r = result;
    if (r == null) return '';
    String name(int t) => t == 0 ? nameA : nameB;
    if (r.tie) return 'Match tied';
    if (r.noResult) return 'No result';
    return '${name(r.winner!)} won by ${r.margin} ${r.byRuns ? (r.margin == 1 ? 'run' : 'runs') : (r.margin == 1 ? 'wicket' : 'wickets')}';
  }

  MatchResult? get result {
    if (!finished) return null;
    final a = innings[0];
    final b = innings[1];
    if (b.legalBalls == 0 && b.runs == 0 && b.wickets == 0) {
      // second innings ended without a ball (abandoned)
      return MatchResult(noResult: true);
    }
    if (b.runs > a.runs) {
      final wktsLeft = setup.players(b.battingTeam).length - 1 - b.wickets;
      return MatchResult(winner: b.battingTeam, margin: wktsLeft < 0 ? 0 : wktsLeft, byRuns: false);
    }
    if (b.runs == a.runs) return MatchResult(tie: true);
    return MatchResult(winner: a.battingTeam, margin: a.runs - b.runs, byRuns: true);
  }
}

class MatchResult {
  MatchResult({this.winner, this.margin = 0, this.byRuns = false, this.tie = false, this.noResult = false});
  final int? winner;
  final int margin;
  final bool byRuns;
  final bool tie;
  final bool noResult;
}

/// Rebuilds the match state from its events.
MatchState replay(MatchSetup setup, List<Map<String, dynamic>> events) {
  final m = MatchState(setup);
  for (final e in events) {
    _apply(m, e);
  }
  return m;
}

void _apply(MatchState m, Map<String, dynamic> e) {
  final type = e['t'] as String?;
  if (m.finished) return;

  if (type == Ev.start) {
    if (m.innings.length >= 2) return;
    if (m.innings.isNotEmpty && !m.innings.last.ended) return;
    final inn = Innings(m.battingTeamNow, m.innings.length);
    m.innings.add(inn);
    inn.striker = e['striker'] as String?;
    inn.nonStriker = e['nonStriker'] as String?;
    inn.bowler = e['bowler'] as String?;
    if (inn.striker != null) inn.batterCard(inn.striker!);
    if (inn.nonStriker != null) inn.batterCard(inn.nonStriker!);
    if (inn.bowler != null) inn.bowlerCard(inn.bowler!);
    return;
  }

  final inn = m.current;
  if (inn == null || inn.ended) return;

  switch (type) {
    case Ev.batter:
      final p = e['player'] as String?;
      if (p == null) return;
      if (inn.striker == null) {
        inn.striker = p;
      } else if (inn.nonStriker == null) {
        inn.nonStriker = p;
      } else {
        return;
      }
      inn.batterCard(p);
      return;
    case Ev.bowler:
      final p = e['player'] as String?;
      if (p == null) return;
      inn.bowler = p;
      inn.bowlerCard(p);
      inn._overRuns = 0;
      return;
    case Ev.swap:
      final s = inn.striker;
      inn.striker = inn.nonStriker;
      inn.nonStriker = s;
      return;
    case Ev.endInnings:
      _endInnings(m, inn);
      return;
    case Ev.ball:
      _ball(m, inn, e);
      return;
  }
}

void _endInnings(MatchState m, Innings inn) {
  inn.ended = true;
}

void _ball(MatchState m, Innings inn, Map<String, dynamic> e) {
  final strikerId = inn.striker;
  final bowlerId = inn.bowler;
  if (strikerId == null || inn.nonStriker == null || bowlerId == null) return;

  final kind = (e['kind'] as String?) ?? BallKind.normal;
  final runs = (e['runs'] as num?)?.toInt() ?? 0;
  final out = e['out'] as Map<String, dynamic>?;
  final striker = inn.batterCard(strikerId);
  final bowler = inn.bowlerCard(bowlerId);
  final overIndex = inn.legalBalls ~/ 6;

  var legal = true;
  var label = '$runs';

  switch (kind) {
    case BallKind.wide:
      legal = false;
      inn.runs += 1 + runs;
      inn.extras.wides += 1 + runs;
      bowler.runs += 1 + runs;
      bowler.wides += 1 + runs;
      inn._overRuns += 1 + runs;
      label = runs == 0 ? 'Wd' : '${runs + 1}Wd';
      break;
    case BallKind.noBall:
      legal = false;
      inn.runs += 1 + runs;
      inn.extras.noBalls += 1;
      bowler.runs += 1 + runs;
      bowler.noBalls += 1;
      inn._overRuns += 1 + runs;
      striker.runs += runs;
      striker.balls += 1;
      if (runs == 4) striker.fours++;
      if (runs == 6) striker.sixes++;
      label = runs == 0 ? 'Nb' : '${runs}Nb';
      break;
    case BallKind.bye:
      inn.runs += runs;
      inn.extras.byes += runs;
      striker.balls += 1;
      label = '${runs}B';
      break;
    case BallKind.legBye:
      inn.runs += runs;
      inn.extras.legByes += runs;
      striker.balls += 1;
      label = '${runs}Lb';
      break;
    default:
      inn.runs += runs;
      striker.runs += runs;
      striker.balls += 1;
      if (runs == 4) striker.fours++;
      if (runs == 6) striker.sixes++;
      bowler.runs += runs;
      inn._overRuns += runs;
      label = runs == 0 ? '•' : '$runs';
  }

  // Runs actually run between the wickets decide the strike.
  if (runs.isOdd) {
    final s = inn.striker;
    inn.striker = inn.nonStriker;
    inn.nonStriker = s;
  }

  inn.partnershipRuns += (kind == BallKind.wide || kind == BallKind.noBall) ? runs + 1 : runs;
  if (legal) inn.partnershipBalls++;

  if (out != null) {
    final outKind = (out['kind'] as String?) ?? OutKind.bowled;
    final outId = (out['player'] as String?) ?? strikerId;
    final fielder = out['fielder'] as String?;
    final card = inn.batterCard(outId);
    card.out = outKind != OutKind.retired;
    card.outKind = outKind;
    card.bowlerId = bowlerId;
    card.fielderId = fielder;
    card.howOut = outKind; // display text is built in the UI with names
    if (outKind != OutKind.retired) {
      inn.partnerships.add(Partnership(strikerId, (inn.striker == strikerId ? inn.nonStriker : inn.striker) ?? '', inn.partnershipRuns, inn.partnershipBalls));
      inn.partnershipRuns = 0;
      inn.partnershipBalls = 0;
      inn.wickets++;
      inn.fallOfWickets.add(FallOfWicket(inn.runs, inn.wickets, outId, oversText(inn.legalBalls + (legal ? 1 : 0))));
    }
    if (OutKind.creditsBowler(outKind)) bowler.wickets++;
    label = label == '•' ? 'W' : '$label W';
    if (inn.striker == outId) {
      inn.striker = null;
    } else if (inn.nonStriker == outId) {
      inn.nonStriker = null;
    }
  }

  inn.balls.add(BallLog(
    label,
    legal,
    overIndex,
    ballInOver: inn.legalBalls % 6 + 1,
    striker: strikerId,
    bowler: bowlerId,
    kind: kind,
    runs: runs,
    outKind: out == null ? null : ((out['kind'] as String?) ?? OutKind.bowled),
    outPlayer: out == null ? null : ((out['player'] as String?) ?? strikerId),
    fielder: out?['fielder'] as String?,
    zone: e['zone'] as String?,
    shot: e['shot'] as String?,
    angle: (e['ang'] as num?)?.toDouble(),
    dist: (e['dist'] as num?)?.toDouble(),
    scoreRuns: inn.runs,
    scoreWickets: inn.wickets,
    index: inn.balls.length,
  ));

  if (legal) {
    inn.legalBalls++;
    bowler.balls++;
    if (inn.legalBalls % 6 == 0) {
      // Over finished.
      if (inn._overRuns == 0) bowler.maidens++;
      inn._overRuns = 0;
      final s = inn.striker;
      inn.striker = inn.nonStriker;
      inn.nonStriker = s;
      inn.lastOverBowler = bowlerId;
      inn.bowler = null;
    }
  }

  // Did the innings end?
  final squad = m.setup.players(inn.battingTeam).length;
  final notOutLeft = squad - inn.wickets - inn.batters.values.where((b) => b.outKind == OutKind.retired).length;
  if (notOutLeft < 2) {
    inn.ended = true;
    inn.allOut = true;
  }
  if (inn.legalBalls >= m.setup.overs * 6) inn.ended = true;
  if (inn.number == 1 && inn.runs > m.innings[0].runs) inn.ended = true;
}

/// Removes events back to (and including) the last ball. Returns the new list.
List<Map<String, dynamic>> undoLast(List<Map<String, dynamic>> events) {
  final list = List<Map<String, dynamic>>.of(events);
  while (list.isNotEmpty) {
    final e = list.removeLast();
    if (e['t'] == Ev.ball) break;
  }
  return list;
}
