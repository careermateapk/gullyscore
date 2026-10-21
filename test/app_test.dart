import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/app/scope.dart';
import 'package:gullyscore/app/settings.dart';
import 'package:gullyscore/app/theme.dart';
import 'package:gullyscore/data/repository.dart';
import 'package:gullyscore/main.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:gullyscore/ui/screens/help.dart';
import 'package:gullyscore/ui/screens/match_centre_screen.dart';
import 'package:gullyscore/ui/screens/new_match_screen.dart';
import 'package:gullyscore/ui/screens/news_screen.dart';
import 'package:gullyscore/ui/screens/onboarding_screen.dart';
import 'package:gullyscore/ui/screens/player_screen.dart';
import 'package:gullyscore/ui/screens/search_screen.dart';
import 'package:gullyscore/ui/screens/team_screen.dart';
import 'package:gullyscore/ui/screens/scoring_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Settings, Repository)> setUpApp({bool onboarded = true, bool reduceMotion = true}) async {
  SharedPreferences.setMockInitialValues({'onboarded': onboarded, 'reduceMotion': reduceMotion, 'askShot': false});
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

void main() {
  testWidgets('first launch shows onboarding, then the empty home', (tester) async {
    final (s, r) = await setUpApp(onboarded: false);
    await tester.pumpWidget(GullyScoreApp(settings: s, repo: r));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to GullyScore'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Score your first match'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
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
      final (s, r) = await setUpApp();
      s.setTheme(mode);
      final id = seedMatch(r);
      final m = r.matches[id]!;
      r.addEvent(m, {'t': Ev.start, 'striker': m.playersA[0], 'nonStriker': m.playersA[1], 'bowler': m.playersB[0]});
      r.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 4});
      final done = seedFinished(r);
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
      ];
      for (final screen in screens) {
        await tester.pumpWidget(scaled(wrap(s, r, screen, mode: mode)));
        await tester.pumpAndSettle();
      }
      // Every tab of the main app.
      await tester.pumpWidget(scaled(GullyScoreApp(settings: s, repo: r)));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
      }
      // Hindi too.
      s.setLang('hi');
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
      }
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
}
