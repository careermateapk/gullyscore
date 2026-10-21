import 'package:flutter/material.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'data/cloud.dart';
import 'data/photos.dart';
import 'data/repository.dart';
import 'data/sync.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = Settings();
  final repo = Repository();
  final sync = SyncService(repo, HttpCloud());
  await Future.wait([settings.load(), PhotoStore.init()]);
  runApp(GullyScoreApp(settings: settings, repo: repo, sync: sync));
  // Matches load in the background; Home shows a skeleton until they arrive.
  await repo.load();
  await sync.start();
}

class GullyScoreApp extends StatelessWidget {
  GullyScoreApp({super.key, required this.settings, required this.repo, SyncService? sync}) : sync = sync ?? SyncService(repo, HttpCloud(''));
  final Settings settings;
  final Repository repo;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AppScope(
        repo: repo,
        settings: settings,
        sync: sync,
        rev: settings.rev,
        child: MaterialApp(
          title: 'GullyScore',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: buildTheme(Palette.lightP),
          darkTheme: buildTheme(Palette.darkP),
          themeAnimationDuration: settings.reduceMotion ? Duration.zero : Motion.page,
          home: settings.onboarded ? const Shell() : OnboardingScreen(onDone: () {}),
        ),
      ),
    );
  }
}
