import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/app/scope.dart';
import 'package:gullyscore/app/settings.dart';
import 'package:gullyscore/app/theme.dart';
import 'package:gullyscore/data/backup.dart';
import 'package:gullyscore/data/cloud.dart';
import 'package:gullyscore/data/sync.dart';
import 'package:gullyscore/data/models.dart';
import 'package:gullyscore/data/repository.dart';
import 'package:gullyscore/main.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/scoring/tournament.dart';
import 'package:gullyscore/ui/screens/help.dart';
import 'package:gullyscore/ui/screens/match_centre_screen.dart';
import 'package:gullyscore/ui/screens/new_match_screen.dart';
import 'package:gullyscore/ui/screens/news_screen.dart';
import 'package:gullyscore/ui/screens/onboarding_screen.dart';
import 'package:gullyscore/ui/screens/player_screen.dart';
import 'package:gullyscore/ui/screens/search_screen.dart';
import 'package:gullyscore/ui/screens/team_screen.dart';
import 'package:gullyscore/ui/screens/tournament_screens.dart';
import 'package:gullyscore/ui/screens/scoring_screen.dart';
import 'package:gullyscore/ui/screens/app_drawer.dart';
import 'package:gullyscore/ui/screens/badges_screen.dart';
import 'package:gullyscore/ui/screens/team_tools.dart';
import 'package:gullyscore/ui/screens/grounds_screen.dart';
import 'package:gullyscore/ui/screens/ground_detail_screen.dart';
import 'package:gullyscore/ui/screens/register_ground_screen.dart';
import 'package:gullyscore/data/social.dart';
import 'package:gullyscore/app/strings.dart';
import 'package:gullyscore/ui/screens/notifications_screen.dart';
import 'package:gullyscore/data/push.dart';
import 'package:gullyscore/scoring/badges.dart';
import 'package:gullyscore/ui/screens/community_screen.dart';
import 'package:gullyscore/ui/screens/info_screens.dart';
import 'package:gullyscore/ui/screens/leaderboard_screen.dart';
import 'package:gullyscore/ui/screens/matches_screen.dart';
import 'package:gullyscore/ui/screens/my_cricket_screen.dart';
import 'package:gullyscore/ui/screens/ratings_screens.dart';
import 'package:gullyscore/ui/screens/series_screen.dart';
import 'package:gullyscore/ui/screens/insights_screens.dart';
import 'package:gullyscore/ui/screens/booking_screens.dart';
import 'package:gullyscore/ui/screens/auth_screen.dart';
import 'package:gullyscore/ui/screens/live_stream_screen.dart';
import 'package:gullyscore/live/live_engine.dart';
import 'package:gullyscore/live/highlights.dart';
import 'dart:io';
import 'package:gullyscore/studio/share_entry.dart';
import 'package:gullyscore/studio/stories.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_fakes.dart';

Future<(Settings, Repository)> setUpApp({bool onboarded = true, bool reduceMotion = true}) async {
  SharedPreferences.setMockInitialValues({'onboarded': onboarded, 'reduceMotion': reduceMotion, 'askShot': false, 'tourDone': true});
  final s = Settings();
  await s.load();
  final r = Repository(store: MemoryStore());
  await r.load();
  return (s, r);
}

Widget wrap(Settings s, Repository r, Widget child, {ThemeMode mode = ThemeMode.dark}) => ListenableBuilder(
      listenable: s,
      builder: (context, _) => AppScope(
        repo: r,
        settings: s,
        sync: SyncService(r, HttpCloud('')),
        rev: s.rev,
        child: MaterialApp(
          theme: buildTheme(Palette.lightP),
          darkTheme: buildTheme(Palette.darkP),
          themeMode: mode,
          home: child,
        ),
      ),
    );

String seedMatch(Repository r, {int overs = 2}) {
  final a = r.addTeam('Rajnagar XI', playerNames: ['Ravi', 'Raju', 'Rohit']);
  final b = r.addTeam('Madhubani Strikers', playerNames: ['Sanjay', 'Vikas', 'Amit']);
  return r.createMatch(a: a, b: b, playersA: a.playerIds, playersB: b.playerIds, overs: overs, firstBatting: 0, title: 'MPL 2026').id;
}

String seedFinished(Repository r) {
  final a = r.addTeam('Sakri Kings', playerNames: ['Kishan', 'Karan', 'Kamal']);
  final b = r.addTeam('Darbhanga Tigers', playerNames: ['Deepak', 'Dinesh', 'Dev']);
  final m = r.createMatch(a: a, b: b, playersA: a.playerIds, playersB: b.playerIds, overs: 1, firstBatting: 0, title: 'MPL 2026');
  r.addEvent(m, {'t': Ev.start, 'striker': a.playerIds[0], 'nonStriker': a.playerIds[1], 'bowler': b.playerIds[0]});
  for (var i = 0; i < 6; i++) {
    r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 1});
  }
  r.addEvent(m, {'t': Ev.start, 'striker': b.playerIds[0], 'nonStriker': b.playerIds[1], 'bowler': a.playerIds[0]});
  r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 6, 'zone': 'long_on', 'ang': 330.0, 'dist': 1.0});
  r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 6});
  return m.id;
}

