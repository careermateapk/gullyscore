// Builds ball-by-ball commentary from what the scorer entered.
// Nothing is guessed: the line only mentions direction or shot when the
// scorer tapped them. Pure Dart so it can be unit tested.
import 'engine.dart';

/// Fielding zones, clockwise from straight past the bowler, for a right-hander.
class Zone {
  static const longOff = 'long_off';
  static const cover = 'cover';
  static const point = 'point';
  static const thirdMan = 'third_man';
  static const fineLeg = 'fine_leg';
  static const squareLeg = 'square_leg';
  static const midWicket = 'mid_wicket';
  static const longOn = 'long_on';

  /// In order of their start angle (each zone is 45 degrees wide).
  static const all = [longOff, cover, point, thirdMan, fineLeg, squareLeg, midWicket, longOn];

  static const offSide = {longOff, cover, point, thirdMan};

  /// Zone for an angle in a right-hander's frame (0 = straight, clockwise).
  static String fromAngle(double angle) {
    final a = ((angle % 360) + 360) % 360;
    return all[(a ~/ 45).clamp(0, 7)];
  }

  static String name(String zone, String lang) {
    final en = {
      longOff: 'Long-off',
      cover: 'Cover',
      point: 'Point',
      thirdMan: 'Third man',
      fineLeg: 'Fine leg',
      squareLeg: 'Square leg',
      midWicket: 'Mid-wicket',
      longOn: 'Long-on',
    };
    final hi = {
      longOff: 'लॉन्ग-ऑफ़',
      cover: 'कवर',
      point: 'पॉइंट',
      thirdMan: 'थर्ड मैन',
      fineLeg: 'फ़ाइन लेग',
      squareLeg: 'स्क्वेयर लेग',
      midWicket: 'मिड-विकेट',
      longOn: 'लॉन्ग-ऑन',
    };
    return (lang == 'hi' ? hi : en)[zone] ?? zone;
  }
}

class Shot {
  static const all = ['drive', 'cut', 'pull', 'sweep', 'loft', 'edge', 'defend'];

  static String name(String shot, String lang) {
    const en = {
      'drive': 'Drive',
      'cut': 'Cut',
      'pull': 'Pull',
      'sweep': 'Sweep',
      'loft': 'Loft',
      'edge': 'Edge',
      'defend': 'Defend',
    };
    const hi = {
      'drive': 'ड्राइव',
      'cut': 'कट',
      'pull': 'पुल',
      'sweep': 'स्वीप',
      'loft': 'हवाई शॉट',
      'edge': 'किनारा',
      'defend': 'डिफ़ेंस',
    };
    return (lang == 'hi' ? hi : en)[shot] ?? shot;
  }
}

enum CommType { ball, overEnd }

class CommItem {
  CommItem.ball(this.ball, this.headline, this.detail)
      : type = CommType.ball,
        overNumber = null,
        overRuns = 0,
        overBalls = const [],
        scoreText = '';

  CommItem.overEnd(this.overNumber, this.overRuns, this.overBalls, this.scoreText, this.headline)
      : type = CommType.overEnd,
        ball = null,
        detail = '';

  final CommType type;
  final BallLog? ball;
  final String headline; // bold part
  final String detail; // normal part (may be empty)
  final int? overNumber; // 1-based, for overEnd
  final int overRuns;
  final List<String> overBalls;
  final String scoreText;
}

String _zonePhrase(String zone, bool six, String lang) {
  final z = Zone.name(zone, lang);
  if (lang == 'hi') return six ? '$z के ऊपर से' : '$z की तरफ़';
  if (six) return 'over ${z.toLowerCase()}';
  switch (zone) {
    case Zone.cover:
      return 'through the covers';
    case Zone.point:
      return 'past point';
    case Zone.thirdMan:
      return 'down to third man';
    case Zone.fineLeg:
      return 'fine down the leg side';
    case Zone.longOff:
      return 'down the ground to long-off';
    case Zone.longOn:
      return 'down the ground to long-on';
    default:
      return 'to ${z.toLowerCase()}';
  }
}

String _shotVerb(String shot) {
  const verbs = {
    'drive': 'Driven',
    'cut': 'Cut',
    'pull': 'Pulled',
    'sweep': 'Swept',
    'loft': 'Lofted',
    'edge': 'Edged',
    'defend': 'Pushed',
  };
  return verbs[shot] ?? 'Played';
}

String _result(BallLog b, String lang) {
  final hi = lang == 'hi';
  final r = b.runs;
  String runsWord(int n) => hi ? '$n रन' : (n == 1 ? '1 run' : '$n runs');
  switch (b.kind) {
    case BallKind.wide:
      if (hi) return r == 0 ? 'वाइड' : 'वाइड, ${r + 1} रन';
      return r == 0 ? 'wide' : 'wide, ${r + 1} runs';
    case BallKind.noBall:
      if (r == 4) return hi ? 'नो बॉल, चौका!' : 'no ball, FOUR';
      if (r == 6) return hi ? 'नो बॉल, छक्का!' : 'no ball, SIX';
      if (hi) return r == 0 ? 'नो बॉल' : 'नो बॉल, ${runsWord(r)}';
      return r == 0 ? 'no ball' : 'no ball, ${runsWord(r)}';
    case BallKind.bye:
      return hi ? '$r बाई' : (r == 1 ? '1 bye' : '$r byes');
    case BallKind.legBye:
      return hi ? '$r लेग बाई' : (r == 1 ? '1 leg bye' : '$r leg byes');
  }
  if (r == 4) return hi ? 'चौका!' : 'FOUR';
  if (r == 6) return hi ? 'छक्का!' : 'SIX';
  if (r == 0) return hi ? 'कोई रन नहीं' : 'no run';
  return runsWord(r);
}

