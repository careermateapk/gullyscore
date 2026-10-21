// First launch: language, look, and how your data is kept.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_i == 2) {
      context.settings.setOnboarded();
      widget.onDone();
      return;
    }
    _pages.nextPage(duration: context.reduceMotion ? const Duration(milliseconds: 1) : Motion.page, curve: Motion.move);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context).settings;

    Widget page({required Widget art, required String title, required String body, Widget? extra}) => LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: art),
                const SizedBox(height: Space.xl),
                Text(title, style: Tx.score(40, p.text).copyWith(height: 1.05)),
                const SizedBox(height: Space.m),
                Text(body, style: Tx.body(p.text2).copyWith(fontSize: 16)),
                if (extra != null) ...[const SizedBox(height: Space.xl), extra],
                const SizedBox(height: Space.l),
              ]),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, Space.m, Space.s, 0),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: Motion.fade,
                  width: 18,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: i == _i ? p.gold : p.line, borderRadius: BorderRadius.circular(99)),
                ),
              const Spacer(),
              if (_i < 2)
                TextButton(
                  onPressed: () {
                    s.setOnboarded();
                    widget.onDone();
                  },
                  style: TextButton.styleFrom(foregroundColor: p.goldText, minimumSize: const Size(56, 44)),
                  child: Text(context.tr('skip'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                page(
                  art: const AppLogo(size: 96),
                  title: context.tr('welcome_title'),
                  body: context.tr('welcome_body'),
                  extra: Segmented<String>(values: const ['en', 'hi'], labels: const ['English', 'हिंदी'], selected: s.lang, onChanged: s.setLang),
                ),
                page(
                  art: Icon(Icons.contrast_rounded, size: 88, color: p.goldText),
                  title: context.tr('look_title'),
                  body: context.tr('look_body'),
                  extra: Segmented<ThemeMode>(
                    values: const [ThemeMode.light, ThemeMode.dark, ThemeMode.system],
                    labels: [context.tr('light'), context.tr('dark'), context.tr('auto')],
                    selected: s.themeMode,
                    onChanged: s.setTheme,
                  ),
                ),
                page(
                  art: Icon(Icons.phone_android_rounded, size: 88, color: p.win),
                  title: context.tr('data_title'),
                  body: context.tr('data_body'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, Space.s, 24, Space.l),
            child: SizedBox(
              width: double.infinity,
              child: GoldButton(label: _i == 2 ? context.tr('start_scoring') : context.tr('next'), onPressed: _next),
            ),
          ),
        ]),
      ),
    );
  }
}
