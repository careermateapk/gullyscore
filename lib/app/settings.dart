// App settings saved on the phone.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  String lang = 'en'; // 'en' or 'hi'
  bool reduceMotion = false;
  bool askShotDirection = true;
  bool haptics = true;
  bool onboarded = false;
  final Set<String> favouriteTeams = {};

  SharedPreferences? _prefs;

  /// Goes up by one on every change.
  int rev = 0;

  @override
  void notifyListeners() {
    rev++;
    super.notifyListeners();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      themeMode = ThemeMode.values[(p.getInt('theme') ?? ThemeMode.dark.index).clamp(0, 2)];
      lang = p.getString('lang') ?? 'en';
      reduceMotion = p.getBool('reduceMotion') ?? false;
      askShotDirection = p.getBool('askShot') ?? true;
      haptics = p.getBool('haptics') ?? true;
      onboarded = p.getBool('onboarded') ?? false;
      favouriteTeams
        ..clear()
        ..addAll(p.getStringList('favTeams') ?? const []);
    } catch (_) {
      // Settings are a convenience: if they cannot be read the defaults are used.
    }
    notifyListeners();
  }

  void _save(void Function(SharedPreferences p) write) {
    final p = _prefs;
    if (p != null) write(p);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save((p) => p.setInt('theme', m.index));
  }

  void setLang(String l) {
    lang = l;
    _save((p) => p.setString('lang', l));
  }

  void setReduceMotion(bool v) {
    reduceMotion = v;
    _save((p) => p.setBool('reduceMotion', v));
  }

  void setAskShot(bool v) {
    askShotDirection = v;
    _save((p) => p.setBool('askShot', v));
  }

  void setHaptics(bool v) {
    haptics = v;
    _save((p) => p.setBool('haptics', v));
  }

  void setOnboarded() {
    onboarded = true;
    _save((p) => p.setBool('onboarded', true));
  }

  void toggleFavourite(String teamId) {
    if (!favouriteTeams.remove(teamId)) favouriteTeams.add(teamId);
    _save((p) => p.setStringList('favTeams', favouriteTeams.toList()));
  }
}
