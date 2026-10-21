import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/data/cloud.dart';
import 'package:gullyscore/data/google_auth.dart';
import 'package:gullyscore/data/models.dart';
import 'package:gullyscore/data/repository.dart';
import 'package:gullyscore/data/sync.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the Cloudflare service.
class FakeCloud implements CloudApi {
  final matches = <String, Map<String, dynamic>>{};
  final owner = <String, String>{};
  final phones = <String, List<Map<String, String>>>{}; // scorer auth → list
  final userPhone = <String, String>{}; // user token → phone
  final status = <String, String>{}; // 'token|auth|player' → pending/ok/no
  var phoneUploads = 0;
  var clock = 1000;
  var offline = false;
  var registered = 0;

  void _check() {
    if (offline) throw CloudError(0, 'offline');
  }

  @override
  bool get enabled => true;
  @override
  String get baseUrl => 'https://gs.test';

  @override
  Future<({String scorerId, String token})> register() async {
    _check();
    registered++;
    return (scorerId: 's$registered', token: 't$registered');
  }

  @override
  Future<int> putMatch(String auth, String id, Map<String, dynamic> body) async {
    _check();
    if (owner[id] != null && owner[id] != auth) throw CloudError(403, 'not yours');
    owner[id] = auth;
    matches[id] = {...body, 'updated': ++clock};
    return clock;
  }

  @override
  Future<void> deleteMatch(String auth, String id) async {
    _check();
    matches.remove(id);
  }

  @override
  Future<RemoteMatch?> getMatch(String id, {int since = 0}) async {
    _check();
    final m = matches[id];
    if (m == null) throw CloudError(404, 'none');
    if (since >= (m['updated'] as int)) return null;
    return RemoteMatch(
      updated: m['updated'] as int,
      finished: m['finished'] as bool,
      summary: Map<String, dynamic>.from(m['summary'] as Map),
      data: Map<String, dynamic>.from(m['data'] as Map),
    );
  }

  @override
  Future<List<MatchListItem>> playerMatches(String playerId) async {
    _check();
    return [
      for (final e in matches.entries)
        if ((e.value['players'] as List).map((x) => x is Map ? x['id'] : x).contains(playerId))
          MatchListItem(id: e.key, updated: e.value['updated'] as int, finished: e.value['finished'] as bool, title: '', summary: Map<String, dynamic>.from(e.value['summary'] as Map)),
    ];
  }

  void _makeClaims() {
    for (final u in userPhone.entries) {
      for (final e in phones.entries) {
        for (final pl in e.value) {
          if (pl['phone'] == u.value) status.putIfAbsent('${u.key}|${e.key}|${pl['id']}', () => 'ok');
        }
      }
    }
  }

  @override
  Future<void> putPlayerPhones(String auth, List<Map<String, String>> players) async {
    _check();
    phoneUploads++;
    phones[auth] = players;
    _makeClaims();
  }

  @override
  Future<List<Claim>> claims(String auth) async {
    _check();
    return [
      for (final e in status.entries)
        if (e.value == 'ok' && e.key.split('|')[1] == auth)
          Claim(userId: e.key.split('|')[0], playerId: e.key.split('|')[2], email: 'ravi@gmail.com', name: 'Ravi K'),
    ];
  }

  @override
  Future<void> answerClaim(String auth, Claim c, bool yes) async {
    _check();
    status['${c.userId}|$auth|${c.playerId}'] = yes ? 'ok' : 'no';
  }

  MeInfo _me(String token) {
    final mine = status.entries.where((e) => e.key.startsWith('$token|')).toList();
    final okPlayers = mine.where((e) => e.value == 'ok').map((e) => e.key.split('|')[2]).toSet();
    return MeInfo(
      email: 'ravi@gmail.com',
      name: 'Ravi K',
      hasPhone: userPhone.containsKey(token),
      profiles: [for (final e in mine) MyProfile(name: 'Ravi', team: '', status: e.value)],
      matches: [
        for (final e in matches.entries)
          if ((e.value['players'] as List).map((x) => x is Map ? x['id'] : x).any(okPlayers.contains))
            MatchListItem(id: e.key, updated: e.value['updated'] as int, finished: e.value['finished'] as bool, title: '', summary: Map<String, dynamic>.from(e.value['summary'] as Map)),
      ],
      token: token,
    );
  }

  @override
  Future<MeInfo> login(String idToken) async {
    _check();
    if (idToken != 'google-ok') throw CloudError(401, 'bad');
    return _me('Uravi');
  }

  @override
  Future<MeInfo> me(String userToken) async {
    _check();
    return _me(userToken);
  }

  @override
  Future<MeInfo> setMyPhone(String userToken, String phone, {String? scorerAuth}) async {
    _check();
    userPhone[userToken] = phone;
    _makeClaims();
    return _me(userToken);
  }

  @override
  Future<void> logout(String userToken) async {}
}

class FakeGoogle implements GoogleAuth {
  var signedOut = false;
  @override
  bool get available => true;
  @override
  Future<String> idToken() async => 'google-ok';
  @override
  Future<void> signOut() async => signedOut = true;
}