String _howOut(BallLog b, String Function(String) name, String lang) {
  final f = b.fielder == null ? '' : name(b.fielder!);
  final hi = lang == 'hi';
  switch (b.outKind) {
    case OutKind.caught:
      if (f.isEmpty) return hi ? 'कैच आउट' : 'caught';
      if (b.fielder == b.bowler) return hi ? 'गेंदबाज़ ने ख़ुद कैच पकड़ा' : 'caught and bowled';
      return hi ? '$f ने कैच पकड़ा' : 'caught by $f';
    case OutKind.bowled:
      return hi ? 'बोल्ड' : 'bowled';
    case OutKind.lbw:
      return hi ? 'एलबीडब्ल्यू' : 'lbw';
    case OutKind.runOut:
      return f.isEmpty ? (hi ? 'रन आउट' : 'run out') : (hi ? '$f ने रन आउट किया' : 'run out by $f');
    case OutKind.stumped:
      return f.isEmpty ? (hi ? 'स्टंप आउट' : 'stumped') : (hi ? '$f ने स्टंप किया' : 'stumped by $f');
    case OutKind.hitWicket:
      return hi ? 'हिट विकेट' : 'hit wicket';
    case OutKind.retired:
      return hi ? 'रिटायर्ड' : 'retired';
  }
  return hi ? 'आउट' : 'out';
}

/// The line a scorer will see before saving a ball (no wicket).
CommItem previewCommentary({
  required String bowler,
  required String striker,
  required String kind,
  required int runs,
  String? zone,
  String? shot,
  String lang = 'en',
}) {
  final b = BallLog('', true, 0, striker: 's', bowler: 'b', kind: kind, runs: runs, zone: zone, shot: shot);
  final names = {'s': striker, 'b': bowler};
  final inn = Innings(0, 0)..balls.add(b);
  return buildCommentary(inn, (id) => names[id] ?? id, lang: lang).last;
}

/// Commentary for one innings, newest first.
List<CommItem> buildCommentary(Innings inn, String Function(String id) name, {String lang = 'en'}) {
  final hi = lang == 'hi';
  final items = <CommItem>[];
  final batRuns = <String, int>{};
  final batBalls = <String, int>{};
  var overRuns = 0;
  var overLabels = <String>[];

  for (final b in inn.balls) {
    // Running batter score (for "Name 12 (9)" on a wicket).
    if (b.kind == BallKind.normal || b.kind == BallKind.noBall) {
      batRuns[b.striker] = (batRuns[b.striker] ?? 0) + b.runs;
    }
    if (b.kind != BallKind.wide) batBalls[b.striker] = (batBalls[b.striker] ?? 0) + 1;

    final head = StringBuffer(hi
        ? '${name(b.bowler)} से ${name(b.striker)}, ${_result(b, lang)}'
        : '${name(b.bowler)} to ${name(b.striker)}, ${_result(b, lang)}');
    final detail = StringBuffer();

    if (b.isWicket || b.outKind == OutKind.retired) {
      final who = b.outPlayer ?? b.striker;
      head
        ..clear()
        ..write(hi
            ? '${name(b.bowler)} से ${name(who)}, आउट!'
            : '${name(b.bowler)} to ${name(who)}, OUT');
      final r = batRuns[who] ?? 0;
      final bl = batBalls[who] ?? 0;
      detail.write(hi
          ? '${_howOut(b, name, lang)}। ${name(who)} $r ($bl)।'
          : '${_capital(_howOut(b, name, lang))}. ${name(who)} $r ($bl).');
    } else if (b.zone != null || b.shot != null) {
      if (hi) {
        final parts = <String>[
          if (b.shot != null) Shot.name(b.shot!, lang),
          if (b.zone != null) _zonePhrase(b.zone!, b.isSix, lang),
        ];
        detail.write('${parts.join(', ')}।');
      } else {
        final verb = b.shot != null ? _shotVerb(b.shot!) : 'Hit';
        detail.write(b.zone != null ? '$verb ${_zonePhrase(b.zone!, b.isSix, lang)}.' : '$verb.');
      }
    }
    items.add(CommItem.ball(b, hi ? head.toString() : '$head.', detail.toString()));

    overRuns += b.teamRuns;
    overLabels.add(b.label);
    if (b.legal && b.ballInOver == 6) {
      final n = b.over + 1;
      items.add(CommItem.overEnd(
        n,
        overRuns,
        overLabels,
        '${b.scoreRuns}/${b.scoreWickets}',
        hi ? 'ओवर $n ख़त्म · $overRuns रन' : 'End of over $n · $overRuns ${overRuns == 1 ? 'run' : 'runs'}',
      ));
      overRuns = 0;
      overLabels = <String>[];
    }
  }
  return items.reversed.toList();
}

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Runs scored in each zone by one batter (for the wagon wheel).
Map<String, int> zoneRuns(Iterable<BallLog> balls, String batterId) {
  final out = <String, int>{};
  for (final b in balls) {
    if (b.striker != batterId || b.zone == null) continue;
    if (b.kind != BallKind.normal && b.kind != BallKind.noBall) continue;
    out[b.zone!] = (out[b.zone!] ?? 0) + b.runs;
  }
  return out;
}
