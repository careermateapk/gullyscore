// Talks to the GullyScore online service (Cloudflare). The address is set
// when the app is built; when it is empty, online features are hidden.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const cloudUrl = String.fromEnvironment('CLOUD_URL');

/// Google "Web application" client ID used for player login (empty = login off).
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

class CloudError implements Exception {
  CloudError(this.status, this.message);
  final int status; // 0 = no internet / no answer
  final String message;

  bool get offline => status == 0;

  @override
  String toString() => 'CloudError($status, $message)';
}

class RemoteMatch {
  RemoteMatch({required this.updated, required this.finished, required this.summary, required this.data});
  final int updated;
  final bool finished;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> data;
}

class TeamRef {
  const TeamRef(this.id, this.name);
  final String id;
  final String name;
}

/// A match in a list (feed, My Cricket, team page).
class MatchListItem {
  MatchListItem({
    required this.id,
    required this.updated,
    required this.finished,
    required this.title,
    required this.summary,
    this.status = '',
    this.scheduled,
    this.ground = '',
    this.teamA = const TeamRef('', ''),
    this.teamB = const TeamRef('', ''),
    this.winner = '',
    this.me,
  });
  final String id;
  final int updated;
  final bool finished;
  final String title;
  final Map<String, dynamic> summary;
  final String status; // upcoming, live, result
  final DateTime? scheduled;
  final String ground;
  final TeamRef teamA;
  final TeamRef teamB;
  final String winner; // team id, 'tie' or ''
  final Map<String, dynamic>? me; // my numbers (My Cricket): r, b, 4s, 6s, notOut, w, o, rc, team

  bool get live => status == 'live' || (status.isEmpty && !finished);
  bool get upcoming => status == 'upcoming';
  String get headline => '${summary['status'] ?? ''}';
}

MatchListItem _item(dynamic m) {
  TeamRef team(dynamic t) => t is Map ? TeamRef('${t['id'] ?? ''}', '${t['name'] ?? ''}') : const TeamRef('', '');
  final sch = m['scheduled'];
  return MatchListItem(
    id: m['id'] as String,
    updated: (m['updated'] as num).toInt(),
    finished: m['finished'] == true,
    title: (m['title'] as String?) ?? '',
    summary: Map<String, dynamic>.from((m['summary'] as Map?) ?? const {}),
    status: (m['status'] as String?) ?? '',
    scheduled: sch is num ? DateTime.fromMillisecondsSinceEpoch(sch.toInt()) : null,
    ground: (m['ground'] as String?) ?? '',
    teamA: team(m['teamA']),
    teamB: team(m['teamB']),
    winner: (m['winner'] as String?) ?? '',
    me: m['me'] is Map ? Map<String, dynamic>.from(m['me'] as Map) : null,
  );
}

MatchListItem parseMatchItem(dynamic m) => _item(m);

/// One of my teams: record, form, next match, rating, matches.
class TeamSummary {
  TeamSummary({
    required this.scorerId,
    required this.id,
    required this.name,
    required this.played,
    required this.won,
    required this.lost,
    required this.form,
    required this.next,
    required this.rating,
    required this.ratings,
    required this.matches,
  });
  final String scorerId;
  final String id;
  final String name;
  final int played, won, lost;
  final List<String> form; // newest first: W, L, T
  final MatchListItem? next;
  final double? rating;
  final int ratings;
  final List<MatchListItem> matches;

  factory TeamSummary.fromJson(Map<String, dynamic> j) => TeamSummary(
        scorerId: (j['scorerId'] as String?) ?? '',
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        played: (j['played'] as num?)?.toInt() ?? 0,
        won: (j['won'] as num?)?.toInt() ?? 0,
        lost: (j['lost'] as num?)?.toInt() ?? 0,
        form: [for (final f in (j['form'] as List? ?? const [])) '$f'],
        next: j['next'] == null ? null : _item(j['next']),
        rating: (j['rating'] as num?)?.toDouble(),
        ratings: (j['ratings'] as num?)?.toInt() ?? 0,
        matches: [for (final m in (j['matches'] as List? ?? const [])) _item(m)],
      );
}

