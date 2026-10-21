// Short match reports written from the scorer's data only.
import 'engine.dart';

class MatchReport {
  MatchReport({required this.headline, required this.paragraphs, required this.topScore, required this.bestBowling, required this.sixes});
  final String headline;
  final List<String> paragraphs;
  final String topScore; // e.g. "64*"
  final String bestBowling; // e.g. "2/22"
  final int sixes;
}

class _Bat {
  _Bat(this.card, this.team);
  final BatterCard card;
  final int team;
}

class _Bowl {
  _Bowl(this.card, this.team);
  final BowlerCard card;
  final int team; // team the bowler plays for
}

/// Returns null for a match that has not finished.
MatchReport? buildReport(
  MatchState st, {
  required String teamA,
  required String teamB,
  required String Function(String id) name,
  String lang = 'en',
}) {
  if (!st.finished || st.innings.isEmpty) return null;
  final hi = lang == 'hi';
  String team(int t) => t == 0 ? teamA : teamB;
  final r = st.result!;

  final bats = <_Bat>[for (final i in st.innings) for (final c in i.batters.values) _Bat(c, i.battingTeam)];
  final bowls = <_Bowl>[for (final i in st.innings) for (final c in i.bowlers.values) _Bowl(c, 1 - i.battingTeam)];
  bats.sort((a, b) => b.card.runs != a.card.runs ? b.card.runs.compareTo(a.card.runs) : a.card.balls.compareTo(b.card.balls));
  bowls.sort((a, b) => b.card.wickets != a.card.wickets ? b.card.wickets.compareTo(a.card.wickets) : a.card.runs.compareTo(b.card.runs));
  final topBat = bats.isEmpty ? null : bats.first;
  final topBowl = bowls.isEmpty ? null : bowls.first;
  String star(BatterCard c) => c.out ? '' : '*';

  String headline;
  if (r.tie) {
    headline = hi ? '${team(0)} और ${team(1)} का मैच टाई' : '${team(0)} and ${team(1)} tie a thriller';
  } else if (r.noResult || r.winner == null) {
    headline = hi ? '${team(0)} बनाम ${team(1)}: कोई नतीजा नहीं' : 'No result between ${team(0)} and ${team(1)}';
  } else {
    final w = r.winner!;
    final l = 1 - w;
    if (topBat != null && topBat.team == w && topBat.card.runs > 0) {
      final runs = '${topBat.card.runs}${star(topBat.card)}';
      headline = hi
          ? '${name(topBat.card.id)} के $runs से ${team(w)} ने ${team(l)} को हराया'
          : "${name(topBat.card.id)}'s $runs takes ${team(w)} past ${team(l)}";
    } else if (topBowl != null && topBowl.team == w && topBowl.card.wickets > 0) {
      final fig = '${topBowl.card.wickets}/${topBowl.card.runs}';
      headline = hi
          ? '${name(topBowl.card.id)} के $fig से ${team(w)} की जीत'
          : "${name(topBowl.card.id)}'s $fig helps ${team(w)} beat ${team(l)}";
    } else {
      headline = hi ? '${team(w)} ने ${team(l)} को हराया' : '${team(w)} beat ${team(l)}';
    }
  }

  final paras = <String>[];
  for (final inn in st.innings) {
    final bt = inn.batters.values.toList()..sort((a, b) => b.runs.compareTo(a.runs));
    final bw = inn.bowlers.values.toList()..sort((a, b) => b.wickets != a.wickets ? b.wickets.compareTo(a.wickets) : a.runs.compareTo(b.runs));
    final t = team(inn.battingTeam);
    final sb = StringBuffer();
    if (inn.number == 0) {
      sb.write(hi
          ? '$t ने ${inn.overs} ओवर में ${inn.runs}/${inn.wickets} बनाए।'
          : '$t made ${inn.runs}/${inn.wickets} in ${inn.overs} overs.');
    } else {
      final target = st.innings[0].runs + 1;
      sb.write(hi
          ? '$target रन का पीछा करते हुए $t ने ${inn.overs} ओवर में ${inn.runs}/${inn.wickets} बनाए।'
          : 'Chasing $target, $t finished on ${inn.runs}/${inn.wickets} in ${inn.overs} overs.');
    }
    if (bt.isNotEmpty && bt.first.runs > 0) {
      final c = bt.first;
      sb.write(hi
          ? ' सबसे ज़्यादा रन ${name(c.id)} ने बनाए: ${c.runs}${star(c)} (${c.balls} गेंद, ${c.fours} चौके, ${c.sixes} छक्के)।'
          : ' ${name(c.id)} top-scored with ${c.runs}${star(c)} off ${c.balls} balls (${c.fours} fours, ${c.sixes} sixes).');
    }
    if (bw.isNotEmpty && bw.first.wickets > 0) {
      final c = bw.first;
      sb.write(hi
          ? ' गेंदबाज़ी में ${name(c.id)} ने ${c.runs} रन देकर ${c.wickets} विकेट लिए।'
          : ' ${name(c.id)} took ${c.wickets} for ${c.runs}.');
    }
    paras.add(sb.toString());
  }
  if (!r.tie && !r.noResult && r.winner != null) {
    final margin = r.byRuns
        ? (hi ? '${r.margin} रन' : '${r.margin} ${r.margin == 1 ? 'run' : 'runs'}')
        : (hi ? '${r.margin} विकेट' : '${r.margin} ${r.margin == 1 ? 'wicket' : 'wickets'}');
    paras.add(hi ? '${team(r.winner!)} ने मैच $margin से जीता।' : '${team(r.winner!)} won by $margin.');
  }

  final sixes = bats.fold<int>(0, (a, b) => a + b.card.sixes);
  return MatchReport(
    headline: headline,
    paragraphs: paras,
    topScore: topBat == null ? '-' : '${topBat.card.runs}${star(topBat.card)}',
    bestBowling: topBowl == null ? '-' : '${topBowl.card.wickets}/${topBowl.card.runs}',
    sixes: sixes,
  );
}
