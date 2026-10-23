import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/app/strings.dart';
import 'package:gullyscore/scoring/badges.dart';
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
    used.addAll(['open', 'women', 'u17', 'u14'].map((k) => 'cat_$k'));
    for (final f in ['league', 'groups', 'knockout']) {
      used.addAll(['fmt_$f', 'fmt_${f}_body']);
    }
    used.add('bracket');
    used.addAll(['khata_expense_sub', 'khata_payment_sub', 'who_spent', 'who_paid', 'all_paid', 'coming', 'not_coming', 'no_reply', 'maybe']);
    used.addAll(['title', 'six', 'potm', 'other'].map((k) => 'sponsor_$k'));
    used.addAll(['turf', 'matting', 'cement', 'mud'].map((k) => 'pitch_$k'));
    used.addAll(['all', 'turf', 'lights', 'cheap'].map((k) => 'gq_$k'));
    used.addAll(['distance', 'rating', 'matches', 'fee', 'name'].map((k) => 'gsort_$k'));
    used.addAll(['about', 'photos', 'reviews', 'matches', 'tournaments', 'insights'].map((k) => 'gtab_$k'));
    used.addAll(['lights', 'washrooms', 'water', 'nets', 'umpires', 'scorers', 'parking', 'pavilion', 'cafeteria', 'sightscreen', 'balls'].map((k) => 'fac_$k'));
    used.addAll(['pitch_astroturf', 'sort_by', 'pitch_type', 'facilities', 'max_fee', 'address', 'timings', 'other_number', 'ground_location']);
    used.addAll(['photos_up_to', 'boundary_m', 'fee_per_match', 'contact', 'reg_step_place', 'reg_step_photos', 'reg_step_fees']);
    used.addAll(['register_ground', 'edit_ground', 'saved', 'use_my_location_here', 'location_saved', 'next']);
    used.addAll(['notifications_sub', 'notifications_off', 'no_grounds_near', 'no_grounds_found']);
    for (final k in ['s', 'w', 'b', 'f', 'a', 'c']) {
      used.addAll(['push_$k', 'push_${k}_sub']);
    }
    for (final b in badgeDefs) {
      used.addAll(['badge_${b.id}', 'badge_${b.id}_how']);
    }
    used.addAll(['players', 'opponent', 'poll', 'tournament', 'general'].map((k) => 'kind_$k'));
    used.addAll(['players', 'opponent', 'poll', 'tournament'].map((k) => 'hint_$k'));
    used.addAll(['sportsmen', 'tough', 'late', 'again'].map((k) => 'tag_$k'));
    used.addAll(['registered', 'joined', 'accept_challenge', 'im_in', 'paid', 'not_paid', 'schedule_match', 'no_live_now', 'no_upcoming']);
    used.addAll(['no_upcoming_body', 'feed_empty_body', 'in_short', 'about_short', 'most_runs', 'most_wickets', 'runs', 'wickets']);
    // v0.9: picture studio, stories, levels and booking
    final st = RegExp(r"\bst\('([a-z0-9_]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in st.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    used.addAll(['midnight', 'royal', 'neon', 'emerald', 'sunset', 'ivory', 'ocean', 'holo', 'gold', 'mint'].map((k) => 'theme_$k'));
    used.addAll(['post', 'story', 'square', 'wide'].map((k) => 'size_$k'));
    used.addAll(['rookie', 'club', 'pro', 'star', 'legend'].map((k) => 'tier_$k'));
    for (final k in ['finisher', 'six_hitter', 'opener', 'all_round', 'wicket_taker', 'safe_hands', 'anchor', 'team_player', 'new']) {
      used.addAll(['persona_$k', 'persona_${k}_line']);
    }
    used.addAll(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((k) => 'day_$k'));
    used.addAll(['requested', 'accepted', 'declined', 'cancelled'].map((k) => 'booking_$k'));
    for (var i = 1; i <= 6; i++) {
      used.addAll(['li_f${i}_t', 'li_f${i}_b']);
    }
    for (var i = 1; i <= 4; i++) {
      used.addAll(['li_s${i}_t', 'li_s${i}_b', 'li_n${i}_t', 'li_n${i}_b']);
    }
    for (var i = 1; i <= 8; i++) {
      used.addAll(['li_q$i', 'li_a$i']);
    }
    used.addAll(['batter', 'bowler', 'all_rounder', 'wicket_keeper', 'fast', 'medium', 'off_spin', 'leg_spin', 'left_arm_spin', 'none'].map((k) => 'role_$k'));
    for (final k in ['score', 'live', 'grounds', 'card']) {
      used.addAll(['kicker', 'a', 'b', 'body'].map((x) => 'intro_${k}_$x'));
    }
    used.addAll(['morning', 'day', 'afternoon', 'night'].map((k) => 'slot_$k'));
    used.addAll(['no_slots', 'no_slots_body', 'no_slots_owner', 'no_incoming_bookings', 'no_incoming_bookings_body', 'no_bookings', 'no_bookings_body', 'gtab_book']);
    used.addAll(['xp_match', 'xp_run', 'xp_wicket', 'xp_catch', 'xp_fifty', 'xp_hundred', 'xp_potm']);
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
