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

import '../scoring/engine.dart';
import '../scoring/tournament.dart';
import 'models.dart';
import 'photos.dart';

class Repository extends ChangeNotifier {
  Repository({Store? store}) : _store = store ?? FileStore();

  final Store _store;
  final Map<String, Player> players = {};
  final Map<String, Team> teams = {};
  final Map<String, MatchRecord> matches = {};
  final Map<String, Tournament> tournaments = {};

  bool loaded = false;
  Object? loadError;
  Timer? _saveTimer;

  Future<void> load() async {
    if (_saveTimer != null) await saveNow(); // never lose a change that was about to be saved
    try {
      final data = await _store.read();
      players.clear();
      teams.clear();
      matches.clear();
      tournaments.clear();
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
        for (final t in (data['tournaments'] as List? ?? const [])) {
          final tr = Tournament.fromJson(Map<String, dynamic>.from(t as Map));
          tournaments[tr.id] = tr;
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
        'tournaments': [for (final t in tournaments.values) t.toJson()],
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

  /// This phone's own teams (not ones from followed matches), by name.
  List<Team> get teamList => teams.values.where((t) => !t.remote).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

  void updatePlayer(Player p, {String? name, bool? leftHanded, String? role, String? phone}) {
    if (name != null && name.trim().isNotEmpty) p.name = name.trim();
    if (phone != null) p.phone = cleanPhone(phone);
    if (leftHanded != null) p.leftHanded = leftHanded;
    if (role != null) p.role = role;
    _changed();
  }

  /// Sets or clears (null) a player's photo. The old picture file is removed.
  Future<void> setPlayerPhoto(Player p, String? fileName) async {
    final old = p.photo;
    p.photo = fileName;
    _changed();
    if (old != null && old != fileName) await PhotoStore.delete(old);
  }

  /// Sets or clears (null) a team's logo. The old picture file is removed.
  Future<void> setTeamLogo(Team t, String? fileName) async {
    final old = t.logo;
    t.logo = fileName;
    _changed();
    if (old != null && old != fileName) await PhotoStore.delete(old);
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
    String? tournamentId,
    String? fixtureId,
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
      tournamentId: tournamentId,
      fixtureId: fixtureId,
    );
    matches[m.id] = m;
    if (tournamentId != null && fixtureId != null) {
      final f = tournaments[tournamentId]?.fixture(fixtureId);
      if (f != null) {
        f.matchId = m.id;
        f.teamA ??= a.id;
        f.teamB ??= b.id;
      }
    }
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
    for (final t in tournaments.values) {
      for (final f in t.fixtures) {
        if (f.matchId == id) f.matchId = null;
      }
    }
    _changed();
  }

  // ---------- followed matches ----------

  /// Stores (or refreshes) a match followed from a live link. Data that
  /// belongs to this phone is never overwritten.
  void upsertRemote(Map<String, dynamic> data) {
    final mj = data['match'];
    if (mj is! Map) return;
    final id = mj['id'];
    if (id is! String) return;
    final mine = matches[id];
    if (mine != null && !mine.remote) return; // this phone scores it
    for (final t in (data['teams'] as List? ?? const [])) {
      final team = Team.fromJson({...Map<String, dynamic>.from(t as Map), 'remote': true});
      final local = teams[team.id];
      if (local != null && !local.remote) continue;
      if (local != null) team.logo = local.logo;
      teams[team.id] = team;
    }
    for (final pj in (data['players'] as List? ?? const [])) {
      final pl = Player.fromJson({...Map<String, dynamic>.from(pj as Map), 'remote': true});
      final local = players[pl.id];
      if (local != null && !local.remote) continue;
      if (local != null) pl.photo = local.photo;
      players[pl.id] = pl;
    }
    final record = MatchRecord.fromJson({...Map<String, dynamic>.from(mj), 'remote': true});
    if (mine != null) record.celebrated.addAll(mine.celebrated);
    matches[id] = record;
    _changed();
  }

  /// What a match looks like online (no photos, no logos).
  Map<String, dynamic> cloudData(MatchRecord m) {
    final ids = {...m.playersA, ...m.playersB};
    final json = m.toJson()..remove('celebrated');
    return {
      'match': json,
      'teams': [for (final t in [teams[m.teamA], teams[m.teamB]]) if (t != null) t.toCloud()],
      'players': [for (final id in ids) if (players[id] != null) players[id]!.toCloud()],
    };
  }

  // ---------- tournaments ----------

  List<Tournament> get tournamentList => tournaments.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Tournament addTournament({
    required String name,
    required String format,
    required int overs,
    required List<String> teamIds,
    int groupCount = 2,
    int qualifiers = 2,
    String category = 'open',
    String venue = '',
  }) {
    final t = createTournament(
      id: newId(),
      name: name.trim(),
      format: format,
      overs: overs,
      teamIds: teamIds,
      groupCount: groupCount,
      qualifiers: qualifiers,
      category: category,
      venue: venue.trim(),
    );
    tournaments[t.id] = t;
    _changed();
    return t;
  }

  void pickWinner(Tournament t, Fixture f, String teamId) {
    f.winnerOverride = teamId;
    _changed();
  }

  /// Removes the tournament. Its matches stay as ordinary matches.
  void deleteTournament(String id) {
    tournaments.remove(id);
    _changed();
  }

  TournamentView viewOf(Tournament t) {
    final states = <String, MatchState>{};
    final teams = <String, List<String>>{};
    for (final f in t.fixtures) {
      final m = f.matchId == null ? null : matches[f.matchId];
      if (m == null) continue;
      states[m.id] = m.state;
      teams[m.id] = [m.teamA, m.teamB];
    }
    return TournamentView(t, states, teams);
  }

  /// Replaces everything on this phone with the data from a backup.
  Future<void> restoreFrom(Map<String, dynamic> data) async {
    await _store.write(data);
    await load();
  }

  /// Removes everything saved on this phone.
  Future<void> deleteAll() async {
    players.clear();
    teams.clear();
    matches.clear();
    tournaments.clear();
    notifyListeners();
    await saveNow();
    await PhotoStore.deleteAll();
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