class MyTotals {
  const MyTotals({this.matches = 0, this.runs = 0, this.wickets = 0, this.best = 0, this.bestNotOut = false});
  final int matches, runs, wickets, best;
  final bool bestNotOut;

  factory MyTotals.fromJson(Map<String, dynamic>? j) => j == null
      ? const MyTotals()
      : MyTotals(
          matches: (j['matches'] as num?)?.toInt() ?? 0,
          runs: (j['runs'] as num?)?.toInt() ?? 0,
          wickets: (j['wickets'] as num?)?.toInt() ?? 0,
          best: (j['best'] as num?)?.toInt() ?? 0,
          bestNotOut: j['bestNotOut'] == true,
        );
}

/// A player profile some scorer made with this person's mobile number.
class MyProfile {
  MyProfile({required this.name, required this.team, required this.status});
  final String name;
  final String team;
  final String status; // pending, ok, no

  bool get approved => status == 'ok';
  bool get waiting => status == 'pending';
}

/// What a logged-in player sees.
class MeInfo {
  MeInfo({
    this.id,
    required this.email,
    required this.name,
    required this.hasPhone,
    required this.profiles,
    required this.matches,
    this.token,
    this.teams = const [],
    this.totals = const MyTotals(),
  });
  final String? id; // used for this person's notifications
  final String email;
  final String name;
  final bool hasPhone;
  final List<MyProfile> profiles;
  final List<MatchListItem> matches;
  final String? token; // only after logging in
  final List<TeamSummary> teams;
  final MyTotals totals;

  factory MeInfo.fromJson(Map<String, dynamic> j) => MeInfo(
        id: j['id'] as String?,
        email: (j['email'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        hasPhone: j['hasPhone'] == true,
        profiles: [
          for (final p in (j['profiles'] as List? ?? const []))
            MyProfile(name: (p['name'] as String?) ?? '', team: (p['team'] as String?) ?? '', status: (p['status'] as String?) ?? 'pending'),
        ],
        matches: [for (final m in (j['matches'] as List? ?? const [])) _item(m)],
        token: j['token'] as String?,
        teams: [for (final t in (j['teams'] as List? ?? const [])) TeamSummary.fromJson(Map<String, dynamic>.from(t as Map))],
        totals: MyTotals.fromJson(j['totals'] is Map ? Map<String, dynamic>.from(j['totals'] as Map) : null),
      );
}

/// "This person says they are your player": waiting for the scorer's yes/no.
class Claim {
  Claim({required this.userId, required this.playerId, required this.email, required this.name});
  final String userId;
  final String playerId;
  final String email;
  final String name;
}

/// Everything the app asks of the online service (a fake is used in tests).
abstract class CloudApi {
  bool get enabled;
  String get baseUrl;
  Future<({String scorerId, String token})> register();
  Future<int> putMatch(String auth, String id, Map<String, dynamic> body);
  Future<void> deleteMatch(String auth, String id);

  /// Null when nothing changed since [since].
  Future<RemoteMatch?> getMatch(String id, {int since = 0});
  Future<List<MatchListItem>> playerMatches(String playerId);

  /// Scorer: the mobile numbers typed for this phone's players (replaces the old list).
  Future<void> putPlayerPhones(String auth, List<Map<String, String>> players);
  Future<List<Claim>> claims(String auth);
  Future<void> answerClaim(String auth, Claim c, bool yes);

  /// Player login with a Google sign-in token.
  Future<MeInfo> login(String idToken);
  Future<MeInfo> me(String userToken);
  Future<MeInfo> setMyPhone(String userToken, String phone, {String? scorerAuth});
  Future<void> logout(String userToken);
}

class HttpCloud implements CloudApi {
  HttpCloud([String? url]) : baseUrl = (url ?? cloudUrl).replaceAll(RegExp(r'/+$'), '');

  @override
  final String baseUrl;

  @override
  bool get enabled => baseUrl.startsWith('https://');

  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  /// Any call to the service (used by the community and ratings screens).
  Future<Map<String, dynamic>> send(String method, String path, {Object? body, String? auth}) => _send(method, path, body: body, auth: auth);

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, String? auth}) async {
    if (!enabled) throw CloudError(0, 'online is off');
    try {
      final req = await _http.openUrl(method, Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 12));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $auth');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      Map<String, dynamic> json;
      try {
        json = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {
        json = {'error': text};
      }
      if (res.statusCode >= 400) throw CloudError(res.statusCode, '${json['error'] ?? 'error'}');
      return json;
    } on CloudError {
      rethrow;
    } on SocketException catch (e) {
      throw CloudError(0, e.message);
    } on TimeoutException {
      throw CloudError(0, 'timeout');
    } on HttpException catch (e) {
      throw CloudError(0, e.message);
    } on HandshakeException catch (e) {
      throw CloudError(0, e.message);
    }
  }

