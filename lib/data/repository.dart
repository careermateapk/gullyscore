// Where teams, players and matches are kept.
//
// The UI only talks to [Repository]. Today it saves to a file on the phone
// ([FileRepository]); an online version can be added later behind the same
// interface without touching the screens.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class Repository extends ChangeNotifier {
  Repository({Store? store}) : _store = store ?? FileStore();

  final Store _store;
  final Map<String, Player> players = {};
  final Map<String, Team> teams = {};
  final Map<String, MatchRecord> matches = {};

  bool loaded = false;
  Object? loadError;
  Timer? _saveTimer;

  Future<void> load() async {
    try {
      final data = await _store.read();
      if (data != null) {
        for (final p in (data['players'] as List? ?? const [])) {
          final pl = Player.fromJson(Map<String, dynamic>.from(p as Map));
          players[pl.id] = pl;
        }
        for (final t in (data['teams'] as List? ?? const [])) {
          final tm = Team.fromJson(Map<String, dynamic>.from(t as Map));
          teams[tm.id] = tm;
        }
        for (final m in (data['matches'] as List? ?? const [])) {
          final mr = MatchRecord.fromJson(Map<String, dynamic>.from(m as Map));
          matches[mr.id] = mr;
        }
      }
      loadError = null;
    } catch (e) {
      loadError = e;
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'players': [for (final p in players.values) p.toJson()],
        'teams': [for (final t in teams.values) t.toJson()],
        'matches': [for (final m in matches.values) m.toJson()],
      };

  /// Saves soon (several quick changes are written once).
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _store.write(toJson());
  }

  // ---------- names ----------

  String playerName(String id) => players[id]?.name ?? '?';
  String teamName(String id) => teams[id]?.name ?? '?';

  // ---------- teams and players ----------

  List<Team> get teamList => teams.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Team addTeam(String name, {List<String> playerNames = const []}) {
    final t = Team(id: newId(), name: name.trim(), colorIndex: teams.length % 8);
    teams[t.id] = t;
    for (final n in playerNames) {
      if (n.trim().isEmpty) continue;
      final p = Player(id: '${t.id}_${t.playerIds.length}_${newId()}', name: n.trim());
      players[p.id] = p;
      t.playerIds.add(p.id);
    }
    _changed();
    return t;
  }

  Player addPlayer(Team team, String name) {
    final p = Player(id: '${team.id}_${team.playerIds.length}_${newId()}', name: name.trim());
    players[p.id] = p;
    team.playerIds.add(p.id);
    _changed();
    return p;
  }

  void updatePlayer(Player p, {String? name, bool? leftHanded, String? role}) {
    if (name != null && name.trim().isNotEmpty) p.name = name.trim();
    if (leftHanded != null) p.leftHanded = leftHanded;
    if (role != null) p.role = role;
    _changed();
  }

  void renameTeam(Team t, String name) {
    if (name.trim().isEmpty) return;
    t.name = name.trim();
    _changed();
  }

  // ---------- matches ----------

  List<MatchRecord> get matchList => matches.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  MatchRecord createMatch({
    required Team a,
    required Team b,
    required List<String> playersA,
    required List<String> playersB,
    required int overs,
    required int firstBatting,
    String venue = '',
    String title = '',
    String tossText = '',
  }) {
    final m = MatchRecord(
      id: newId(),
      teamA: a.id,
      teamB: b.id,
      playersA: playersA,
      playersB: playersB,
      overs: overs,
      firstBatting: firstBatting,
      createdAt: DateTime.now(),
      venue: venue,
      title: title,
      tossText: tossText,
    );
    matches[m.id] = m;
    _changed();
    return m;
  }

  void addEvent(MatchRecord m, Map<String, dynamic> e) {
    m.events = [...m.events, e];
    m.updatedAt = DateTime.now();
    _changed();
  }

  void setEvents(MatchRecord m, List<Map<String, dynamic>> events) {
    m.events = events;
    m.updatedAt = DateTime.now();
    _changed();
  }

  void markCelebrated(MatchRecord m, String key) {
    if (m.celebrated.add(key)) _changed();
  }

  void deleteMatch(String id) {
    matches.remove(id);
    _changed();
  }

  /// Removes everything saved on this phone.
  Future<void> deleteAll() async {
    players.clear();
    teams.clear();
    matches.clear();
    notifyListeners();
    await saveNow();
  }
}

/// Reads and writes the whole data file.
abstract class Store {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
}

class FileStore implements Store {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gullyscore.json');
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final f = await _file();
    if (!await f.exists()) {
      // A crash during a write leaves the previous copy behind.
      final bak = File('${f.path}.bak');
      if (await bak.exists()) return jsonDecode(await bak.readAsString()) as Map<String, dynamic>;
      return null;
    }
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    if (await f.exists()) await f.copy('${f.path}.bak');
    await tmp.rename(f.path);
  }
}

/// Keeps data in memory only (used by tests).
class MemoryStore implements Store {
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> read() async => data;

  @override
  Future<void> write(Map<String, dynamic> d) async => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
}
