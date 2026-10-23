// Bottom navigation: Home, Matches, My Cricket, Community, Profile,
// plus the ☰ side menu (tournaments, news, help, policies...).
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/app_tour.dart';
import 'app_drawer.dart';
import 'community_screen.dart';
import 'home_screen.dart';
import 'matches_screen.dart';
import 'my_cricket_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  OverlayEntry? _tour;

  void go(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    tourRequest.addListener(_replayTour);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !context.settings.tourDone) _startTour();
    });
  }

  @override
  void dispose() {
    tourRequest.removeListener(_replayTour);
    _tour?.remove();
    _tour = null;
    super.dispose();
  }

  void _replayTour() {
    if (!mounted) return;
    go(0);
    // wait for Home to be on screen
    Future.delayed(context.reduceMotion ? Duration.zero : const Duration(milliseconds: 450), () {
      if (mounted) _startTour();
    });
  }

  void _startTour() {
    if (_tour != null) return;
    _tour = showAppTour(context, onDone: () {
      _tour = null;
      if (mounted) context.settings.setTourDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pages = [
      HomeScreen(onOpenTab: go),
      const MatchesScreen(),
      MyCricketScreen(onOpenTab: go),
      const CommunityScreen(),
      const SettingsScreen(),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        backgroundColor: p.bg,
        drawer: const AppDrawer(),
        body: AnimatedSwitcher(
          duration: context.reduceMotion ? Duration.zero : Motion.fade,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: p.nav,
            indicatorColor: p.gold.withValues(alpha: 0.14),
            height: 72,
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                  fontFamily: 'Hanken',
                  fontFamilyFallback: const ['NotoDeva'],
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: s.contains(WidgetState.selected) ? p.goldText : p.text2,
                )),
            iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.goldText : p.text2, size: 22)),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
            child: NavigationBar(
              key: TourKeys.navBar,
              selectedIndex: _index,
              onDestinationSelected: go,
              animationDuration: Motion.fade,
              destinations: [
                NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.tr('nav_home')),
                NavigationDestination(icon: const Icon(Icons.sports_cricket_outlined), selectedIcon: const Icon(Icons.sports_cricket_rounded), label: context.tr('nav_matches')),
                NavigationDestination(icon: const Icon(Icons.sports_handball_outlined), selectedIcon: const Icon(Icons.sports_handball_rounded), label: context.tr('nav_my_cricket')),
                NavigationDestination(icon: const Icon(Icons.groups_outlined), selectedIcon: const Icon(Icons.groups_rounded), label: context.tr('nav_community')),
                NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('nav_profile')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
