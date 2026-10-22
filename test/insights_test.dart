import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/insights.dart';
import 'package:gullyscore/scoring/stats.dart';

Map<String, dynamic> ball(int runs, {String kind = BallKind.normal, Map<String, dynamic>? out}) =>
    {'t': Ev.ball, 'kind': kind, 'runs': runs, if (out != null) 'out': out};

final setup = MatchSetup(overs: 3, playersA: ['a1', 'a2', 'a3', 'a4'], playersB: ['b1', 'b2', 'b3', 'b4'], firstBatting: 0);

// A bats 3 overs: 30/1. B chases 31: cruises, then over 2 (b-team's 2nd over) loses 3 wickets.
final events = <Map<String, dynamic>>[
  {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
  ball(4), ball(6), ball(1), ball(0), ball(4), ball(1),
  {'t': Ev.bowler, 'player': 'b2'},
  ball(0), ball(1), ball(4), ball(0, out: {'kind': OutKind.bowled}),
  {'t': Ev.batter, 'player': 'a3'},
  ball(1), ball(0),
  {'t': Ev.bowler, 'player': 'b1'},
  ball(0, kind: BallKind.wide), ball(4), ball(1), ball(0), ball(1), ball(0), ball(1),
  {'t': Ev.start, 'striker': 'b1', 'nonStriker': 'b2', 'bowler': 'a1'},
  ball(6), ball(6), ball(4), ball(1), ball(1), ball(1),
  {'t': Ev.bowler, 'player': 'a2'},
  ball(0, out: {'kind': OutKind.caught, 'fielder': 'a1'}),
  {'t': Ev.batter, 'player': 'b3'},
  ball(0, out: {'kind': OutKind.bowled}),
  {'t': Ev.batter, 'player': 'b4'},
  ball(0, out: {'kind': OutKind.lbw}),
];

void main() {
  final st = replay(setup, events);
  final sm = StatMatch(id: 'm1', teamIds: ['A', 'B'], state: st);

  test('head to head counts balls, runs, outs and the ball sequence', () {
    final h = headToHead('a1', 'b1', [sm]);
    expect(h.balls, greaterThan(0));
    expect(h.sequence.first, '4');
    expect(h.sequence[1], '6');
    final h2 = headToHead('a1', 'b2', [sm]);
    expect(h2.outs, 1);
    expect(h2.howOut[OutKind.bowled], 1);
    expect(h2.sequence.contains('W'), true);
    expect(rivals('a1', [sm], asBatter: true).first.$1, isNotEmpty);
  });

  test('levels climb with XP and never pass Legend', () {
    expect(Level(0).number, 0);
    expect(Level(0).tier, 0);
    expect(Level(Level.needed(3)).tier, 1); // Club I
    expect(Level(Level.needed(3)).step, 1);
    expect(Level(1 << 30).isMax, true);
    expect(Level(1 << 30).tier, levelTiers.length - 1);
    final l = Level(Level.needed(4) + 10);
    expect(l.progress, greaterThan(0));
    expect(l.toNext, Level.needed(5) - l.xp);
    final s = playerStats('a1', [sm]);
    expect(xpOf(s), s.matches * 10 + s.runs + s.wickets * 20 + (s.catches + s.runOuts + s.stumpings) * 10 + s.fifties * 25 + s.hundreds * 75);
  });

  test('win chance goes down when wickets fall and up when runs come', () {
    expect(chaseWinChance(0, 10, 5), 100);
    expect(chaseWinChance(10, 0, 5), 0);
    expect(chaseWinChance(30, 60, 10) > chaseWinChance(30, 60, 3), true);
    expect(chaseWinChance(20, 60, 8) > chaseWinChance(60, 60, 8), true);
  });

  test('match story finds the over that turned the chase', () {
    expect(st.finished, true);
    final s = matchStory(st);
    expect(s.chase, true);
    expect(s.turning, isNotNull);
    expect(s.turning!.innings, 1);
    expect(s.turning!.wickets, 3);
    expect(s.chances.first, inInclusiveRange(1, 99));
    expect(s.bestOver!.runs, greaterThanOrEqualTo(12));
  });

  test('season wrapped adds up a player year', () {
    final w = seasonWrapped('a1', [WrappedMatch(sm, DateTime(2026, 10, 25), 'Rajnagar'), WrappedMatch(sm, DateTime(2026, 10, 18), 'Rajnagar')], runsByPlayer: {'a1': 40, 'a2': 10, 'b1': 30});
    final s = playerStats('a1', [sm]);
    expect(w.matches, 2);
    expect(w.runs, s.runs * 2);
    expect(w.favouriteGround, 'Rajnagar');
    expect(w.favouriteGroundMatches, 2);
    expect(w.bestWeekday, DateTime.sunday);
    expect(w.catches, 2);
    expect(w.rankOf, 3);
    expect(w.personality, isNotEmpty);
    final b2 = seasonWrapped('b1', [WrappedMatch(sm, DateTime(2026, 1, 1), '')]);
    expect(b2.matches, 1);
  });
}
