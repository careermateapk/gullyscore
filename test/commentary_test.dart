import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/scoring/commentary.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/predictor.dart';

Map<String, dynamic> ball(int runs, {String kind = BallKind.normal, Map<String, dynamic>? out, String? zone, String? shot}) => {
      't': Ev.ball,
      'kind': kind,
      'runs': runs,
      if (out != null) 'out': out,
      if (zone != null) 'zone': zone,
      if (shot != null) 'shot': shot,
    };

final setup = MatchSetup(overs: 2, playersA: ['a1', 'a2', 'a3'], playersB: ['b1', 'b2', 'b3'], firstBatting: 0);
String name(String id) => {'a1': 'Sanjay', 'a2': 'Vikas', 'a3': 'Amit', 'b1': 'Pappu', 'b2': 'Ravi', 'b3': 'Raju'}[id] ?? id;

void main() {
  test('zones from angles', () {
    expect(Zone.fromAngle(10), Zone.longOff);
    expect(Zone.fromAngle(60), Zone.cover);
    expect(Zone.fromAngle(300), Zone.midWicket);
    expect(Zone.fromAngle(-10), Zone.longOn);
  });

  test('commentary uses only what the scorer entered', () {
    final m = replay(setup, <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(4, zone: Zone.cover, shot: 'drive'),
      ball(1),
      ball(6, zone: Zone.longOn),
      ball(0, out: {'kind': OutKind.caught, 'fielder': 'b3'}),
    ]);
    final items = buildCommentary(m.innings[0], name);
    // newest first
    expect(items.first.headline, 'Pappu to Vikas, OUT.');
    expect(items.first.detail, 'Caught by Raju. Vikas 6 (2).');
    final four = items.last;
    expect(four.headline, 'Pappu to Sanjay, FOUR.');
    expect(four.detail, 'Driven through the covers.');
    final single = items[2];
    expect(single.headline, 'Pappu to Sanjay, 1 run.');
    expect(single.detail, '');
    expect(items[1].detail, 'Hit over long-on.');
  });

  test('over summary after six legal balls', () {
    final m = replay(setup, <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(1),
      ball(0, kind: BallKind.wide),
      for (var i = 0; i < 5; i++) ball(0),
    ]);
    final items = buildCommentary(m.innings[0], name);
    expect(items.first.type, CommType.overEnd);
    expect(items.first.overRuns, 2);
    expect(items.first.overBalls.length, 7);
    expect(items.first.headline, 'End of over 1 · 2 runs');
  });

  test('hindi commentary', () {
    final m = replay(setup, <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(6, zone: Zone.longOn),
    ]);
    final items = buildCommentary(m.innings[0], name, lang: 'hi');
    expect(items.first.headline, 'Pappu से Sanjay, छक्का!');
    expect(items.first.detail, 'लॉन्ग-ऑन के ऊपर से।');
  });

  test('ball log keeps over.ball and score', () {
    final m = replay(setup, <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(2),
      ball(0, kind: BallKind.wide),
      ball(4),
    ]);
    final balls = m.innings[0].balls;
    expect(balls[0].overBall, '0.1');
    expect(balls[1].overBall, '0.2');
    expect(balls[2].overBall, '0.2');
    expect(balls[2].scoreRuns, 7);
    expect(balls[2].isFour, true);
  });

  test('partnerships are recorded at each wicket', () {
    final m = replay(setup, <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      ball(4),
      ball(1),
      ball(0, out: {'kind': OutKind.bowled}),
    ]);
    final inn = m.innings[0];
    expect(inn.partnerships.length, 1);
    expect(inn.partnerships.first.runs, 5);
    expect(inn.partnerships.first.balls, 3);
    expect(inn.partnershipRuns, 0);
  });

  test('win chance rises as the chase gets easier', () {
    final base = <Map<String, dynamic>>[
      {'t': Ev.start, 'striker': 'a1', 'nonStriker': 'a2', 'bowler': 'b1'},
      for (var i = 0; i < 6; i++) ball(1),
      {'t': Ev.bowler, 'player': 'b2'},
      for (var i = 0; i < 6; i++) ball(1),
      {'t': Ev.start, 'striker': 'b1', 'nonStriker': 'b2', 'bowler': 'a1'},
    ];
    final early = winChance(replay(setup, base))!;
    final good = winChance(replay(setup, [...base, ball(6), ball(4)]))!;
    expect(good.chasingPercent, greaterThan(early.chasingPercent));
    expect(early.chasingTeam, 1);
    final won = winChance(replay(setup, [...base, ball(6), ball(6), ball(1)]))!;
    expect(won.chasingPercent, 100);
  });
}
