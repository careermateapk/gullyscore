// Talks to the GullyScore online service (Cloudflare). The address is set
// when the app is built; when it is empty, online features are hidden.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const cloudUrl = String.fromEnvironment('CLOUD_URL');

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

class MatchListItem {
  MatchListItem({required this.id, required this.updated, required this.finished, required this.title, required this.summary});
  final String id;
  final int updated;
  final bool finished;
  final String title;
  final Map<String, dynamic> summary;
}

class Invite {
  Invite({required this.playerId, required this.name, required this.team});
  final String playerId;
  final String name;
  final String team;
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
  Future<String> createInvite(String auth, {required String playerId, required String name, required String team});
  Future<Invite> getInvite(String code);
}

class HttpCloud implements CloudApi {
  HttpCloud([String? url]) : baseUrl = (url ?? cloudUrl).replaceAll(RegExp(r'/+$'), '');

  @override
  final String baseUrl;

  @override
  bool get enabled => baseUrl.startsWith('https://');

  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

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
    return [
      for (final m in (j['matches'] as List? ?? const []))
        MatchListItem(
          id: m['id'] as String,
          updated: (m['updated'] as num).toInt(),
          finished: m['finished'] == true,
          title: (m['title'] as String?) ?? '',
          summary: Map<String, dynamic>.from(m['summary'] as Map),
        ),
    ];
  }

  @override
  Future<String> createInvite(String auth, {required String playerId, required String name, required String team}) async {
    final j = await _send('POST', '/v1/invites', body: {'playerId': playerId, 'name': name, 'team': team}, auth: auth);
    return j['code'] as String;
  }

  @override
  Future<Invite> getInvite(String code) async {
    final j = await _send('GET', '/v1/invites/${Uri.encodeComponent(code.trim().toUpperCase())}');
    return Invite(playerId: j['playerId'] as String, name: j['name'] as String, team: (j['team'] as String?) ?? '');
  }
}
