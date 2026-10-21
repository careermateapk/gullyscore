import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/tournament.dart';

/// A finished 1-over match where team A (batting first) scores [runsA]
/// and team B scores [runsB] (B stops as soon as it passes A).
MatchState playMatch(List<String> pa, List<String> pb, int runsA, int runsB) {
  final setup = MatchSetup(overs: 1, playersA: pa, playersB: pb, firstBatting: 0);
  final ev = <Map<String, dynamic>>[
    {'t': Ev.start, 'striker': pa[0], 'nonStriker': pa[1], 'bowler': pb[0]},
  ];
  void over(int runs) {
    // up to 6 balls: score [runs] using 6s and 4s and 1s, then dots
    var left = runs;
    for (var i = 0; i < 6; i++) {
      final r = left >= 6 ? 6 : (left >= 4 ? 4 : (left > 0 ? 1 : 0));
      left -= r;
      ev.add({'t': Ev.ball, 'kind': BallKind.normal, 'runs': r});
    }
  }

  over(runsA);
  ev.add({'t': Ev.start, 'striker': pb[0], 'nonStriker': pb[1], 'bowler': pa[0]});
  over(runsB);
  return replay(setup, ev);
}

void main() {
  test('groups are dealt like cards', () {
    expect(makeGroups(['1', '2', '3', '4', '5', '6', '7', '8'], 2), [
      ['1', '4', '5', '8'],
      ['2', '3', '6', '7'],
    ]);
  });

  test('bracket pairs', () {
    expect(bracketPairs(2), [(1, 2)]);
    expect(bracketPairs(4), [(1, 4), (2, 3)]);
    expect(bracketPairs(8), [(1, 8), (4, 5), (2, 7), (3, 6)]);
  });

  test('league of 4 with top 2 makes 6 games and a final', () {
    final t = createTournament(id: 't', name: 'MPL', format: TFormat.league, overs: 10, teamIds: ['a', 'b', 'c', 'd'], qualifiers: 2);
    expect(t.fixtures.where((f) => f.stage == Stage.league).length, 6);
    final fin = t.fixtures.last;
    expect(fin.stage, Stage.finalStage);
    expect((fin.slotA, fin.slotB), ('L1', 'L2'));
    expect(t.fixtures.map((f) => f.number).toList(), [1, 2, 3, 4, 5, 6, 7]);
  });

  test('two groups of 4, top 2: semis cross over, then a final', () {
    final t = createTournament(
        id: 't', name: 'Cup', format: TFormat.groups, overs: 8, teamIds: [for (var i = 1; i <= 8; i++) 't$i'], groupCount: 2, qualifiers: 2);
    expect(t.fixtures.where((f) => f.stage == Stage.group).length, 12);
    final semis = t.fixtures.where((f) => f.stage == Stage.semi).toList();
    expect(semis.length, 2);
    expect((semis[0].slotA, semis[0].slotB), ('G0P1', 'G1P2'));
    expect((semis[1].slotA, semis[1].slotB), ('G1P1', 'G0P2'));
    final fin = t.fixtures.last;
    expect((fin.slotA, fin.slotB), ('W:${semis[0].id}', 'W:${semis[1].id}'));
  });

  test('knockout of 8 has quarter-finals, semis and a final', () {
    final t = createTournament(id: 'k', name: 'KO', format: TFormat.knockout, overs: 6, teamIds: [for (var i = 1; i <= 8; i++) 't$i']);
    expect(t.fixtures.where((f) => f.stage == Stage.quarter).length, 4);
    expect(t.fixtures.where((f) => f.stage == Stage.semi).length, 2);
    expect(t.fixtures.where((f) => f.stage == Stage.finalStage).length, 1);
    expect(() => createTournament(id: 'x', name: 'x', format: TFormat.knockout, overs: 6, teamIds: ['a', 'b', 'c']), throwsArgumentError);
  });

  test('league table decides the final, and the final decides the champion', () {
    final teams = ['a', 'b', 'c'];
    final players = {for (final t in teams) t: ['${t}1', '${t}2', '${t}3']};
    final t = createTournament(id: 't', name: 'MPL', format: TFormat.league, overs: 1, teamIds: teams, qualifiers: 2);
    final states = <String, MatchState>{};
    final mteams = <String, List<String>>{};
    // a beats everyone, b beats c.
    final scores = {'a': 30, 'b': 20, 'c': 10};
    for (final f in t.fixtures.where((f) => f.stage == Stage.league)) {
      final id = 'm${f.number}';
      f.matchId = id;
      states[id] = playMatch(players[f.teamA]!, players[f.teamB]!, scores[f.teamA]!, scores[f.teamB]!);
      mteams[id] = [f.teamA!, f.teamB!];
    }
    var v = TournamentView(t, states, mteams);
    expect(v.table().map((r) => r.teamId).toList(), ['a', 'b', 'c']);
    final fin = t.fixtures.last;
    expect(v.teamsOf(fin), ('a', 'b'));
    expect(v.champion(), isNull);

    fin.matchId = 'final';
    states['final'] = playMatch(players['b']!, players['a']!, 25, 10); // b bats first and wins
    mteams['final'] = ['b', 'a'];
    v = TournamentView(t, states, mteams);
    expect(v.champion(), 'b');
    expect(v.played, 4);
  });

  test('a tied knockout waits for the organiser to pick', () {
    final t = createTournament(id: 'k', name: 'KO', format: TFormat.knockout, overs: 1, teamIds: ['a', 'b']);
    final f = t.fixtures.single;
    f.matchId = 'm';
    final st = playMatch(['a1', 'a2', 'a3'], ['b1', 'b2', 'b3'], 12, 12);
    final v = TournamentView(t, {'m': st}, {'m': ['a', 'b']});
    expect(st.result!.tie, true);
    expect(v.needsPick(f), true);
    expect(v.champion(), isNull);
    f.winnerOverride = 'b';
    expect(TournamentView(t, {'m': st}, {'m': ['a', 'b']}).champion(), 'b');
  });

  test('player of the match favours big runs and wickets', () {
    final st = playMatch(['a1', 'a2', 'a3'], ['b1', 'b2', 'b3'], 30, 10);
    // a1 faced 6s and 4s; a1 scored all 30 off the first balls? strike rotates on singles only.
    expect(mvpPoints('a1', st), greaterThan(0));
    expect(playerOfMatch(st), 'a1');
    final table = mvpTable([st]);
    expect(table.first.$1, 'a1');
  });

  test('tournament survives saving and loading', () {
    final t = createTournament(id: 't', name: 'Cup', format: TFormat.groups, overs: 8, teamIds: ['a', 'b', 'c', 'd'], groupCount: 2, qualifiers: 1, category: 'women');
    t.fixtures.first.matchId = 'm1';
    final back = Tournament.fromJson(t.toJson());
    expect(back.groups, t.groups);
    expect(back.fixtures.length, t.fixtures.length);
    expect(back.fixtures.first.matchId, 'm1');
    expect(back.category, 'women');
    expect(back.fixtures.last.stage, Stage.finalStage);
  });
}