Future<Repository> repoWithMatch() async {
  final r = Repository(store: MemoryStore());
  await r.load();
  final a = r.addTeam('Rajnagar XI', playerNames: ['Ravi', 'Raju', 'Rohit']);
  final b = r.addTeam('Madhubani Strikers', playerNames: ['Sanjay', 'Vikas', 'Amit']);
  r.createMatch(a: a, b: b, playersA: a.playerIds, playersB: b.playerIds, overs: 2, firstBatting: 0, title: 'MPL');
  return r;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('matches go online, then a second phone follows them live', () async {
    final cloud = FakeCloud();
    final scorer = await repoWithMatch();
    final sync = SyncService(scorer, cloud);
    await sync.start(timers: false);
    await sync.tick();
    final m = scorer.matchList.first;
    expect(cloud.matches.containsKey(m.id), true);
    expect(sync.isOnline(m.id), true);
    expect(sync.liveLink(m.id), 'https://gs.test/m/${m.id}');

    // Second phone.
    SharedPreferences.setMockInitialValues({});
    final viewerRepo = Repository(store: MemoryStore());
    await viewerRepo.load();
    final viewer = SyncService(viewerRepo, cloud);
    await viewer.start(timers: false);
    final id = await viewer.follow('Live score: https://gs.test/m/${m.id}');
    expect(id, m.id);
    expect(viewerRepo.matches[id]!.remote, true);
    expect(viewerRepo.teamList, isEmpty, reason: 'followed teams do not mix with your own');
    expect(viewerRepo.teamName(m.teamA), 'Rajnagar XI');

    // Scorer scores a four; viewer sees it after its next refresh.
    scorer.addEvent(m, {'t': Ev.start, 'striker': m.playersA[0], 'nonStriker': m.playersA[1], 'bowler': m.playersB[0]});
    scorer.addEvent(m, {'t': Ev.ball, 'kind': BallKind.normal, 'runs': 4});
    await sync.tick();
    await viewer.tick();
    expect(viewerRepo.matches[id]!.state.current!.runs, 4);

    // The viewer never uploads someone else's match.
    expect(viewer.pending, isEmpty);
    await scorer.saveNow();
    await viewerRepo.saveNow();
  });

  test('no internet: scoring keeps going and uploads later', () async {
    final cloud = FakeCloud()..offline = true;
    final r = await repoWithMatch();
    final sync = SyncService(r, cloud);
    await sync.start(timers: false);
    await sync.tick();
    expect(sync.state, SyncState.offline);
    expect(sync.pending.length, 1);
    cloud.offline = false;
    await sync.tick();
    expect(sync.pending, isEmpty);
    expect(sync.state, SyncState.idle);
    await r.saveNow();
  });

  test('turning sharing off stops uploads', () async {
    final cloud = FakeCloud();
    final r = await repoWithMatch();
    final sync = SyncService(r, cloud);
    await sync.start(timers: false);
    sync.setShareOnline(false);
    await sync.tick();
    expect(cloud.matches, isEmpty);
    await r.saveNow();
  });

  test('deleting a match removes it online', () async {
    final cloud = FakeCloud();
    final r = await repoWithMatch();
    final sync = SyncService(r, cloud);
    await sync.start(timers: false);
    await sync.tick();
    final id = r.matchList.first.id;
    r.deleteMatch(id);
    await sync.tick();
    expect(cloud.matches.containsKey(id), false);
    await r.saveNow();
  });

  test('player logs in with Google + mobile and sees their matches at once', () async {
    final cloud = FakeCloud();
    final r = await repoWithMatch();
    final scorer = SyncService(r, cloud, google: FakeGoogle());
    await scorer.start(timers: false);
    await scorer.tick();
    expect(cloud.phoneUploads, 0, reason: 'nothing to send without numbers');

    final ravi = r.players.values.firstWhere((p) => p.name == 'Ravi');
    r.updatePlayer(ravi, phone: '+91 98765-43210');
    expect(ravi.phone, '9876543210');
    await scorer.tick();
    expect(cloud.phoneUploads, 1);
    await scorer.tick();
    expect(cloud.phoneUploads, 1, reason: 'unchanged numbers are not sent again');
    expect(cloud.matches.toString().contains('9876543210'), false, reason: 'number is not inside match data');

    // Ravi's own phone.
    SharedPreferences.setMockInitialValues({});
    final phone = Repository(store: MemoryStore());
    await phone.load();
    final google = FakeGoogle();
    final mine = SyncService(phone, cloud, google: google);
    await mine.start(timers: false);
    expect(mine.loggedIn, false);
    await mine.login();
    expect(mine.loggedIn, true);
    expect(mine.me!.hasPhone, false);
    await expectLater(mine.setMyPhone('12345'), throwsA(isA<CloudError>()));
    await mine.setMyPhone('09876543210');
    expect(mine.me!.profiles.single.approved, true);
    expect(mine.me!.matches.length, 1, reason: 'no approval needed');

    // The scorer sees the linked account on the player's profile and can remove it.
    await scorer.checkClaims();
    expect(scorer.claims.length, 1);
    await scorer.answerClaim(scorer.claims.single, false);
    expect(scorer.claims, isEmpty);
    final info = await mine.refreshMe();
    expect(info!.matches, isEmpty);

    await mine.logout();
    expect(mine.loggedIn, false);
    expect(google.signedOut, true);
    await r.saveNow();
  });

  test('mobile numbers are cleaned', () {
    expect(cleanPhone('+91 98765 43210'), '9876543210');
    expect(cleanPhone('098765-43210'), '9876543210');
    expect(cleanPhone('12345'), '');
    expect(cleanPhone(''), '');
  });

  test('links and ids are recognised', () {
    expect(SyncService.matchIdFrom('https://gullyscore-api.x.workers.dev/m/abc123'), 'abc123');
    expect(SyncService.matchIdFrom('see https://a.b/m/k9_z-1 now'), 'k9_z-1');
    expect(SyncService.matchIdFrom('abc123'), 'abc123');
    expect(SyncService.matchIdFrom('hello world'), isNull);
  });
}
