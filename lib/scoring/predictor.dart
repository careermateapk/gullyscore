// A simple, explainable win-chance estimate for the team chasing.
// It is shown "for fun only" in the app. Pure Dart.
import 'dart:math' as math;

import 'engine.dart';

class WinChance {
  WinChance(this.chasingTeam, this.chasingPercent);
  final int chasingTeam;
  final int chasingPercent; // 0-100

  int get defendingPercent => 100 - chasingPercent;
}

/// Returns null when there is no chase going on yet.
WinChance? winChance(MatchState m) {
  if (m.innings.length < 2) return null;
  final first = m.innings[0];
  final chase = m.innings[1];
  final team = chase.battingTeam;
  final r = m.result;
  if (r != null) {
    if (r.tie || r.noResult || r.winner == null) return WinChance(team, 50);
    return WinChance(team, r.winner == team ? 100 : 0);
  }
  final need = (first.runs + 1) - chase.runs;
  final balls = m.setup.overs * 6 - chase.legalBalls;
  final squad = m.setup.players(team).length;
  final wicketsLeft = squad - 1 - chase.wickets;
  if (need <= 0) return WinChance(team, 100);
  if (balls <= 0 || wicketsLeft <= 0) return WinChance(team, 0);

  // Par scoring rate taken from the first innings, at least 5 an over.
  final totalBalls = m.setup.overs * 6;
  final par = math.max(5.0, first.runs * 6 / math.max(1, totalBalls));
  final wicketFactor = 0.35 + 0.65 * (wicketsLeft / math.max(1, squad - 1));
  final expected = par * balls / 6 * wicketFactor;
  final spread = math.sqrt(need) * 1.6 + 4;
  final p = 1 / (1 + math.exp(-(expected - need) / spread));
  final pct = (p * 100).round().clamp(2, 98);
  return WinChance(team, pct);
}
