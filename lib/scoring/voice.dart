// Voice scoring: turns what the scorer says ("chauka cover drive", "wide",
// "bowled", "do run") into a ball. Hindi (Devanagari or Roman) and English.
// Pure Dart so it is unit tested.
import 'commentary.dart';
import 'engine.dart';

class VoiceCall {
  VoiceCall({this.kind = BallKind.normal, this.runs = 0, this.out, this.zone, this.shot, this.needsWicketDetails = false});
  final String kind;
  final int runs;
  final String? out; // OutKind, when a wicket was said
  final String? zone;
  final String? shot;
  final bool needsWicketDetails; // "out" / "caught" / "run out": ask who and how

  bool get isWicket => out != null || needsWicketDetails;

  /// Event fields for the scoring engine (without 't').
  Map<String, dynamic> toEvent(String striker) => {
        'kind': kind,
        'runs': runs,
        if (out != null) 'out': {'kind': out, 'player': striker},
        if (zone != null) 'zone': zone,
        if (shot != null) 'shot': shot,
        if (zone != null) 'ang': Zone.all.indexOf(zone!) * 45.0 + 22.5,
        if (zone != null) 'dist': (runs == 4 || runs == 6) ? 1.0 : 0.6,
      };
}

const _words = <String, List<String>>{
  // extras (checked first)
  'legbye': ['leg bye', 'leg by', 'legbye', 'लेग बाई', 'लेग बाय', 'लेगबाई'],
  'noball': ['no ball', 'noball', 'no-ball', 'नो बॉल', 'नोबॉल', 'नो बोल'],
  'wide': ['wide', 'white', 'वाइड', 'वाईड', 'wyd'],
  'bye': ['bye', 'by run', 'बाई', 'बाय'],
  // wickets
  'out:${OutKind.bowled}': ['bowled', 'bold', 'बोल्ड', 'क्लीन बोल्ड'],
  'out:${OutKind.lbw}': ['lbw', 'l b w', 'एलबीडब्ल्यू', 'एल बी डब्ल्यू', 'leg before'],
  'out:${OutKind.hitWicket}': ['hit wicket', 'हिट विकेट'],
  'ask:${OutKind.caught}': ['caught', 'catch', 'कैच', 'केच', 'लपका'],
  'ask:${OutKind.runOut}': ['run out', 'runout', 'रन आउट', 'रनआउट'],
  'ask:${OutKind.stumped}': ['stumped', 'stumping', 'stump', 'स्टंप', 'स्टम्प'],
  'ask:out': ['out', 'wicket', 'आउट', 'विकेट', 'wicket gira'],
  // runs
  '6': ['six', 'sixer', 'chakka', 'chhakka', 'chakkaa', 'छक्का', 'छक्के', 'सिक्स', 'छह', 'छः', 'cheh'],
  '4': ['four', 'chauka', 'chowka', 'chouka', 'boundary', 'चौका', 'चौके', 'फोर', 'चार', 'char'],
  '5': ['five', 'paanch', 'panch', 'पांच', 'पाँच'],
  '3': ['three', 'teen', 'तीन', 'थ्री'],
  '2': ['two', 'double', 'do run', 'दो', 'डबल', 'टू'],
  '1': ['one', 'single', 'ek', 'एक', 'सिंगल', 'वन'],
  '0': ['dot', 'no run', 'zero', 'khali', 'खाली', 'डॉट', 'शून्य', 'कोई रन नहीं', 'जीरो', 'ज़ीरो'],
};

const _zones = <String, List<String>>{
  Zone.thirdMan: ['third man', 'थर्ड मैन'],
  Zone.fineLeg: ['fine leg', 'फाइन लेग', 'फ़ाइन लेग'],
  Zone.squareLeg: ['square leg', 'स्क्वायर लेग', 'स्क्वेयर लेग'],
  Zone.midWicket: ['mid wicket', 'midwicket', 'मिड विकेट', 'मिडविकेट'],
  Zone.longOn: ['long on', 'लॉन्ग ऑन', 'लोंग ऑन', 'straight', 'सीधा', 'सीधे'],
  Zone.longOff: ['long off', 'लॉन्ग ऑफ', 'लोंग ऑफ'],
  Zone.cover: ['cover', 'covers', 'कवर'],
  Zone.point: ['point', 'पॉइंट', 'पॉइन्ट'],
};

const _shots = <String, List<String>>{
  'drive': ['drive', 'ड्राइव'],
  'cut': ['cut', 'कट'],
  'pull': ['pull', 'पुल'],
  'sweep': ['sweep', 'स्वीप'],
  'loft': ['loft', 'lofted', 'उठाकर', 'हवा में'],
  'edge': ['edge', 'nick', 'एज'],
};

String _clean(String s) => ' ${s.toLowerCase().replaceAll(RegExp(r'[.,!?।]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

/// Finds [w] as a whole word (or phrase) in the padded text.
bool _has(String text, String w) {
  if (RegExp(r'^[a-z0-9 \-]+$').hasMatch(w)) return text.contains(' $w ');
  return text.contains(w); // Devanagari: no reliable word edges
}

String _remove(String text, String w) => RegExp(r'^[a-z0-9 \-]+$').hasMatch(w) ? text.replaceAll(' $w ', ' ') : text.replaceAll(w, ' ');

/// What the scorer said, as a ball. Null when nothing cricket-like was heard.
VoiceCall? parseVoice(String said) {
  var t = _clean(said);
  if (t.trim().isEmpty) return null;
  String? zone, shot;
  for (final e in _zones.entries) {
    for (final w in e.value) {
      if (_has(t, w)) {
        zone ??= e.key;
        t = _remove(t, w);
      }
    }
  }
  for (final e in _shots.entries) {
    for (final w in e.value) {
      if (_has(t, w)) {
        shot ??= e.key;
        t = _remove(t, w);
      }
    }
  }
  var kind = BallKind.normal;
  String? out;
  var ask = false;
  int? runs;
  // Bare digits ("wide 2", "4") count as runs.
  final digit = RegExp(r'(?:^| )([0-6])(?= )').firstMatch(t);
  for (final e in _words.entries) {
    for (final w in e.value) {
      if (!_has(t, w)) continue;
      final k = e.key;
      if (k == 'legbye') {
        kind = BallKind.legBye;
      } else if (k == 'noball') {
        kind = BallKind.noBall;
      } else if (k == 'wide') {
        kind = BallKind.wide;
      } else if (k == 'bye') {
        if (kind == BallKind.normal) kind = BallKind.bye;
      } else if (k.startsWith('out:')) {
        out ??= k.substring(4);
      } else if (k.startsWith('ask:')) {
        if (out == null) ask = true;
      } else {
        runs ??= int.parse(k);
      }
      t = _remove(t, w);
      break;
    }
  }
  if (runs == null && digit != null) runs = int.parse(digit.group(1)!);
  if (out != null) ask = false;
  final heard = kind != BallKind.normal || out != null || ask || runs != null;
  if (!heard) return null;
  // Byes and leg byes without a number mean one run.
  if ((kind == BallKind.bye || kind == BallKind.legBye) && (runs == null || runs == 0)) runs = 1;
  final r = (runs ?? 0).clamp(0, 6);
  return VoiceCall(
    kind: out != null ? BallKind.normal : kind,
    runs: out != null ? 0 : r,
    out: out,
    zone: out != null || ask ? null : (r > 0 ? zone : null),
    shot: out != null || ask ? null : (r > 0 ? shot : null),
    needsWicketDetails: ask,
  );
}
