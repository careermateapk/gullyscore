// Notifications with Firebase Cloud Messaging. The phone subscribes to
// topics (a match, a team, or this person); the service sends to topics.
// Nothing is set up unless the Firebase settings were built into the app.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fbApiKey = String.fromEnvironment('FB_API_KEY');
const _fbAppId = String.fromEnvironment('FB_APP_ID');
const _fbSender = String.fromEnvironment('FB_SENDER');
const _fbProject = String.fromEnvironment('FB_PROJECT');

/// Kinds of notifications people can switch on and off.
const pushKinds = ['s', 'w', 'b', 'f', 'a', 'c'];
const _defaults = {'s': true, 'w': true, 'b': false, 'f': true, 'a': true, 'c': true};

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9\-_.~%]'), '_');
String pushTopic(List<String> parts) => parts.map(_safe).join('.');

/// Which topics to be in, from the switches, my teams, followed matches and me.
Set<String> wantedTopics({
  required Map<String, bool> on,
  required List<(String scorer, String team)> teams,
  required Iterable<String> followed,
  String? userId,
}) {
  final out = <String>{};
  for (final t in teams) {
    for (final level in ['s', 'w', 'b', 'a']) {
      if (on[level] == true) out.add(pushTopic(['t', t.$1, t.$2, level]));
    }
  }
  if (on['f'] == true) {
    for (final m in followed) {
      out.add(pushTopic(['m', m, 's']));
    }
  }
  if (on['c'] == true && userId != null && userId.isNotEmpty) out.add(pushTopic(['u', userId]));
  return out;
}

class PushService extends ChangeNotifier {
  bool ready = false;
  final Map<String, bool> on = Map.of(_defaults);
  Set<String> _subscribed = {};
  SharedPreferences? _prefs;

  /// Called when a notification is tapped (or arrives while the app is open).
  void Function(String? matchId)? onOpen;
  void Function(String title, String body, String? matchId)? onForeground;

  static bool get configured => _fbApiKey.isNotEmpty && _fbAppId.isNotEmpty && _fbProject.isNotEmpty;

  Future<void> loadSwitches() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      for (final k in pushKinds) {
        on[k] = p.getBool('push.$k') ?? _defaults[k]!;
      }
      _subscribed = (p.getStringList('push.topics') ?? const []).toSet();
    } catch (_) {}
  }

  Future<void> init() async {
    await loadSwitches();
    if (!configured) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(apiKey: _fbApiKey, appId: _fbAppId, messagingSenderId: _fbSender, projectId: _fbProject),
      );
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) onForeground?.call(n.title ?? '', n.body ?? '', msg.data['matchId'] as String?);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((msg) => onOpen?.call(msg.data['matchId'] as String?));
      final first = await m.getInitialMessage();
      if (first != null) {
        Timer(const Duration(seconds: 2), () => onOpen?.call(first.data['matchId'] as String?));
      }
      ready = true;
      notifyListeners();
    } catch (e) {
      debugPrint('push off: $e');
    }
  }

  Future<void> setSwitch(String kind, bool v) async {
    on[kind] = v;
    await _prefs?.setBool('push.$kind', v);
    notifyListeners();
  }

  /// Joins and leaves topics so they match [wanted].
  Future<void> apply(Set<String> wanted) async {
    if (!ready) return;
    final m = FirebaseMessaging.instance;
    for (final t in wanted.difference(_subscribed)) {
      try {
        await m.subscribeToTopic(t);
        _subscribed.add(t);
      } catch (_) {}
    }
    for (final t in _subscribed.difference(wanted).toList()) {
      try {
        await m.unsubscribeFromTopic(t);
        _subscribed.remove(t);
      } catch (_) {}
    }
    await _prefs?.setStringList('push.topics', _subscribed.toList());
  }
}
