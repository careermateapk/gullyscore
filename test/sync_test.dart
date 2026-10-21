import 'package:flutter_test/flutter_test.dart';
import 'package:gullyscore/data/cloud.dart';
import 'package:gullyscore/data/repository.dart';
import 'package:gullyscore/data/sync.dart';
import 'package:gullyscore/scoring/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the Cloudflare service.
class FakeCloud implements CloudApi {
  final matches = <String, Map<String, dynamic>>{};
  final owner = <String, String>{};
  final invites = <String, Invite>{};
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
        if ((e.value['players'] as List).contains(playerId))
          MatchListItem(id: e.key, updated: e.value['updated'] as int, finished: e.value['finished'] as bool, title: '', summary: Map<String, dynamic>.from(e.value['summary'] as Map)),
    ];
  }

  @override
  Future<String> createInvite(String auth, {required String playerId, required String name, required String team}) async {
    _check();
    final code = 'CODE${invites.length + 1}';
    invites[code] = Invite(playerId: playerId, name: name, team: team);
    return code;
  }

  @override
  Future<Invite> getInvite(String code) async {
    _check();
    final i = invites[code.toUpperCase()];
    if (i == null) throw CloudError(404, 'none');
    return i;
  }
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

  test('invite code links a player phone to their matches', () async {
    final cloud = FakeCloud();
    final r = await repoWithMatch();
    final sync = SyncService(r, cloud);
    await sync.start(timers: false);
    final ravi = r.players.values.firstWhere((p) => p.name == 'Ravi');
    final inv = await sync.invite(ravi);
    expect(inv.link, 'https://gs.test/p/${inv.code}');

    SharedPreferences.setMockInitialValues({});
    final phone = Repository(store: MemoryStore());
    await phone.load();
    final mine = SyncService(phone, cloud);
    await mine.start(timers: false);
    await mine.linkProfile(inv.code.toLowerCase());
    expect(mine.linkedName, 'Ravi');
    final list = await mine.myMatches();
    expect(list.length, 1);
    await r.saveNow();
  });

  test('links and ids are recognised', () {
    expect(SyncService.matchIdFrom('https://gullyscore-api.x.workers.dev/m/abc123'), 'abc123');
    expect(SyncService.matchIdFrom('see https://a.b/m/k9_z-1 now'), 'k9_z-1');
    expect(SyncService.matchIdFrom('abc123'), 'abc123');
    expect(SyncService.matchIdFrom('hello world'), isNull);
  });
}