final _errors = <FlutterErrorDetails>[];
void Function(FlutterErrorDetails)? _savedOnError;

/// Fails with the full error (including which widget) if anything went wrong.
void check(WidgetTester tester, String where) {
  if (_errors.isNotEmpty) {
    final msg = _errors.map((d) => d.toString()).join('\n');
    _errors.clear();
    FlutterError.onError = _savedOnError; // must be restored before failing
    fail('$where\n$msg');
  }
}

void main() {
  liveEngine = FakeLiveEngine();
  HighlightStore.root = () async => Directory.systemTemp.createTempSync('gs_live');
  testWidgets('first launch shows onboarding, then the empty home', (tester) async {
    final (s, r) = await setUpApp(onboarded: false);
    await tester.pumpWidget(GullyScoreApp(settings: s, repo: r));
    await tester.pumpAndSettle();
    expect(find.text('EVERY BALL.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Score your first match'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('My Cricket'), findsOneWidget);
  });

  testWidgets('no dashboard without login; Google needs sign up first; sign up works', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'reduceMotion': true, 'askShot': false, 'tourDone': true});
    final s = Settings();
    await s.load();
    final r = Repository(store: MemoryStore());
    await r.load();
    final sent = <String, Object?>{};
    Future<Map<String, dynamic>> send(String method, String path, {Object? body, String? auth}) async {
      if (path.startsWith('/v1/auth/')) {
        final b = body as Map<String, dynamic>;
        sent[path] = b;
        if (path == '/v1/auth/google' && b['mode'] == 'login') throw CloudError(404, 'not signed up');
        return {...meJson, 'token': 'Unew'};
      }
      return fakeSend(method, path, body: body, auth: auth);
    }

    final sync = SyncService(r, OnlineCloud(), google: NoGoogle(), socialSender: send);
    await sync.start(timers: false);
    _savedOnError = FlutterError.onError;
    FlutterError.onError = (d) => _errors.add(d);
    await tester.pumpWidget(GullyScoreApp(settings: s, repo: r, sync: sync));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Community'), findsNothing);

    // Google without an account → warning.
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('No account for this Gmail'), findsOneWidget);
    await tester.tap(find.text('Sign up now'));
    await tester.pumpAndSettle();

    Future<void> type(String label, String v) async {
      final f = find.widgetWithText(TextField, label).first;
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.enterText(f, v);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await type('Full name', 'Suraj Kumar');
    await type('Mobile number', '9876543210');
    await type('Email', 'suraj@example.com');
    await type('Password', 'abc');
    expect(find.textContaining('Weak'), findsOneWidget);
    await type('Password', 'Gully2024!');
    expect(find.textContaining('Strong'), findsOneWidget);
    await type('Re-enter password', 'Gully2024!');
    expect(find.textContaining('Match'), findsWidgets);
    await tap(find.text('State'));
    await tester.tap(find.text('Bihar'));
    await tester.pumpAndSettle();
    await tap(find.text('City'));
    await tester.tap(find.text('Madhubani'));
    await tester.pumpAndSettle();

    // Not agreed yet → blocked.
    await tap(find.text('Create account'));
    expect(sent.containsKey('/v1/auth/signup'), false);
    expect(find.textContaining('Please accept'), findsWidgets);

    await tap(find.byType(Checkbox));
    await tap(find.text('Create account'));
    final b = sent['/v1/auth/signup'] as Map<String, dynamic>;
    expect(b['state'], 'Bihar');
    expect(b['city'], 'Madhubani');
    expect(b['countryCode'], '+91');
    expect(b['agree'], true);
    expect(sync.loggedIn, true);
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.text('Community'), findsOneWidget);

    // Logging out brings the login screen back.
    await sync.logout();
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    FlutterError.onError = _savedOnError;
    check(tester, 'login flow');
  });

  testWidgets('logging in plays the welcome, then opens home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'reduceMotion': false, 'askShot': false, 'tourDone': true});
    final s = Settings();
    await s.load();
    final r = Repository(store: MemoryStore());
    await r.load();
    Future<Map<String, dynamic>> send(String method, String path, {Object? body, String? auth}) async {
      if (path == '/v1/auth/login') return {...meJson, 'token': 'Unew'};
      return fakeSend(method, path, body: body, auth: auth);
    }

    final sync = SyncService(r, OnlineCloud(), google: NoGoogle(), socialSender: send);
    await sync.start(timers: false);
    await tester.pumpWidget(GullyScoreApp(settings: s, repo: r, sync: sync));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'suraj@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Gully2024!');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Log in').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Log in').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sync.loggedIn, true);
    expect(find.byType(AuthScreen), findsOneWidget); // still celebrating
    expect(find.textContaining('Good to see you again'), findsOneWidget);
    expect(find.textContaining('SURAJ!'), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.text('Community'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('first time on home: the app tour runs once, also on a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'reduceMotion': true, 'askShot': false});
    final s = Settings();
    await s.load();
    final r = Repository(store: MemoryStore());
    await r.load();
    _savedOnError = FlutterError.onError;
    FlutterError.onError = _errors.add;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
      child: GullyScoreApp(settings: s, repo: r),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Quick tour?'), findsOneWidget);
    await tester.tap(find.text('Show me →'));
    await tester.pumpAndSettle();
    check(tester, 'tour step 1');
    expect(find.text('STEP 1 OF 6'), findsOneWidget);
    for (var i = 2; i <= 6; i++) {
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();
      check(tester, 'tour step $i');
      expect(find.text('STEP $i OF 6'), findsOneWidget);
    }
    await tester.tap(find.text("Let's play 🏏"));
    await tester.pumpAndSettle();
    expect(find.text('Quick tour?'), findsNothing);
    expect(s.tourDone, true);
    FlutterError.onError = _savedOnError;
    check(tester, 'tour end');
  });

  testWidgets('live stream: set up, open camera, go live, score a four, end', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    final m = r.matches[id]!;
    r.addEvent(m, {'t': Ev.start, 'striker': m.playersA[0], 'nonStriker': m.playersA[1], 'bowler': m.playersB[0]});
    final engine = FakeLiveEngine();
    liveEngine = engine;
    _savedOnError = FlutterError.onError;
    FlutterError.onError = _errors.add;
    await tester.pumpWidget(wrap(s, r, LiveStreamScreen(matchId: id)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Open camera'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    expect(find.text('Paste your YouTube stream key first.'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Stream key'), -200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Stream key'), 'abcd-efgh-ijkl-mnop');
    await tester.enterText(find.widgetWithText(TextField, 'YouTube link for fans (optional)'), 'https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv');
    await tester.scrollUntilVisible(find.text('Open camera'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    check(tester, 'live setup');
    expect(m.stream, 'c:UCabcdefghijklmnopqrstuv');
    // The camera page on a small landscape phone.
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(640, 320), textScaler: TextScaler.linear(1.3)),
      child: wrap(s, r, LiveStreamScreen(key: UniqueKey(), matchId: id)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Stream key'), 'abcd-efgh-ijkl-mnop');
    await tester.scrollUntilVisible(find.text('Open camera'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pump(const Duration(seconds: 7)); // intro graphic goes away
    await tester.pumpAndSettle();
    check(tester, 'camera page');
    if (find.text('Ready').evaluate().isEmpty) {
      FlutterError.onError = _savedOnError;
      await tester.scrollUntilVisible(find.text('Open camera'), 200, scrollable: find.byType(Scrollable).first);
      fail('no Ready: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText()).join(' | ')}');
    }
    await tester.tap(find.byTooltip('Go LIVE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('LIVE  00:'), findsOneWidget);
    expect(engine.calls, containsAll(['prepare', 'start', 'segment']));
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.text('FOUR!'), findsOneWidget);
    check(tester, 'four on the video');
    expect(engine.calls, contains('cut'));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byTooltip('Replay last ball'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('End live'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End live').last);
    await tester.pumpAndSettle();
    expect(engine.calls, contains('stop'));
    check(tester, 'live end');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
    FlutterError.onError = _savedOnError;
    liveEngine = FakeLiveEngine();
  });

  testWidgets('switching to Hindi changes the navigation', (tester) async {
    final (s, r) = await setUpApp();
    await tester.pumpWidget(GullyScoreApp(settings: s, repo: r));
    await tester.pumpAndSettle();
    s.setLang('hi');
    await tester.pumpAndSettle();
    expect(find.text('होम'), findsOneWidget);
    expect(find.text('प्रोफ़ाइल'), findsOneWidget);
  });

  testWidgets('score a few balls, undo, and the score is right', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    await tester.pumpWidget(wrap(s, r, ScoringScreen(matchId: id)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pick openers and bowler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raju'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sanjay'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pad_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pad_4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pad_6')));
    await tester.pumpAndSettle();

    final m = r.matches[id]!;
    expect(m.state.current!.runs, 11);
    expect(m.state.current!.legalBalls, 3);
    // Celebrations are remembered so they never replay.
    expect(m.celebrated.length, 2);

    await tester.tap(find.byKey(const ValueKey('pad_undo')));
    await tester.pumpAndSettle();
    expect(r.matches[id]!.state.current!.runs, 5);
    expect(find.text('Last ball removed'), findsOneWidget);

    // Wide with one extra run.
    await tester.tap(find.byKey(const ValueKey('pad_wide')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    expect(r.matches[id]!.state.current!.runs, 7);
    expect(r.matches[id]!.state.current!.legalBalls, 2);
  });

  testWidgets('wicket asks for the next batter', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    r.addEvent(r.matches[id]!, {'t': Ev.start, 'striker': r.teamList.last.playerIds[0], 'nonStriker': r.teamList.last.playerIds[1], 'bowler': r.teamList.first.playerIds[0]});
    await tester.pumpWidget(wrap(s, r, ScoringScreen(matchId: id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pad_wicket')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bowled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save wicket'));
    await tester.pumpAndSettle();
    expect(r.matches[id]!.state.current!.wickets, 1);
    expect(find.text('Pick next batter'), findsWidgets);
  });

  testWidgets('match centre tabs open without errors', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    final m = r.matches[id]!;
    final bat = m.playersA;
    final bowl = m.playersB;
    r.addEvent(m, {'t': Ev.start, 'striker': bat[0], 'nonStriker': bat[1], 'bowler': bowl[0]});
    for (final runs in [1, 4, 0, 6, 2, 1]) {
      r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': runs, 'zone': 'cover', 'ang': 60.0, 'dist': 0.9});
    }
    r.addEvent(m, {'t': Ev.bowler, 'player': bowl[1]});
    r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 0, 'out': {'kind': OutKind.caught, 'fielder': bowl[2]}});
    await tester.pumpWidget(wrap(s, r, MatchCentreScreen(matchId: id)));
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
    for (final tab in ['Scorecard', 'Commentary', 'Squads', 'Stats', 'Summary']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('small phone with large text has no overflow (${mode.name})', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      _savedOnError = FlutterError.onError;
      FlutterError.onError = _errors.add;
      final (s, r) = await setUpApp();
      s.setTheme(mode);
      final id = seedMatch(r);
      final m = r.matches[id]!;
      r.addEvent(m, {'t': Ev.start, 'striker': m.playersA[0], 'nonStriker': m.playersA[1], 'bowler': m.playersB[0]});
      r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 4});
      final done = seedFinished(r);
      final tour = r.addTournament(
          name: 'Mithila Premier League Winter Edition', format: TFormat.groups, overs: 6, teamIds: [for (final t in r.teamList) t.id], groupCount: 2, qualifiers: 1);
      final ko = r.addTournament(name: 'KO Cup', format: TFormat.knockout, overs: 6, teamIds: [m.teamA, m.teamB]);
      r.addSponsor(ko, Sponsor(name: 'Sharma Hardware and Sanitary Store Madhubani', phone: '9876543210', place: 'Main road, near the old bus stand'));
      r.addSponsor(ko, Sponsor(name: 'Mithila Mobiles', role: 'six'));
      final f0 = ko.fixtures.single;
      r.createMatch(a: r.teams[m.teamA]!, b: r.teams[m.teamB]!, playersA: m.playersA, playersB: m.playersB, overs: 6, firstBatting: 0, tournamentId: ko.id, fixtureId: f0.id);
      Widget scaled(Widget child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
            child: child,
          );
      final screens = <Widget>[
        ScoringScreen(matchId: id),
        ScoringScreen(matchId: done),
        MatchCentreScreen(matchId: id),
        MatchCentreScreen(matchId: done),
        const NewMatchScreen(),
        PlayerScreen(playerId: m.playersA[0]),
        TeamScreen(teamId: m.teamA),
        const TeamScreen(),
        const SearchScreen(),
        const FaqScreen(),
        ArticleScreen(matchId: done),
        OnboardingScreen(onDone: () {}),
        const AuthScreen(),
        const AuthScreen(startOnSignUp: true),
        LiveStreamScreen(matchId: id),
        HighlightsScreen(matchId: id),
        const CreateTournamentScreen(),
        TournamentScreen(tournamentId: tour.id),
        TournamentScreen(tournamentId: ko.id),
        const InfoScreen(kind: 'privacy'),
        const InfoScreen(kind: 'terms'),
        const InfoScreen(kind: 'about'),
        const LeaderboardScreen(),
        const SeriesScreen(pushed: true),
        const NewsScreen(pushed: true),
      ];
      for (final screen in screens) {
        await tester.pumpWidget(scaled(wrap(s, r, screen, mode: mode)));
        await tester.pumpAndSettle();
        check(tester, screen.runtimeType.toString());
      }
      // Every intro scene.
      await tester.pumpWidget(scaled(wrap(s, r, OnboardingScreen(onDone: () {}), mode: mode)));
      await tester.pumpAndSettle();
      for (var i = 1; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        check(tester, 'intro scene $i');
      }
      // Sign up with a picked state and a foreign country code.
      await tester.pumpWidget(scaled(wrap(s, r, const AuthScreen(startOnSignUp: true), mode: mode)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('State'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State'));
      await tester.pumpAndSettle();
      check(tester, 'state sheet');
      await tester.tap(find.text('Bihar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      check(tester, 'country sheet');
      await tester.enterText(find.byType(TextField).last, 'united k');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('United Kingdom'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      check(tester, 'sign up errors');
      // Every tab of the main app.
      await tester.pumpWidget(scaled(GullyScoreApp(settings: s, repo: r)));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
        check(tester, 'tab $i');
      }
      // Hindi too.
      s.setLang('hi');
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
        check(tester, 'hindi tab $i');
      }
      await tester.pump(const Duration(seconds: 1));
      FlutterError.onError = _savedOnError;
    });
  }

  testWidgets('a finished match gets a report and a result card', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedFinished(r);
    expect(r.matches[id]!.state.finished, true);
    await tester.pumpWidget(wrap(s, r, ArticleScreen(matchId: id)));
    await tester.pumpAndSettle();
    expect(find.textContaining('won by'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  test('player photo name is saved and read back', () {
    final pl = Player(id: 'p1', name: 'Sanjay Jha', photo: 'p1_1.jpg');
    final back = Player.fromJson(pl.toJson());
    expect(back.photo, 'p1_1.jpg');
    expect(Player.fromJson(Player(id: 'p2', name: 'X').toJson()).photo, isNull);
  });

  testWidgets('profile picture opens photo choices and shows initials without a photo', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    final pid = r.matches[id]!.playersA.first;
    await tester.pumpWidget(wrap(s, r, PlayerScreen(playerId: pid)));
    await tester.pumpAndSettle();
    expect(find.text('R'), findsWidgets); // "Ravi" has no photo yet
    await tester.tap(find.bySemanticsLabel('Change photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tournament fixtures link to matches and all tabs open', (tester) async {
    final (s, r) = await setUpApp();
    final a = r.addTeam('Alpha', playerNames: ['A1', 'A2', 'A3']);
    final b = r.addTeam('Bravo', playerNames: ['B1', 'B2', 'B3']);
    final c = r.addTeam('Charlie', playerNames: ['C1', 'C2', 'C3']);
    final t = r.addTournament(name: 'Village Cup', format: TFormat.league, overs: 1, teamIds: [a.id, b.id, c.id], qualifiers: 2);
    expect(t.fixtures.length, 4); // 3 league + final
    final f = t.fixtures.first;
    final ta = r.teams[f.teamA]!;
    final tb = r.teams[f.teamB]!;
    final m = r.createMatch(a: ta, b: tb, playersA: ta.playerIds, playersB: tb.playerIds, overs: 1, firstBatting: 0, tournamentId: t.id, fixtureId: f.id);
    expect(f.matchId, m.id);
    r.addEvent(m, {'t': Ev.start, 'striker': ta.playerIds[0], 'nonStriker': ta.playerIds[1], 'bowler': tb.playerIds[0]});
    for (var i = 0; i < 6; i++) {
      r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 4});
    }
    r.addEvent(m, {'t': Ev.start, 'striker': tb.playerIds[0], 'nonStriker': tb.playerIds[1], 'bowler': ta.playerIds[0]});
    for (var i = 0; i < 6; i++) {
      r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 1});
    }
    expect(r.viewOf(t).played, 1);
    expect(r.viewOf(t).table().first.teamId, ta.id);

    await tester.pumpWidget(wrap(s, r, TournamentScreen(tournamentId: t.id)));
    await tester.pumpAndSettle();
    expect(find.text('Village Cup'), findsWidgets);
    expect(find.text('Start this match'), findsWidgets);
    for (final tab in ['Points table', 'Stats', 'Teams', 'Fixtures']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Player of the Match'), findsNothing); // only shown in match centre
    await tester.pump(const Duration(seconds: 1));
  });

  test('team logo name is saved and read back', () {
    final t = Team(id: 't1', name: 'Rajnagar XI', colorIndex: 1, logo: 'logo_t1_1.jpg');
    expect(Team.fromJson(t.toJson()).logo, 'logo_t1_1.jpg');
    expect(Team.fromJson(Team(id: 't2', name: 'X', colorIndex: 0).toJson()).logo, isNull);
  });

  test('backup file round trip restores everything', () async {
    final r = Repository(store: MemoryStore());
    await r.load();
    final id = seedMatch(r);
    final t = r.addTournament(name: 'Cup', format: TFormat.knockout, overs: 5, teamIds: r.teamList.map((t) => t.id).toList());
    final bytes = Backup.build(r.toJson(), at: DateTime(2026, 10, 21));
    final back = Backup.read(bytes);
    expect(back.matchCount, 1);
    expect(back.teamCount, 2);
    expect(back.created, DateTime(2026, 10, 21));

    final fresh = Repository(store: MemoryStore());
    await fresh.load();
    await fresh.restoreFrom(back.data);
    expect(fresh.matches[id]!.playersA.length, 3);
    expect(fresh.tournaments[t.id]!.fixtures.length, 1);
    expect(fresh.players.length, 6);
    await fresh.saveNow();
    await r.saveNow();
  });

  test('a random file is not mistaken for a backup', () {
    expect(() => Backup.read(Uint8List.fromList('hello'.codeUnits)), throwsFormatException);
    expect(() => Backup.read(Uint8List.fromList('{"a":1}'.codeUnits)), throwsFormatException);
  });

  testWidgets('team screen offers a logo', (tester) async {
    final (s, r) = await setUpApp();
    final id = seedMatch(r);
    await tester.pumpWidget(wrap(s, r, TeamScreen(teamId: r.matches[id]!.teamA)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add team logo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove logo'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('online screens fit on a small phone with large text (${mode.name})', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      _savedOnError = FlutterError.onError;
      FlutterError.onError = _errors.add;
      SharedPreferences.setMockInitialValues({
        'tourDone': true,
        'onboarded': true,
        'reduceMotion': true,
        'askShot': false,
        'cloud.user': 'Utoken',
        'cloud.userEmail': 'surajkumarthakur.longname@gmail.com',
        'cloud.myPhone': '9111111111',
      });
      final s = Settings();
      await s.load();
      s.setTheme(mode);
      final r = Repository(store: MemoryStore());
      await r.load();
      final done = seedFinished(r);
      final sync = SyncService(r, OnlineCloud(), google: NoGoogle(), socialSender: fakeSend);
      await sync.start(timers: false);
      await sync.refreshMe();
      final team = MeInfo.fromJson(meJson).teams.first;
      Widget app(Widget child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) => AppScope(
                repo: r,
                settings: s,
                sync: sync,
                rev: s.rev,
                child: MaterialApp(
                  key: UniqueKey(), // a fresh app each time, so sheets from the last screen are gone
                  theme: buildTheme(Palette.lightP),
                  darkTheme: buildTheme(Palette.darkP),
                  themeMode: mode,
                  home: child,
                ),
              ),
            ),
          );
      Future<void> show(Widget w, String name, {List<String> taps = const []}) async {
        await tester.pumpWidget(app(w));
        await tester.pumpAndSettle();
        check(tester, name);
        for (final t in taps) {
          await tester.tap(find.text(t).first);
          await tester.pumpAndSettle();
          check(tester, '$name → $t');
        }
      }

      for (final lang in ['en', 'hi']) {
        s.setLang(lang);
        final hi = lang == 'hi';
        await show(Scaffold(body: MyCricketScreen(onOpenTab: (_) {})), 'my cricket $lang', taps: [hi ? 'मेरी टीमें' : 'My teams']);
        await show(const Scaffold(body: CommunityScreen()), 'community $lang');
        await show(const Scaffold(body: MatchesScreen()), 'feed $lang', taps: [hi ? 'आने वाले · 4' : 'Upcoming · 4', hi ? 'नतीजे' : 'Results']);
        await show(TeamRatingsScreen(scorerId: 's1', teamId: 'tA', teamName: 'Madhubani Super Strikers XI'), 'ratings $lang');
        await show(OnlineTeamScreen(team: team), 'team page $lang');
        await show(MatchCentreScreen(matchId: done), 'rate button $lang');
        if (find.textContaining(hi ? 'रेटिंग दें' : 'Rate ').evaluate().isEmpty) {
          FlutterError.onError = _savedOnError;
          fail('no rate button ($lang)');
        }
        await tester.tap(find.textContaining(hi ? 'रेटिंग दें' : 'Rate ').first);
        await tester.pumpAndSettle();
        check(tester, 'rate sheet $lang');
        await show(const Scaffold(drawer: AppDrawer(), body: SizedBox()), 'drawer $lang');
        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();
        check(tester, 'drawer open $lang');
        await show(const LeaderboardScreen(), 'leaderboard $lang');
        await show(AvailabilityScreen(team: team), 'who is coming $lang');
        await tester.tap(find.text(hi ? 'टीम (4)' : 'Squad (4)'));
        await tester.pumpAndSettle();
        check(tester, 'who is coming squad $lang');
        await show(KhataScreen(team: team), 'khata $lang');
        await show(BadgesScreen(me: MeInfo.fromJson(meJson)), 'badges $lang');
        await show(const GroundsScreen(locate: false), 'grounds $lang');
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();
        check(tester, 'ground filters $lang');
        await show(const GroundsScreen(locate: false), 'grounds again $lang');
        await tester.tap(find.textContaining(hi ? 'बदलें' : 'change').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'darbh');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        check(tester, 'choose location $lang');
        for (final tab in ['about', 'book', 'photos', 'reviews', 'matches', 'tournaments', 'insights']) {
          await show(const GroundDetailScreen(groundId: 'g1'), 'ground $tab $lang');
          final tabText = find.text(Strings.get('gtab_$tab', lang)).first;
          await tester.ensureVisible(tabText);
          await tester.pumpAndSettle();
          await tester.tap(tabText);
          await tester.pumpAndSettle();
          check(tester, 'ground tab $tab $lang');
        }
        await show(const GroundDetailScreen(key: ValueKey('gm'), groundId: 'gm'), 'map ground $lang');
        if (find.text(Strings.get('add_details', lang)).evaluate().isEmpty) {
          FlutterError.onError = _savedOnError;
          fail('map ground should ask for details ($lang)');
        }
        final g = Ground(Map<String, dynamic>.from(await fakeSend('GET', '/v1/grounds/g1')));
        await show(RegisterGroundScreen(edit: g, locate: false), 'register ground $lang');
        for (var step = 0; step < 2; step++) {
          final next = find.text(Strings.get('next', lang)).first;
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pumpAndSettle();
          check(tester, 'register step ${step + 2} $lang');
        }
        await show(const NotificationsScreen(), 'notifications $lang');
        await show(const NewMatchScreen(), 'new match $lang', taps: [hi ? 'बाद में खेलें' : 'Schedule for later']);

        // v0.9: picture studio, stories, levels, head to head and booking
        Future<void> tapText(String text, String name) async {
          // Built but below the screen counts too; ensureVisible scrolls to it.
          var f = find.text(text, skipOffstage: false);
          for (var i = 0; i < 8 && f.evaluate().isEmpty; i++) {
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
            await tester.pumpAndSettle();
            f = find.text(text, skipOffstage: false);
          }
          if (f.evaluate().isEmpty) {
            FlutterError.onError = _savedOnError;
            final seen = find.byType(Text, skipOffstage: false).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(60).join(' | ');
            fail('$name: "$text" not found. On screen: $seen');
          }
          await tester.ensureVisible(f.first);
          await tester.pumpAndSettle();
          await tester.tap(f.first);
          await tester.pumpAndSettle();
          check(tester, name);
        }

        Future<void> storySteps(String name) async {
          for (var i = 0; i < 6; i++) {
            final next = find.byTooltip(Strings.get('next', lang));
            if (next.evaluate().isEmpty) break;
            await tester.tap(next.first);
            await tester.pumpAndSettle();
            check(tester, '$name slide ${i + 2}');
          }
        }

        final dm = r.matches[done]!;
        final batter = dm.playersA.first, bowler = dm.playersB.first;
        Future<void> launch(String name, Future<void> Function(BuildContext) open) async {
          await tester.pumpWidget(app(Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(onPressed: () => open(ctx), child: const Text('GO')))))));
          await tester.pumpAndSettle();
          await tester.tap(find.text('GO'));
          await tester.pumpAndSettle();
          check(tester, name);
        }

        await show(PlayerScreen(playerId: batter), 'player tools $lang');
        await launch('player card $lang', (c) => openPlayerCard(c, batter));
        for (final t in ['royal', 'neon', 'ivory']) {
          await tapText(Strings.get('theme_$t', lang), 'card theme $t $lang');
        }
        await tapText(Strings.get('size_story', lang), 'card story size $lang');
        await tapText(Strings.get('size_square', lang), 'card square size $lang');
        await launch('wrapped $lang', (c) => openSeasonWrapped(c, batter));
        await storySteps('wrapped $lang');
        await launch('face off $lang', (c) => openFaceOff(c, batter, bowler));
        await show(LevelScreen(playerId: batter), 'level $lang');
        await show(HeadToHeadScreen(batter: batter, bowler: bowler), 'head to head $lang');
        await show(HeadToHeadScreen(batter: bowler, bowler: batter), 'head to head other way $lang');
        await show(MatchCentreScreen(matchId: done), 'match centre studio $lang');
        await launch('poster $lang', (c) => openPoster(c, dm));
        await tapText(Strings.get('poster_tab_day', lang), 'poster day $lang');
        await tapText(Strings.get('poster_tab_live', lang), 'poster live $lang');
        await launch('match story $lang', (c) => openMatchStory(c, dm));
        await storySteps('match story $lang');
        await launch('certificate $lang', (c) => openMomCertificate(c, dm));
        await show(const BookingsScreen(), 'bookings $lang');
        await tapText(Strings.get('bookings_incoming', lang), 'bookings incoming $lang');
        final g1 = Ground(Map<String, dynamic>.from(await fakeSend('GET', '/v1/grounds/g1')));
        await show(SlotsEditorScreen(ground: g1, slots: [Slot(id: 's1', label: 'Morning', start: 360, end: 600, price: 150000)]), 'slots editor $lang');
        await tapText('+ ${Strings.get('slot_night', lang)}', 'slots editor add $lang');
      }
      await tester.pump(const Duration(seconds: 1));
      FlutterError.onError = _savedOnError;
    });
  }

  testWidgets('a scheduled match asks the toss when scoring starts', (tester) async {
    final (s, r) = await setUpApp();
    final a = r.addTeam('Rajnagar XI', playerNames: ['Ravi', 'Raju', 'Rohit']);
    final b = r.addTeam('Madhubani Strikers', playerNames: ['Sanjay', 'Vikas', 'Amit']);
    final m = r.createMatch(a: a, b: b, playersA: a.playerIds, playersB: b.playerIds, overs: 2, firstBatting: 0, scheduledAt: DateTime.now().add(const Duration(days: 1)));
    expect(m.tossPending, true);
    expect(MatchRecord.fromJson(m.toJson()).scheduledAt, isNotNull);
    expect(matchStatusOnline(m, m.state), 'upcoming');
    await tester.pumpWidget(wrap(s, r, ScoringScreen(matchId: m.id)));
    await tester.pumpAndSettle();
    expect(find.text('Who won the toss?'), findsOneWidget);
    await tester.tap(find.text('Madhubani Strikers'));
    await tester.tap(find.text('Bowl'));
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(m.tossPending, false);
    expect(m.firstBatting, 0, reason: 'B won and chose to bowl, so A bats');
    expect(find.text('Pick openers and bowler'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  test('player numbers for My Cricket and the leaderboard', () async {
    final r = Repository(store: MemoryStore());
    await r.load();
    final id = seedFinished(r);
    final m = r.matches[id]!;
    final st = m.state;
    final opener = playerLine(st, m.playersA[0], m.teamA, 'Kishan');
    expect(opener['runs'], 3);
    expect((opener['line'] as Map)['notOut'], true);
    final bowler = playerLine(st, m.playersB[0], m.teamB, 'Deepak');
    expect(bowler['wickets'], 0);
    expect((bowler['line'] as Map)['o'], '1.0');
    expect(matchStatusOnline(m, st), 'result');
  });

  test('badges come from match numbers', () {
    final me = MeInfo.fromJson(meJson);
    final ids = earnedBadges(me.matches).map((b) => b.def.id).toSet();
    expect(ids, containsAll(['debut', 'fifty', 'century', 'six_hitter', 'three_wickets', 'five_wickets', 'hat_trick', 'safe_hands']));
    expect(ids.contains('ten_matches'), false);
    expect(earnedBadges(const []), isEmpty);
  });

  test('sponsors are saved with the tournament and go online with its matches', () async {
    final r = Repository(store: MemoryStore());
    await r.load();
    final a = r.addTeam('A', playerNames: ['a1', 'a2']);
    final b = r.addTeam('B', playerNames: ['b1', 'b2']);
    final t = r.addTournament(name: 'Cup', format: TFormat.knockout, overs: 5, teamIds: [a.id, b.id]);
    final m = r.createMatch(a: a, b: b, playersA: a.playerIds, playersB: b.playerIds, overs: 5, firstBatting: 0, tournamentId: t.id, fixtureId: t.fixtures.single.id);
    r.addSponsor(t, Sponsor(name: 'Sharma Hardware', phone: '98765'));
    expect(Tournament.fromJson(t.toJson()).sponsors.single.name, 'Sharma Hardware');
    final data = r.cloudData(m);
    expect(((data['match'] as Map)['sponsors'] as List).single['name'], 'Sharma Hardware');
    final copy = MatchRecord.fromJson({...Map<String, dynamic>.from(data['match'] as Map), 'remote': true});
    expect(r.sponsorsOf(copy).single.phone, '98765');
    await r.saveNow();
  });

  test('notification topics follow the switches', () {
    final on = {'s': true, 'w': true, 'b': false, 'f': true, 'a': true, 'c': true};
    final t = wantedTopics(on: on, teams: [('s1', 'tA')], followed: ['m 1'], userId: 'g42');
    expect(t, containsAll(['t.s1.tA.s', 't.s1.tA.w', 't.s1.tA.a', 'm.m_1.s', 'u.g42']));
    expect(t.contains('t.s1.tA.b'), false);
    final none = wantedTopics(on: {for (final k in on.keys) k: false}, teams: [('s1', 'tA')], followed: ['x'], userId: 'g42');
    expect(none, isEmpty);
  });
}
