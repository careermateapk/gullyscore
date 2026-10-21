// Keeps this phone's matches online (for live links and players' phones),
// follows other people's matches, and links this phone to a player profile.
// Scoring never waits for the internet: uploads happen in the background and
// are retried until they succeed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scoring/format.dart';
import 'cloud.dart';
import 'models.dart';
import 'repository.dart';

enum SyncState { off, idle, working, offline, error }

class SyncService extends ChangeNotifier {
  SyncService(this.repo, this.cloud);

  final Repository repo;
  final CloudApi cloud;

  String? _scorerId;
  String? _token;
  bool shareOnline = true;
  final Map<String, int> _uploaded = {}; // match id → local updatedAt (ms) that is online
  final Set<String> following = {};
  final Map<String, int> _since = {}; // match id → server "updated" last seen
  String? linkedPlayerId;
  String? linkedName;
  String? linkedTeam;

  SyncState state = SyncState.off;
  DateTime? lastOk;
  SharedPreferences? _prefs;
  Timer? _timer;
  bool _busy = false;

  bool get enabled => cloud.enabled;
  String? get _auth => _scorerId == null ? null : '$_scorerId.$_token';

  Future<void> start({bool timers = true}) async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      _scorerId = p.getString('cloud.id');
      _token = p.getString('cloud.token');
      shareOnline = p.getBool('cloud.share') ?? true;
      following.addAll(p.getStringList('cloud.following') ?? const []);
      for (final e in (p.getStringList('cloud.uploaded') ?? const [])) {
        final i = e.lastIndexOf('=');
        if (i > 0) _uploaded[e.substring(0, i)] = int.tryParse(e.substring(i + 1)) ?? 0;
      }
      linkedPlayerId = p.getString('cloud.me');
      linkedName = p.getString('cloud.meName');
      linkedTeam = p.getString('cloud.meTeam');
    } catch (_) {}
    state = enabled ? SyncState.idle : SyncState.off;
    notifyListeners();
    if (!enabled) return;
    repo.addListener(_kick);
    if (timers) _timer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
    unawaited(tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    repo.removeListener(_kick);
    super.dispose();
  }

  void _kick() {
    // Upload soon after a change, without blocking the scorer.
    Timer(const Duration(milliseconds: 800), () => tick());
  }

  void _savePrefs() {
    final p = _prefs;
    if (p == null) return;
    p.setStringList('cloud.uploaded', [for (final e in _uploaded.entries) '${e.key}=${e.value}']);
    p.setStringList('cloud.following', following.toList());
  }

  void setShareOnline(bool v) {
    shareOnline = v;
    _prefs?.setBool('cloud.share', v);
    notifyListeners();
    if (v) unawaited(tick());
  }

  Future<String> _ensureIdentity() async {
    final a = _auth;
    if (a != null) return a;
    final r = await cloud.register();
    _scorerId = r.scorerId;
    _token = r.token;
    await _prefs?.setString('cloud.id', r.scorerId);
    await _prefs?.setString('cloud.token', r.token);
    return '$_scorerId.$_token';
  }

  /// Matches of this phone that are newer than what is online.
  List<MatchRecord> get pending => [
        for (final m in repo.matches.values)
          if (!m.remote && (_uploaded[m.id] ?? 0) < m.updatedAt.millisecondsSinceEpoch) m,
      ];

  bool isOnline(String matchId) {
    final m = repo.matches[matchId];
    if (m == null) return false;
    if (m.remote) return true;
    return (_uploaded[matchId] ?? 0) >= m.updatedAt.millisecondsSinceEpoch;
  }

  /// One round of work: upload, remove deleted, refresh followed matches.
  Future<void> tick() async {
    if (!enabled || _busy) return;
    _busy = true;
    var changed = false;
    try {
      if (shareOnline) {
        final todo = repo.loaded ? pending : const <MatchRecord>[];
        if (todo.isNotEmpty) {
          state = SyncState.working;
          notifyListeners();
          final auth = await _ensureIdentity();
          for (final m in todo) {
            await cloud.putMatch(auth, m.id, _body(m));
            _uploaded[m.id] = m.updatedAt.millisecondsSinceEpoch;
            changed = true;
          }
        }
        // Matches deleted on this phone come down online too.
        final gone = repo.loaded ? _uploaded.keys.where((id) => !repo.matches.containsKey(id)).toList() : const <String>[];
        if (gone.isNotEmpty) {
          final auth = await _ensureIdentity();
          for (final id in gone) {
            await cloud.deleteMatch(auth, id);
            _uploaded.remove(id);
            changed = true;
          }
        }
      }
      await _refreshFollowing();
      state = SyncState.idle;
      lastOk = DateTime.now();
    } on CloudError catch (e) {
      state = e.offline ? SyncState.offline : SyncState.error;
    } catch (_) {
      state = SyncState.error;
    } finally {
      _busy = false;
      if (changed) _savePrefs();
      notifyListeners();
    }
  }

  Map<String, dynamic> _body(MatchRecord m) {
    final st = m.state;
    final summary = buildSummary(state: st, nameA: repo.teamName(m.teamA), nameB: repo.teamName(m.teamB), name: repo.playerName);
    if (m.title.isNotEmpty) summary['title'] = '${summary['title']} · ${m.title}';
    return {
      'data': repo.cloudData(m),
      'summary': summary,
      'players': [...m.playersA, ...m.playersB],
      'finished': st.finished,
      'title': m.title,
    };
  }

  Future<void> _refreshFollowing() async {
    for (final id in following.toList()) {
      final local = repo.matches[id];
      if (local != null && local.remote && local.state.finished && _since.containsKey(id)) continue;
      final r = await cloud.getMatch(id, since: _since[id] ?? 0);
      if (r == null) continue;
      _since[id] = r.updated;
      repo.upsertRemote(r.data);
    }
  }

  /// Start following a match from a link like ".../m/<id>" or a bare id.
  /// Returns the match id. Throws [CloudError] if it does not exist.
  Future<String> follow(String linkOrId) async {
    final id = matchIdFrom(linkOrId);
    if (id == null) throw CloudError(404, 'bad link');
    if (repo.matches[id] != null && !repo.matches[id]!.remote) return id; // it's ours
    final r = await cloud.getMatch(id);
    if (r == null) throw CloudError(404, 'no data');
    _since[id] = r.updated;
    repo.upsertRemote(r.data);
    following.add(id);
    _savePrefs();
    notifyListeners();
    return id;
  }

  void unfollow(String id) {
    following.remove(id);
    _savePrefs();
    notifyListeners();
  }

  static String? matchIdFrom(String text) {
    final t = text.trim();
    final m = RegExp(r'/m/([A-Za-z0-9_\-]+)').firstMatch(t);
    if (m != null) return m.group(1);
    if (RegExp(r'^[A-Za-z0-9_\-]{4,80}$').hasMatch(t)) return t;
    return null;
  }

  String liveLink(String matchId) => '${cloud.baseUrl}/m/$matchId';

  /// Makes sure a match is online now (used before sharing its link).
  Future<void> pushNow(String matchId) async {
    final m = repo.matches[matchId];
    if (m == null || m.remote) return;
    final auth = await _ensureIdentity();
    await cloud.putMatch(auth, m.id, _body(m));
    _uploaded[m.id] = m.updatedAt.millisecondsSinceEpoch;
    _savePrefs();
    notifyListeners();
  }

  /// Invite code (and web link) for one of this phone's players.
  Future<({String code, String link})> invite(Player p) async {
    final auth = await _ensureIdentity();
    // Their matches need to be online for them to see.
    for (final m in repo.matches.values) {
      if (!m.remote && (m.playersA.contains(p.id) || m.playersB.contains(p.id)) && !isOnline(m.id)) {
        await cloud.putMatch(auth, m.id, _body(m));
        _uploaded[m.id] = m.updatedAt.millisecondsSinceEpoch;
      }
    }
    _savePrefs();
    final team = repo.teams.values.where((t) => t.playerIds.contains(p.id)).map((t) => t.name).firstOrNull ?? '';
    final code = await cloud.createInvite(auth, playerId: p.id, name: p.name, team: team);
    return (code: code, link: '${cloud.baseUrl}/p/$code');
  }

  /// "This is me": links this phone to a player profile with an invite code.
  Future<Invite> linkProfile(String code) async {
    final inv = await cloud.getInvite(code);
    linkedPlayerId = inv.playerId;
    linkedName = inv.name;
    linkedTeam = inv.team;
    await _prefs?.setString('cloud.me', inv.playerId);
    await _prefs?.setString('cloud.meName', inv.name);
    await _prefs?.setString('cloud.meTeam', inv.team);
    notifyListeners();
    return inv;
  }

  Future<void> unlinkProfile() async {
    linkedPlayerId = null;
    linkedName = null;
    linkedTeam = null;
    await _prefs?.remove('cloud.me');
    await _prefs?.remove('cloud.meName');
    await _prefs?.remove('cloud.meTeam');
    notifyListeners();
  }

  /// Matches of the linked player, newest first.
  Future<List<MatchListItem>> myMatches() async {
    final id = linkedPlayerId;
    if (id == null) return const [];
    return cloud.playerMatches(id);
  }
}
