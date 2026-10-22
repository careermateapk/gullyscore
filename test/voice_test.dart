import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/scoring/commentary.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/voice.dart';

void main() {
  test('runs in English, Hinglish and Hindi', () {
    expect(parseVoice('four')!.runs, 4);
    expect(parseVoice('Chauka, cover drive')!.runs, 4);
    expect(parseVoice('चौका')!.runs, 4);
    expect(parseVoice('छक्का')!.runs, 6);
    expect(parseVoice('chhakka')!.runs, 6);
    expect(parseVoice('ek run')!.runs, 1);
    expect(parseVoice('दो रन')!.runs, 2);
    expect(parseVoice('teen')!.runs, 3);
    expect(parseVoice('dot ball')!.runs, 0);
    expect(parseVoice('खाली')!.runs, 0);
    expect(parseVoice('3')!.runs, 3);
  });

  test('direction and shot are kept for runs', () {
    final c = parseVoice('chauka cover drive')!;
    expect(c.zone, Zone.cover);
    expect(c.shot, 'drive');
    final e = c.toEvent('s1');
    expect(e['zone'], Zone.cover);
    expect(e['dist'], 1.0);
    expect(parseVoice('single square leg')!.zone, Zone.squareLeg);
    expect(parseVoice('dot')!.zone, isNull);
  });

  test('extras', () {
    expect(parseVoice('wide')!.kind, BallKind.wide);
    expect(parseVoice('wide')!.runs, 0);
    final w = parseVoice('wide and four')!;
    expect(w.kind, BallKind.wide);
    expect(w.runs, 4);
    expect(parseVoice('no ball')!.kind, BallKind.noBall);
    expect(parseVoice('नो बॉल छक्का')!.runs, 6);
    expect(parseVoice('leg bye')!.kind, BallKind.legBye);
    expect(parseVoice('leg bye')!.runs, 1);
    expect(parseVoice('bye 2')!.kind, BallKind.bye);
    expect(parseVoice('bye 2')!.runs, 2);
  });

  test('wickets: bowled and lbw go straight in, others ask who', () {
    final b = parseVoice('clean bowled')!;
    expect(b.out, OutKind.bowled);
    expect(b.needsWicketDetails, false);
    expect(b.toEvent('s1')['out'], {'kind': OutKind.bowled, 'player': 's1'});
    expect(parseVoice('बोल्ड')!.out, OutKind.bowled);
    expect(parseVoice('LBW')!.out, OutKind.lbw);
    expect(parseVoice('catch out')!.needsWicketDetails, true);
    expect(parseVoice('run out')!.needsWicketDetails, true);
    expect(parseVoice('आउट')!.needsWicketDetails, true);
    expect(parseVoice('run out')!.isWicket, true);
  });

  test('nothing cricket-like', () {
    expect(parseVoice(''), isNull);
    expect(parseVoice('hello bhai'), isNull);
  });
}
