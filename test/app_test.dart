import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/app/scope.dart';
import 'package:gullyscore/app/settings.dart';
import 'package:gullyscore/app/theme.dart';
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
        const CreateTournamentScreen(),
        TournamentScreen(tournamentId: tour.id),
        TournamentScreen(tournamentId: ko.id),
      ];
      for (final screen in screens) {
        await tester.pumpWidget(scaled(wrap(s, r, screen, mode: mode)));
        await tester.pumpAndSettle();
        check(tester, screen.runtimeType.toString());
      }
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
}
