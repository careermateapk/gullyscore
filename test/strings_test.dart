import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/app/strings.dart';
import 'package:gullyscore/ui/screens/help.dart';

void main() {
  test('every text key used in the code exists in English and Hindi', () {
    final used = <String>{};
    final re = RegExp(r"tr\('([a-z0-9_]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    // Keys built at run time.
    used.addAll(['toss_bat', 'toss_bowl', 'balls_n', 'runs_n']);
    used.addAll([for (var i = 1; i <= 5; i++) 'privacy_$i']);
    used.addAll(['bowled', 'caught', 'lbw', 'run_out', 'stumped', 'hit_wicket', 'retired'].map((k) => 'out_$k'));
    used.addAll(['all', 'teams', 'players', 'matches'].map((k) => 'search_$k'));
    used.addAll(['all', 'boundaries', 'wickets', 'overs'].map((k) => 'filter_$k'));
    used.addAll(['scoring', 'sharing', 'data', 'other'].map((k) => 'faq_cat_$k'));
    for (final f in faqs) {
      used.add('faq_${f.id}_q');
      used.add('faq_${f.id}_a');
    }

    final missingEn = used.where((k) => !Strings.en.containsKey(k)).toList()..sort();
    final missingHi = used.where((k) => !Strings.hi.containsKey(k)).toList()..sort();
    expect(missingEn, isEmpty, reason: 'English missing');
    expect(missingHi, isEmpty, reason: 'Hindi missing');
  });

  test('both languages use the same {placeholders}', () {
    final ph = RegExp(r'\{[a-z]+\}');
    for (final k in Strings.en.keys) {
      final en = ph.allMatches(Strings.en[k]!).map((m) => m.group(0)).toSet();
      final hi = ph.allMatches(Strings.hi[k] ?? '').map((m) => m.group(0)).toSet();
      expect(hi, en, reason: k);
    }
  });
}
