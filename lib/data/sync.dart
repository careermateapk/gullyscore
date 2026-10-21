// Keeps this phone's matches online (for live links and players' phones),
// follows other people's matches, and logs a player in (Google + their
// mobile number) so they see every match they played in.
// Scoring never waits for the internet: uploads happen in the background and
// are retried until they succeed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scoring/engine.dart';
import '../scoring/format.dart';
import 'cloud.dart';
import 'google_auth.dart';
import 'push.dart';
import 'social.dart';
import 'models.dart';
import 'repository.dart';

enum SyncState { off, idle, working, offline, error }

/// upcoming (not started yet), live, or result.
String matchStatusOnline(MatchRecord m, MatchState st) {
  if (st.finished) return 'result';
  if (m.tossPending || st.innings.isEmpty || (st.innings.length == 1 && st.innings[0].balls.isEmpty)) {
    return m.scheduledAt != null || m.tossPending ? 'upcoming' : 'live';
  }
  return 'live';
}

/// One player's numbers in a match, for My Cricket and the leaderboard.
Map<String, dynamic> playerLine(MatchState st, String id, String team, String name) {
  var runs = 0, balls = 0, fours = 0, sixes = 0, wkts = 0, bBalls = 0, bRuns = 0;
  var batted = false, bowled = false, out = false;
  var catches = 0, hatTrick = false;
  for (final inn in st.innings) {
    var run = 0; // wickets in a row for this bowler
    for (final b in inn.balls) {
      if (b.fielder == id && b.outKind == OutKind.caught) catches++;
      if (b.bowler != id || !b.legal) continue;
      if (b.isWicket && OutKind.creditsBowler(b.outKind!)) {
        run++;
        if (run >= 3) hatTrick = true;
      } else {
        run = 0;
      }
    }
    final b = inn.batters[id];
    if (b != null) {
      batted = true;
      runs += b.runs;
      balls += b.balls;
      fours += b.fours;
      sixes += b.sixes;
      out = out || b.out;
    }
    final w = inn.bowlers[id];
    if (w != null && w.balls + w.wides + w.noBalls > 0) {
      bowled = true;
      wkts += w.wickets;
      bBalls += w.balls;
      bRuns += w.runs;
    }
  }
  return {
    'id': id,
    'team': team,
    'name': name,
    'runs': runs,
    'wickets': wkts,
    'line': {
      if (batted) ...{'r': runs, 'b': balls, '4s': fours, '6s': sixes, 'notOut': !out},
      if (bowled) ...{'w': wkts, 'o': oversText(bBalls), 'rc': bRuns},
      if (catches > 0) 'ct': catches,
      if (hatTrick) 'hat': true,
    },
  };
}

class SyncService extends ChangeNotifier {
  SyncService(this.repo, this.cloud, {GoogleAuth? google, Sender? socialSender})
      : google = google ?? PluginGoogleAuth(),
        _socialSender = socialSender;

  final Sender? _socialSender; // tests

  final Repository repo;
  final CloudApi cloud;
  final GoogleAuth google;

  String? _scorerId;
  String? _token;
  bool shareOnline = true;
  final Map<String, int> _uploaded = {}; // match id → local updatedAt (ms) that is online
  final Set<String> following = {};
  final Map<String, int> _since = {}; // match id → server "updated" last seen

  // Player login (this phone's owner as a player).
  String? _userToken;
  MeInfo? me;
  String myPhone = '';

