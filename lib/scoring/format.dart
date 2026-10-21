// Turns a match state into plain text / a summary map with player names.
// The summary is saved in the match document so the live web page can show
// the scorecard without running the engine.
import 'engine.dart';

String howOutText(BatterCard b, String Function(String id) name) {
  if (!b.out && b.outKind != OutKind.retired) return 'not out';
  final bowler = b.bowlerId == null ? '' : name(b.bowlerId!);
  final fielder = b.fielderId == null ? '' : name(b.fielderId!);
  switch (b.outKind) {
    case OutKind.bowled:
      return 'b $bowler';
    case OutKind.caught:
      if (b.fielderId == b.bowlerId) return 'c & b $bowler';
      return fielder.isEmpty ? 'c ? b $bowler' : 'c $fielder b $bowler';
    case OutKind.lbw:
      return 'lbw b $bowler';
    case OutKind.runOut:
      return fielder.isEmpty ? 'run out' : 'run out ($fielder)';
    case OutKind.stumped:
      return 'st $fielder b $bowler';
    case OutKind.hitWicket:
      return 'hit wicket b $bowler';
    case OutKind.retired:
      return 'retired';
  }
  return 'out';
}

String extrasText(Extras e) => '${e.total} (wd ${e.wides}, nb ${e.noBalls}, b ${e.byes}, lb ${e.legByes})';

String f1(double v) => v.toStringAsFixed(1);
String f2(double v) => v.toStringAsFixed(2);

Map<String, dynamic> buildSummary({
  required MatchState state,
  required String nameA,
  required String nameB,
  required String Function(String id) name,
}) {
  String team(int t) => t == 0 ? nameA : nameB;
  final innings = <Map<String, dynamic>>[];
  for (final inn in state.innings) {
    innings.add({
      'team': team(inn.battingTeam),
      'score': '${inn.runs}/${inn.wickets}',
      'overs': inn.overs,
      'extras': extrasText(inn.extras),
      'batting': [
        for (final id in inn.battingOrder)
          {
            'name': name(id),
            'out': howOutText(inn.batters[id]!, name),
            'r': inn.batters[id]!.runs,
            'b': inn.batters[id]!.balls,
            '4s': inn.batters[id]!.fours,
            '6s': inn.batters[id]!.sixes,
            'sr': f1(inn.batters[id]!.strikeRate),
            'onStrike': !inn.ended && id == inn.striker,
            'batting': !inn.ended && (id == inn.striker || id == inn.nonStriker),
          }
      ],
      'bowling': [
        for (final id in inn.bowlingOrder)
          {
            'name': name(id),
            'o': inn.bowlers[id]!.overs,
            'm': inn.bowlers[id]!.maidens,
            'r': inn.bowlers[id]!.runs,
            'w': inn.bowlers[id]!.wickets,
            'econ': f2(inn.bowlers[id]!.economy),
            'bowling': !inn.ended && id == inn.bowler,
          }
      ],
      'fow': [for (final f in inn.fallOfWickets) '${f.runs}-${f.wicket} (${name(f.player)}, ${f.overs})'],
    });
  }

  final cur = state.current;
  String status;
  if (state.finished) {
    status = state.resultText(nameA, nameB);
  } else if (cur == null) {
    status = 'Match about to start';
  } else if (state.innings.length == 2 && !cur.ended) {
    final need = state.runsNeeded ?? 0;
    final left = state.ballsLeft ?? 0;
    status = '${team(cur.battingTeam)} need $need ${need == 1 ? 'run' : 'runs'} from $left ${left == 1 ? 'ball' : 'balls'}';
  } else if (cur.ended) {
    status = 'Innings break · ${team(1 - cur.battingTeam)} need ${cur.runs + 1} to win';
  } else {
    status = '${team(cur.battingTeam)} batting · CRR ${f2(cur.runRate)}';
  }

  return {
    'title': '$nameA vs $nameB',
    'status': status,
    'finished': state.finished,
    'innings': innings,
    'thisOver': cur == null || cur.ended ? <String>[] : [for (final b in cur.thisOver) b.label],
  };
}

/// Short score line, e.g. "Lions 120/4 (15.2)".
String scoreLine(Innings inn, String teamName) => '$teamName ${inn.runs}/${inn.wickets} (${inn.overs})';
