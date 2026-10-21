// Everything-online pieces of v0.5: the all-matches feed, team pages,
// leaderboard, Community posts, ratings, comments, reactions and replies.
import 'cloud.dart';

class Leader {
  Leader({required this.name, required this.team, required this.runs, required this.wickets, required this.matches, required this.best});
  final String name, team;
  final int runs, wickets, matches, best;
}

class Post {
  Post(this.j);
  final Map<String, dynamic> j;

  String get id => j['id'] as String;
  String get kind => j['kind'] as String; // players, opponent, poll, tournament, general
  String get body => (j['body'] as String?) ?? '';
  String get place => (j['place'] as String?) ?? '';
  DateTime get created => DateTime.fromMillisecondsSinceEpoch((j['created'] as num).toInt());
  String get author => ((j['author'] as Map?)?['name'] as String?) ?? '';
  bool get mine => j['mine'] == true;
  int get joins => (j['joins'] as num?)?.toInt() ?? 0;
  bool get joined => j['joined'] == true;
  bool get paid => j['paid'] == true;
  bool get hasContact => j['hasContact'] == true;
  String? get contact => j['contact'] as String?;
  Map<String, dynamic> get extra => Map<String, dynamic>.from((j['extra'] as Map?) ?? const {});
  List<String> get options => [for (final o in (extra['options'] as List? ?? const [])) '$o'];
  List<int> get votes => [for (final v in (j['votes'] as List? ?? const [])) (v as num).toInt()];
  int? get myVote => (j['myVote'] as num?)?.toInt();
}

class JoinRow {
  JoinRow({required this.userId, required this.name, required this.email, required this.note, required this.paid});
  final String userId, name, email, note;
  bool paid;
}

class Comment {
  Comment(this.j);
  final Map<String, dynamic> j;

  String get id => j['id'] as String;
  String? get parentId => j['parentId'] as String?;
  String get author => ((j['author'] as Map?)?['name'] as String?) ?? '';
  String get authorTeam => ((j['author'] as Map?)?['team'] as String?) ?? '';
  bool get isTeam => j['isTeam'] == true;
  double get stars => (j['stars'] as num?)?.toDouble() ?? 0;
  String get body => (j['body'] as String?) ?? '';
  DateTime get created => DateTime.fromMillisecondsSinceEpoch((j['created'] as num).toInt());
  bool get mine => j['mine'] == true;
  List<(String, int)> get reactions => [for (final r in (j['reactions'] as List? ?? const [])) ('${r['emoji']}', (r['n'] as num).toInt())];
  String? get myReaction => j['myReaction'] as String?;
  int get replies => (j['replies'] as num?)?.toInt() ?? 0;
  List<Comment> get firstReplies => [for (final r in (j['firstReplies'] as List? ?? const [])) Comment(Map<String, dynamic>.from(r as Map))];
}