  // Scorer side: mobile numbers sent, and accounts linked to this phone's players.
  String _phonesSig = '';
  List<Claim> claims = const [];
  DateTime? _claimsAt;

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
      _userToken = p.getString('cloud.user');
      myPhone = p.getString('cloud.myPhone') ?? '';
      _phonesSig = p.getString('cloud.phonesSig') ?? '';
      final email = p.getString('cloud.userEmail');
      if (_userToken != null && email != null) {
        me = MeInfo(email: email, name: p.getString('cloud.userName') ?? '', hasPhone: myPhone.isNotEmpty, profiles: const [], matches: const []);
      }
    } catch (_) {}
    state = enabled ? SyncState.idle : SyncState.off;
    notifyListeners();
    if (!enabled) return;
    repo.addListener(_kick);
    if (!timers) return; // tests drive tick() themselves
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
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
    if (_timer != null) Timer(const Duration(milliseconds: 800), () => tick());
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
        await _sendPhones();
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
      await _refreshClaims();
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
    final sponsors = repo.sponsorsOf(m);
    if (sponsors.isNotEmpty) summary['sponsors'] = [for (final x in sponsors) x.toJson()];
    final r = st.finished ? st.result : null;
    return {
      'data': repo.cloudData(m),
      'summary': summary,
      'players': [
        for (final id in m.playersA) playerLine(st, id, m.teamA, repo.playerName(id)),
        for (final id in m.playersB) playerLine(st, id, m.teamB, repo.playerName(id)),
      ],
      'finished': st.finished,
      'title': m.title,
      'status': matchStatusOnline(m, st),
      if (m.scheduledAt != null) 'scheduled': m.scheduledAt!.millisecondsSinceEpoch,
      'ground': m.venue,
      if (m.groundId.isNotEmpty) 'groundId': m.groundId,
      'teamA': {'id': m.teamA, 'name': repo.teamName(m.teamA)},
      'teamB': {'id': m.teamB, 'name': repo.teamName(m.teamB)},
      'winner': r == null ? '' : (r.tie ? 'tie' : (r.winner == null ? '' : (r.winner == 0 ? m.teamA : m.teamB))),
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
    unawaited(updatePush());
    return id;
  }

  void unfollow(String id) {
    following.remove(id);
    _savePrefs();
    notifyListeners();
    unawaited(updatePush());
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

  // ---------- Scorer: players' mobile numbers ----------

  /// Every player of this phone's teams (the squad), with the mobile number when typed.
  List<Map<String, String>> _phoneList() {
    final list = <Map<String, String>>[];
    for (final t in repo.teams.values) {
      if (t.remote) continue;
      for (final id in t.playerIds) {
        final p = repo.players[id];
        if (p == null || p.remote) continue;
        list.add({'id': p.id, 'name': p.name, 'team': t.name, 'teamId': t.id, 'phone': p.phone});
      }
    }
    list.sort((a, b) => a['id']!.compareTo(b['id']!));
    return list;
  }

  bool get _anyPhone => _phoneList().any((e) => e['phone']!.isNotEmpty);

  Future<void> _sendPhones() async {
    if (!repo.loaded) return;
    final list = _phoneList();
    if (_phonesSig.isEmpty && !list.any((e) => e['phone']!.isNotEmpty)) return; // nothing to link yet
    final sig = list.map((e) => '${e['id']}|${e['phone']}|${e['name']}|${e['team']}|${e['teamId']}').join(';');
    if (sig == _phonesSig) return;
    final auth = await _ensureIdentity();
    await cloud.putPlayerPhones(auth, list);
    _phonesSig = sig;
    _claimsAt = null; // refresh linked accounts right away
    await _prefs?.setString('cloud.phonesSig', sig);
  }

  Future<void> _refreshClaims({bool force = false}) async {
    final auth = _auth;
    if (auth == null || _phonesSig.isEmpty) {
      if (claims.isNotEmpty) claims = const [];
      return;
    }
    final at = _claimsAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(seconds: 30)) return;
    _claimsAt = DateTime.now();
    claims = await cloud.claims(auth);
  }

  /// Asks the server for linked accounts now (player profile calls this).
  Future<void> checkClaims() async {
    if (!enabled) return;
    try {
      await _refreshClaims(force: true);
      notifyListeners();
    } catch (_) {}
  }

  /// The scorer keeps (yes) or removes (no) an account linked to their player.
  Future<void> answerClaim(Claim c, bool yes) async {
    final auth = await _ensureIdentity();
    await cloud.answerClaim(auth, c, yes);
    claims = [for (final x in claims) if (x.userId != c.userId || x.playerId != c.playerId) x];
    notifyListeners();
  }

  // ---------- Player login ----------

  bool get loginAvailable => enabled && google.available;

  /// Feed, community, ratings (calls the service directly).
  late final SocialApi social = SocialApi(
    _socialSender ??
        (method, path, {body, auth}) {
      final c = cloud;
      if (c is HttpCloud) return c.send(method, path, body: body, auth: auth);
      return Future.error(CloudError(0, 'online is off'));
    },
    () => _userToken,
  );

  // ---------- Notifications ----------

  final PushService push = PushService();

  /// Topics this phone should be in right now.
  Set<String> get pushTopics => wantedTopics(
        on: push.on,
        teams: [for (final t in me?.teams ?? const <TeamSummary>[]) (t.scorerId, t.id)],
        followed: following,
        userId: me?.id,
      );

  Future<void> updatePush() => push.apply(pushTopics);

  /// Settings → Delete my account: removes the login and everything posted.
  Future<void> deleteAccount() async {
    await social.deleteAccount();
    await _forgetUser();
    await google.signOut();
  }
  bool get loggedIn => _userToken != null;

  Future<void> _saveMe(MeInfo info) async {
    me = info;
    unawaited(updatePush());
    await _prefs?.setString('cloud.userEmail', info.email);
    await _prefs?.setString('cloud.userName', info.name);
    notifyListeners();
  }

  /// Google account picker, then our server. Throws [GoogleLoginError] or [CloudError].
  Future<void> login() async {
    final idToken = await google.idToken();
    final info = await cloud.login(idToken);
    _userToken = info.token;
    await _prefs?.setString('cloud.user', info.token ?? '');
    await _saveMe(info);
    // Same person reinstalled the app: send their number again.
    if (myPhone.isNotEmpty && !info.hasPhone) await setMyPhone(myPhone);
  }

  /// The player's own mobile number: links every profile scorers made with it.
  Future<void> setMyPhone(String phone) async {
    final t = _userToken;
    if (t == null) throw CloudError(401, 'not logged in');
    final clean = cleanPhone(phone);
    if (clean.isEmpty) throw CloudError(400, 'bad phone');
    // If this phone also scores, send its numbers first so its own players link too.
    if (_anyPhone) await _sendPhones();
    final info = await cloud.setMyPhone(t, clean);
    myPhone = clean;
    await _prefs?.setString('cloud.myPhone', clean);
    await _saveMe(info);
  }

  Future<MeInfo?> refreshMe() async {
    final t = _userToken;
    if (t == null) return null;
    try {
      final info = await cloud.me(t);
      await _saveMe(info);
      return info;
    } on CloudError catch (e) {
      if (e.status == 401) await _forgetUser();
      rethrow;
    }
  }

  Future<void> logout() async {
    final t = _userToken;
    await _forgetUser();
    await google.signOut();
    if (t != null) {
      try {
        await cloud.logout(t);
      } catch (_) {}
    }
  }

  Future<void> _forgetUser() async {
    _userToken = null;
    me = null;
    await _prefs?.remove('cloud.user');
    await _prefs?.remove('cloud.userEmail');
    await _prefs?.remove('cloud.userName');
    notifyListeners();
    unawaited(updatePush());
  }
}