  @override
  Future<({String scorerId, String token})> register() async {
    final j = await _send('POST', '/v1/register');
    return (scorerId: j['scorerId'] as String, token: j['token'] as String);
  }

  @override
  Future<int> putMatch(String auth, String id, Map<String, dynamic> body) async {
    final j = await _send('PUT', '/v1/matches/${Uri.encodeComponent(id)}', body: body, auth: auth);
    return (j['updated'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> deleteMatch(String auth, String id) async {
    await _send('DELETE', '/v1/matches/${Uri.encodeComponent(id)}', auth: auth);
  }

  @override
  Future<RemoteMatch?> getMatch(String id, {int since = 0}) async {
    final j = await _send('GET', '/v1/matches/${Uri.encodeComponent(id)}${since > 0 ? '?since=$since' : ''}');
    if (j['unchanged'] == true) return null;
    return RemoteMatch(
      updated: (j['updated'] as num).toInt(),
      finished: j['finished'] == true,
      summary: Map<String, dynamic>.from(j['summary'] as Map),
      data: Map<String, dynamic>.from(j['data'] as Map),
    );
  }

  @override
  Future<List<MatchListItem>> playerMatches(String playerId) async {
    final j = await _send('GET', '/v1/players/${Uri.encodeComponent(playerId)}/matches');
    return [for (final m in (j['matches'] as List? ?? const [])) _item(m)];
  }

  @override
  Future<void> putPlayerPhones(String auth, List<Map<String, String>> players) async {
    await _send('POST', '/v1/players/phones', body: {'players': players}, auth: auth);
  }

  @override
  Future<List<Claim>> claims(String auth) async {
    final j = await _send('GET', '/v1/claims', auth: auth);
    return [
      for (final c in (j['claims'] as List? ?? const []))
        Claim(userId: c['userId'] as String, playerId: c['playerId'] as String, email: (c['email'] as String?) ?? '', name: (c['name'] as String?) ?? ''),
    ];
  }

  @override
  Future<void> answerClaim(String auth, Claim c, bool yes) async {
    await _send('POST', '/v1/claims', body: {'userId': c.userId, 'playerId': c.playerId, 'ok': yes}, auth: auth);
  }

  @override
  Future<MeInfo> login(String idToken) async => MeInfo.fromJson(await _send('POST', '/v1/login', body: {'idToken': idToken}));

  @override
  Future<MeInfo> me(String userToken) async => MeInfo.fromJson(await _send('GET', '/v1/me', auth: userToken));

  @override
  Future<MeInfo> setMyPhone(String userToken, String phone, {String? scorerAuth}) async =>
      MeInfo.fromJson(await _send('PUT', '/v1/me/phone', body: {'phone': phone, if (scorerAuth != null) 'scorer': scorerAuth}, auth: userToken));

  @override
  Future<void> logout(String userToken) async {
    await _send('DELETE', '/v1/me', auth: userToken);
  }
}
