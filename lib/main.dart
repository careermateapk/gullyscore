import 'package:flutter/material.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'data/cloud.dart';
import 'data/photos.dart';
import 'data/repository.dart';
import 'data/sync.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/online.dart';
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
  // Notifications: tapping one opens that match.
  sync.push.onOpen = (matchId) {
    final ctx = appNavigator.currentContext;
    if (matchId != null && ctx != null && ctx.mounted) openFollowed(ctx, matchId);
  };
  sync.push.onForeground = (title, body, matchId) {
    appMessenger.currentState?.showSnackBar(SnackBar(
      content: Text(body.isEmpty ? title : '$title\n$body'),
      action: matchId == null ? null : SnackBarAction(label: 'Open', onPressed: () => sync.push.onOpen?.call(matchId)),
    ));
  };
  await sync.push.init();
  await sync.updatePush();
}

final appNavigator = GlobalKey<NavigatorState>();
final appMessenger = GlobalKey<ScaffoldMessengerState>();

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
          navigatorKey: appNavigator,
          scaffoldMessengerKey: appMessenger,
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: buildTheme(Palette.lightP),
          darkTheme: buildTheme(Palette.darkP),
          themeAnimationDuration: settings.reduceMotion ? Duration.zero : Motion.page,
          home: settings.onboarded ? _AuthGate(sync: sync) : OnboardingScreen(onDone: () {}),
        ),
      ),
    );
  }
}

/// No dashboard without an account (when the online server is set up).
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.sync});
  final SyncService sync;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool? _wasIn;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_changed);
  }

  @override
  void dispose() {
    widget.sync.removeListener(_changed);
    super.dispose();
  }

  bool get _in => !widget.sync.enabled || widget.sync.loggedIn;

  void _changed() {
    final now = _in;
    // Logged out from somewhere deep in the app: close those pages.
    if (_wasIn == true && !now) appNavigator.currentState?.popUntil((r) => r.isFirst);
    _wasIn = now;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sync;
    if (s.enabled && !s.ready) return const Scaffold(backgroundColor: Color(0xFF03060D));
    _wasIn ??= _in;
    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 400),
      child: _in ? const Shell(key: ValueKey('shell')) : const AuthScreen(key: ValueKey('auth')),
    );
  }
}
