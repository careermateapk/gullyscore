import 'package:flutter/material.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = Settings();
  final repo = Repository();
  await Future.wait([settings.load(), repo.load()]);
  runApp(GullyScoreApp(settings: settings, repo: repo));
}

class GullyScoreApp extends StatelessWidget {
  const GullyScoreApp({super.key, required this.settings, required this.repo});
  final Settings settings;
  final Repository repo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AppScope(
        repo: repo,
        settings: settings,
        rev: settings.rev,
        child: MaterialApp(
          title: 'GullyScore',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: buildTheme(Palette.lightP),
          darkTheme: buildTheme(Palette.darkP),
          themeAnimationDuration: Motion.page,
          home: const Scaffold(body: Center(child: Text('GullyScore'))),
        ),
      ),
    );
  }
}
