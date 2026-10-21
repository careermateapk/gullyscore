// Bottom navigation: Home, Matches, Series, News, Profile.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import 'home_screen.dart';
import 'matches_screen.dart';
import 'news_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pages = [
      HomeScreen(onOpenTab: go),
      const MatchesScreen(),
      const SeriesScreen(),
      const NewsScreen(),
      const SettingsScreen(),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        backgroundColor: p.bg,
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
              selectedIndex: _index,
              onDestinationSelected: go,
              animationDuration: Motion.fade,
              destinations: [
                NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.tr('nav_home')),
                NavigationDestination(icon: const Icon(Icons.sports_cricket_outlined), selectedIcon: const Icon(Icons.sports_cricket_rounded), label: context.tr('nav_matches')),
                NavigationDestination(icon: const Icon(Icons.emoji_events_outlined), selectedIcon: const Icon(Icons.emoji_events_rounded), label: context.tr('nav_series')),
                NavigationDestination(icon: const Icon(Icons.article_outlined), selectedIcon: const Icon(Icons.article_rounded), label: context.tr('nav_news')),
                NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('nav_profile')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
