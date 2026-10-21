import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/stats.dart';

Map<String, dynamic> ball(int runs, {String kind = BallKind.normal, Map<String, dynamic>? out}) =>
    {'t': Ev.ball, 'kind': kind, 'runs': runs, if (out != null) 'out': out};

final setup = MatchSetup(
  overs: 2,
  playersA: ['a1', 'a2', 'a3'],
  playersB: ['b1', 'b2', 'b3'],
  firstBatting: 0,
);

final events = <Map<String, dynamic>>[
  {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
  ball(1),
  ball(4),
  ball(0, kind: BallKind.wide),
  ball(0),
  ball(6),
  ball(0, kind: BallKind.noBall),
  ball(0, out: {'kind': OutKind.bowled}),
  {'t': Ev.batter, 'player': 'a3'},
  ball(1, kind: BallKind.legBye),
  {'t': Ev.bowler, 'player': 'b2'},
  ball(0, out: {'kind': OutKind.caught, 'fielder': 'b1'}),
  {'t': Ev.start, 'striker': 'b1', 'nonStriker': 'b2', 'bowler': 'a1'},
  ball(6),
  ball(6),
  ball(4),
];

void main() {
  test('first innings totals, extras and cards', () {
    final m = replay(setup, events);
    final i1 = m.innings[0];
    expect(i1.runs, 14);
    expect(i1.wickets, 2);
    expect(i1.allOut, true);
    expect(i1.overs, '1.1');
    expect(i1.extras.total, 3);
    expect(i1.batters['a2']!.runs, 10);
    expect(i1.batters['a2']!.balls, 5);
    expect(i1.batters['a3']!.balls, 2);
    expect(i1.batters['a3']!.outKind, OutKind.caught);
    expect(i1.bowlers['b1']!.runs, 13);
    expect(i1.bowlers['b1']!.balls, 6);
    expect(i1.bowlers['b1']!.wickets, 1);
    expect(i1.bowlers['b2']!.wickets, 1);
  });

  test('chase ends the match with the right result', () {
    final m = replay(setup, events);
    expect(m.finished, true);
    expect(m.nextStep, NextStep.finished);
    expect(m.innings[1].runs, 16);
    expect(m.resultText('Lions', 'Tigers'), 'Tigers won by 2 wickets');
  });

  test('over end swaps strike and asks for a new bowler', () {
    final m = replay(setup, [
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      for (var i = 0; i < 6; i++) ball(0),
    ]);
    final inn = m.current!;
    expect(inn.striker, 'a2');
    expect(inn.nonStriker, 'a1');
    expect(m.nextStep, NextStep.newBowler);
    expect(inn.bowlers['b1']!.maidens, 1);
    expect(inn.lastOverBowler, 'b1');
  });

  test('wicket asks for a new batter', () {
    final m = replay(setup, [
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(0, out: {'kind': OutKind.lbw}),
    ]);
    expect(m.nextStep, NextStep.newBatter);
    expect(m.availableBatters(), ['a3']);
  });

  test('undo removes the last ball', () {
    final before = replay(setup, undoLast(events));
    expect(before.finished, false);
    expect(before.innings[1].runs, 12);
  });

  test('points table and net run rate', () {
    final m = replay(setup, events);
    final table = pointsTable(['A', 'B'], [StatMatch(id: 'm', teamIds: ['A', 'B'], state: m)]);
    expect(table.first.teamId, 'B');
    expect(table.first.points, 2);
    expect(table.first.nrr, closeTo(25, 0.001));
    expect(table.last.nrr, closeTo(-25, 0.001));
  });

  test('player career stats', () {
    final m = replay(setup, events);
    final list = [StatMatch(id: 'm', teamIds: ['A', 'B'], state: m)];
    final a2 = playerStats('a2', list);
    expect(a2.runs, 10);
    expect(a2.fours, 1);
    expect(a2.sixes, 1);
    final b1 = playerStats('b1', list);
    expect(b1.runs, 16);
    expect(b1.notOuts, 1);
    expect(b1.wickets, 1);
    expect(b1.catches, 1);
  });

  test('round robin fixtures', () {
    expect(roundRobin(['a', 'b', 'c', 'd']).length, 6);
    expect(roundRobin(['a', 'b', 'c']).length, 3);
  });
}
