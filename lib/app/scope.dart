// Gives every screen access to the saved data and the settings.
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/sync.dart';
import 'settings.dart';
import 'strings.dart';

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.repo, required this.settings, required this.sync, required this.rev, required super.child});

  final Repository repo;
  final Settings settings;
  final SyncService sync;
  final int rev; // changes whenever a setting changes, so text and colours refresh

  static AppScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing');
    return s!;
  }

  /// Reads without rebuilding when it changes (for button handlers).
  static AppScope read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => rev != old.rev || repo != old.repo;
}

extension AppContext on BuildContext {
  Repository get repo => AppScope.read(this).repo;
  Settings get settings => AppScope.read(this).settings;
  SyncService get sync => AppScope.read(this).sync;

  /// Translated text for [key]; `{name}` parts are filled from [args].
  String tr(String key, [Map<String, Object> args = const {}]) {
    final lang = AppScope.of(this).settings.lang;
    var s = Strings.get(key, lang);
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  bool get reduceMotion => AppScope.read(this).settings.reduceMotion || MediaQuery.of(this).disableAnimations;
}