class TeamRatings {
  TeamRatings(this.j);
  final Map<String, dynamic> j;
  int get count => (j['count'] as num?)?.toInt() ?? 0;
  double? get overall => (j['overall'] as num?)?.toDouble();
  double? get fair => (j['fair'] as num?)?.toDouble();
  double? get behaviour => (j['behaviour'] as num?)?.toDouble();
  double? get ontime => (j['ontime'] as num?)?.toDouble();
  Map<String, int> get tags => {for (final e in ((j['tags'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
  List<Comment> get comments => [for (final c in (j['comments'] as List? ?? const [])) Comment(Map<String, dynamic>.from(c as Map))];
}

class RatingTarget {
  RatingTarget(this.j);
  final Map<String, dynamic> j;
  bool get canRate => j['canRate'] == true;
  bool get rated => j['rated'] == true;
  String get scorerId => (j['scorerId'] as String?) ?? '';
  TeamRef? get team => j['team'] is Map ? TeamRef('${j['team']['id']}', '${j['team']['name']}') : null;
}

const reactionEmojis = ['👍', '❤️', '😂', '🔥', '👏', '😮'];
const ratingTags = ['sportsmen', 'tough', 'late', 'again'];

typedef Sender = Future<Map<String, dynamic>> Function(String method, String path, {Object? body, String? auth});

class SocialApi {
  SocialApi(this._send, this._token);
  final Sender _send;
  final String? Function() _token; // logged-in player's token, if any

  String _need() {
    final t = _token();
    if (t == null) throw CloudError(401, 'not logged in');
    return t;
  }

  Future<({List<MatchListItem> matches, int live, int upcoming})> feed(String kind, {int before = 0}) async {
    final j = await _send('GET', '/v1/feed?kind=$kind${before > 0 ? '&before=$before' : ''}');
    final c = (j['counts'] as Map?) ?? const {};
    return (
      matches: [for (final m in (j['matches'] as List? ?? const [])) parseMatchItem(m)],
      live: (c['live'] as num?)?.toInt() ?? 0,
      upcoming: (c['upcoming'] as num?)?.toInt() ?? 0,
    );
  }

  Future<TeamSummary> team(String scorerId, String teamId) async =>
      TeamSummary.fromJson(await _send('GET', '/v1/teams/${Uri.encodeComponent(scorerId)}/${Uri.encodeComponent(teamId)}'));

  Future<List<Leader>> leaderboard({required String kind, int days = 0}) async {
    final j = await _send('GET', '/v1/leaderboard?kind=$kind&days=$days');
    return [
      for (final p in (j['players'] as List? ?? const []))
        Leader(
          name: '${p['name']}',
          team: '${p['team'] ?? ''}',
          runs: (p['runs'] as num?)?.toInt() ?? 0,
          wickets: (p['wickets'] as num?)?.toInt() ?? 0,
          matches: (p['matches'] as num?)?.toInt() ?? 0,
          best: (p['best'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  // ----- Community -----
  Future<List<Post>> posts({String kind = '', int before = 0}) async {
    final q = [if (kind.isNotEmpty) 'kind=$kind', if (before > 0) 'before=$before'].join('&');
    final j = await _send('GET', '/v1/posts${q.isEmpty ? '' : '?$q'}', auth: _token());
    return [for (final p in (j['posts'] as List? ?? const [])) Post(Map<String, dynamic>.from(p as Map))];
  }

  Future<Post> createPost(Map<String, dynamic> body) async => Post(await _send('POST', '/v1/posts', body: body, auth: _need()));
  Future<void> deletePost(String id) async => _send('DELETE', '/v1/posts/$id', auth: _need());
  Future<Post> join(String id, {bool join = true, String note = ''}) async =>
      Post(await _send('POST', '/v1/posts/$id/join', body: {'join': join, 'note': note}, auth: _need()));
  Future<Post> vote(String id, int option) async => Post(await _send('POST', '/v1/posts/$id/vote', body: {'option': option}, auth: _need()));

  Future<List<JoinRow>> joins(String id) async {
    final j = await _send('GET', '/v1/posts/$id/joins', auth: _need());
    return [
      for (final r in (j['joins'] as List? ?? const []))
        JoinRow(userId: '${r['userId']}', name: '${r['name'] ?? ''}', email: '${r['email'] ?? ''}', note: '${r['note'] ?? ''}', paid: r['paid'] == true),
    ];
  }

  Future<void> setPaid(String postId, String userId, bool paid) async =>
      _send('POST', '/v1/posts/$postId/paid', body: {'userId': userId, 'paid': paid}, auth: _need());

  // ----- Ratings, comments -----
  Future<RatingTarget> ratingTarget(String matchId) async => RatingTarget(await _send('GET', '/v1/matches/${Uri.encodeComponent(matchId)}/rating', auth: _need()));

  Future<void> rate(String matchId, {required int fair, required int behaviour, required int ontime, required List<String> tags, String comment = ''}) async =>
      _send('POST', '/v1/matches/${Uri.encodeComponent(matchId)}/rating',
          body: {'fair': fair, 'behaviour': behaviour, 'ontime': ontime, 'tags': tags, 'comment': comment}, auth: _need());

  Future<TeamRatings> teamRatings(String scorerId, String teamId, {String sort = 'new'}) async =>
      TeamRatings(await _send('GET', '/v1/teams/${Uri.encodeComponent(scorerId)}/${Uri.encodeComponent(teamId)}/ratings?sort=$sort', auth: _token()));

  Future<List<Comment>> replies(String commentId) async {
    final j = await _send('GET', '/v1/comments/$commentId/replies', auth: _token());
    return [for (final r in (j['replies'] as List? ?? const [])) Comment(Map<String, dynamic>.from(r as Map))];
  }

  Future<Comment> reply(String commentId, String body) async => Comment(await _send('POST', '/v1/comments/$commentId/replies', body: {'body': body}, auth: _need()));
  Future<Comment> react(String commentId, String? emoji) async => Comment(await _send('POST', '/v1/comments/$commentId/react', body: {'emoji': emoji}, auth: _need()));
  Future<void> deleteComment(String id) async => _send('DELETE', '/v1/comments/$id', auth: _need());
  Future<void> report(String kind, String id, {String reason = ''}) async => _send('POST', '/v1/reports', body: {'kind': kind, 'id': id, 'reason': reason}, auth: _need());
  Future<void> deleteAccount() async => _send('DELETE', '/v1/me/account', auth: _need());
}
