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

class AskPlayer {
  AskPlayer(this.playerId, this.name, this.answer);
  final String playerId, name, answer;
}

class Ask {
  Ask(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  String get title => (j['title'] as String?) ?? '';
  String get when => (j['when'] as String?) ?? '';
  String get place => (j['place'] as String?) ?? '';
  int get need => (j['need'] as num?)?.toInt() ?? 11;
  bool get mine => j['mine'] == true;
  String get myAnswer => (j['myAnswer'] as String?) ?? '';
  int get yes => (j['yes'] as num?)?.toInt() ?? 0;
  int get no => (j['no'] as num?)?.toInt() ?? 0;
  int get maybe => (j['maybe'] as num?)?.toInt() ?? 0;
  int get waiting => (j['waiting'] as num?)?.toInt() ?? 0;
  List<AskPlayer> get players => [for (final p in (j['players'] as List? ?? const [])) AskPlayer('${p['playerId']}', '${p['name']}', '${p['answer'] ?? ''}')];
}

class KhataItem {
  KhataItem(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  bool get expense => j['kind'] == 'expense';
  int get amount => (j['amount'] as num).toInt();
  String get note => (j['note'] as String?) ?? '';
  String get name => (j['name'] as String?) ?? '';
  DateTime get created => DateTime.fromMillisecondsSinceEpoch((j['created'] as num).toInt());
}

class KhataPerson {
  KhataPerson(this.playerId, this.name, this.paid, this.due);
  final String playerId, name;
  final int paid, due;
}

class Khata {
  Khata(this.j);
  final Map<String, dynamic> j;
  String get month => (j['month'] as String?) ?? '';
  int get spent => (j['spent'] as num?)?.toInt() ?? 0;
  int get share => (j['share'] as num?)?.toInt() ?? 0;
  int get players => (j['players'] as num?)?.toInt() ?? 0;
  int get pending => (j['pending'] as num?)?.toInt() ?? 0;
  List<KhataPerson> get people => [
        for (final p in (j['people'] as List? ?? const []))
          KhataPerson('${p['playerId']}', '${p['name']}', (p['paid'] as num).toInt(), (p['due'] as num).toInt()),
      ];
  List<KhataItem> get items => [for (final i in (j['items'] as List? ?? const [])) KhataItem(Map<String, dynamic>.from(i as Map))];
}

class Ground {
  Ground(this.j);
  final Map<String, dynamic> j;
  String get id => (j['id'] as String?) ?? '';
  String get name => (j['name'] as String?) ?? '';
  String get address => (j['address'] as String?) ?? '';
  String get city => (j['city'] as String?) ?? '';
  double get lat => (j['lat'] as num).toDouble();
  double get lng => (j['lng'] as num).toDouble();
  List<String> get pitches => [for (final x in (j['pitches'] as List? ?? const [])) '$x'];
  List<String> get facilities => [for (final x in (j['facilities'] as List? ?? const [])) '$x'];
  int get feeMin => (j['feeMin'] as num?)?.toInt() ?? 0;
  int get feeMax => (j['feeMax'] as num?)?.toInt() ?? 0;
  String get fee => (j['fee'] as String?) ?? '';
  int get boundaryMin => (j['boundaryMin'] as num?)?.toInt() ?? 0;
  int get boundaryMax => (j['boundaryMax'] as num?)?.toInt() ?? 0;
  String get timings => (j['timings'] as String?) ?? '';
  String get phone => (j['phone'] as String?) ?? '';
  String get phone2 => (j['phone2'] as String?) ?? '';
  bool get mine => j['mine'] == true;
  /// Came from the free map and nobody has filled in its details yet.
  bool get fromMap => j['fromMap'] == true;
  double? get km => (j['km'] as num?)?.toDouble();
  double? get rating => (j['rating'] as num?)?.toDouble();
  int get reviews => (j['reviews'] as num?)?.toInt() ?? 0;
  int get matches => (j['matches'] as num?)?.toInt() ?? 0;
  String? get photo => j['photo'] as String?;
  List<String> get photoIds => [for (final x in (j['photoIds'] as List? ?? const [])) '$x'];
  String get area => city.isNotEmpty ? city : address.split(',').first;
}

class Place {
  Place(this.name, this.detail, this.lat, this.lng);
  final String name, detail;
  final double lat, lng;
  Map<String, dynamic> toJson() => {'name': name, 'detail': detail, 'lat': lat, 'lng': lng};
  factory Place.fromJson(Map<String, dynamic> j) => Place('${j['name']}', '${j['detail'] ?? ''}', (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

class GroundReview {
  GroundReview(this.name, this.stars, this.body, this.created);
  final String name, body;
  final int stars;
  final DateTime created;
}

class GroundInsights {
  GroundInsights(this.j);
  final Map<String, dynamic> j;
  int get matches => (j['matches'] as num?)?.toInt() ?? 0;
  int? get avgFirst => (j['avgFirst'] as num?)?.toInt();
  Map<String, dynamic>? get highest => j['highest'] as Map<String, dynamic>?;
  Map<String, dynamic>? get lowest => j['lowest'] as Map<String, dynamic>?;
  int? get batFirstWinPct => (j['batFirstWinPct'] as num?)?.toInt();
  List<int> get days => [for (final d in (j['days'] as List? ?? const [0, 0, 0, 0, 0, 0, 0])) (d as num).toInt()];
  List<(String, int)> get topRuns => [for (final x in (j['topRuns'] as List? ?? const [])) ('${x['name']}', (x['value'] as num).toInt())];
  List<(String, int)> get topWickets => [for (final x in (j['topWickets'] as List? ?? const [])) ('${x['name']}', (x['value'] as num).toInt())];
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
  // ----- Team tools -----
  String _team(String s, String t) => '/v1/teams/${Uri.encodeComponent(s)}/${Uri.encodeComponent(t)}';

  Future<List<Ask>> asks(String scorerId, String teamId) async {
    final j = await _send('GET', '${_team(scorerId, teamId)}/asks', auth: _need());
    return [for (final a in (j['asks'] as List? ?? const [])) Ask(Map<String, dynamic>.from(a as Map))];
  }

  Future<Ask> createAsk(String scorerId, String teamId, {required String title, String when = '', String place = '', int need = 11}) async =>
      Ask(await _send('POST', '${_team(scorerId, teamId)}/asks', body: {'title': title, 'when': when, 'place': place, 'need': need}, auth: _need()));
  Future<Ask> answerAsk(String id, String answer) async => Ask(await _send('POST', '/v1/asks/$id/answer', body: {'answer': answer}, auth: _need()));
  Future<void> deleteAsk(String id) async => _send('DELETE', '/v1/asks/$id', auth: _need());

  Future<Khata> khata(String scorerId, String teamId, {String month = ''}) async =>
      Khata(await _send('GET', '${_team(scorerId, teamId)}/khata${month.isEmpty ? '' : '?month=$month'}', auth: _need()));
  Future<Khata> addKhata(String scorerId, String teamId, {required String kind, required int amount, required String playerId, String note = '', String month = ''}) async =>
      Khata(await _send('POST', '${_team(scorerId, teamId)}/khata',
          body: {'kind': kind, 'amount': amount, 'playerId': playerId, 'note': note, if (month.isNotEmpty) 'month': month}, auth: _need()));
  Future<Khata> deleteKhata(String id) async => Khata(await _send('DELETE', '/v1/khata/$id', auth: _need()));

  // ----- Grounds -----
  String photoUrl(String base, String groundId, String photoId) => '$base/v1/grounds/$groundId/photos/$photoId';

  Future<List<Place>> places(String q) async {
    final j = await _send('GET', '/v1/places?q=${Uri.encodeQueryComponent(q)}');
    return [for (final p in (j['places'] as List? ?? const [])) Place.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  Future<({int total, List<Ground> grounds})> grounds(
      {double? lat, double? lng, int km = 15, String q = '', List<String> pitch = const [], List<String> fac = const [], int? feeMax, String sort = 'distance'}) async {
    final params = [
      if (lat != null && lng != null) 'lat=$lat&lng=$lng',
      'km=$km',
      if (q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
      if (pitch.isNotEmpty) 'pitch=${pitch.join(',')}',
      if (fac.isNotEmpty) 'fac=${fac.join(',')}',
      if (feeMax != null) 'feeMax=$feeMax',
      'sort=$sort',
    ].join('&');
    final j = await _send('GET', '/v1/grounds?$params');
    return (
      total: (j['total'] as num?)?.toInt() ?? 0,
      grounds: [for (final g in (j['grounds'] as List? ?? const [])) Ground(Map<String, dynamic>.from(g as Map))],
    );
  }

  Future<Ground> ground(String id, {double? lat, double? lng}) async =>
      Ground(await _send('GET', '/v1/grounds/$id${lat == null ? '' : '?lat=$lat&lng=$lng'}', auth: _token()));
  Future<Ground> addGround(Map<String, dynamic> body) async => Ground(await _send('POST', '/v1/grounds', body: body, auth: _need()));
  Future<Ground> editGround(String id, Map<String, dynamic> body) async => Ground(await _send('PUT', '/v1/grounds/$id', body: body, auth: _need()));
  Future<String> addGroundPhoto(String id, String jpegBase64) async =>
      '${(await _send('POST', '/v1/grounds/$id/photos', body: {'jpeg': jpegBase64}, auth: _need()))['id']}';
  Future<void> deleteGroundPhoto(String id, String photoId) async => _send('DELETE', '/v1/grounds/$id/photos/$photoId', auth: _need());

  Future<List<GroundReview>> groundReviews(String id) async {
    final j = await _send('GET', '/v1/grounds/$id/reviews');
    return [
      for (final r in (j['reviews'] as List? ?? const []))
        GroundReview('${r['name']}', (r['stars'] as num).toInt(), '${r['body'] ?? ''}', DateTime.fromMillisecondsSinceEpoch((r['created'] as num).toInt())),
    ];
  }

  Future<void> reviewGround(String id, int stars, String body) async => _send('POST', '/v1/grounds/$id/reviews', body: {'stars': stars, 'body': body}, auth: _need());

  Future<({List<MatchListItem> matches, List<(String, int)> tournaments})> groundMatches(String id) async {
    final j = await _send('GET', '/v1/grounds/$id/matches');
    return (
      matches: [for (final m in (j['matches'] as List? ?? const [])) parseMatchItem(m)],
      tournaments: [for (final t in (j['tournaments'] as List? ?? const [])) ('${t['title']}', (t['matches'] as num).toInt())],
    );
  }

  Future<GroundInsights> groundInsights(String id) async => GroundInsights(await _send('GET', '/v1/grounds/$id/insights'));

  // ------------------------------------------------------------ booking and weather

  Future<GroundSlots> groundSlots(String id, {String? date}) async =>
      GroundSlots(await _send('GET', '/v1/grounds/$id/slots${date == null ? '' : '?date=$date'}', auth: _token()));
  Future<GroundSlots> saveGroundSlots(String id, List<Slot> slots) async =>
      GroundSlots(await _send('PUT', '/v1/grounds/$id/slots', body: {'slots': [for (final s in slots) s.toJson()]}, auth: _need()));
  Future<void> requestBooking(String groundId, {required String slotId, required String date, required String team, required String phone, String note = ''}) async =>
      _send('POST', '/v1/grounds/$groundId/bookings', body: {'slotId': slotId, 'date': date, 'team': team, 'phone': phone, 'note': note}, auth: _need());
  Future<({List<Booking> asked, List<Booking> incoming})> bookings() async {
    final j = await _send('GET', '/v1/bookings', auth: _need());
    List<Booking> list(String k) => [for (final b in (j[k] as List? ?? const [])) Booking(Map<String, dynamic>.from(b as Map))];
    return (asked: list('asked'), incoming: list('incoming'));
  }

  Future<void> answerBooking(String id, String action) async => _send('POST', '/v1/bookings/$id', body: {'action': action}, auth: _need());

  Future<List<DayWeather>> weather(double lat, double lng) async {
    final j = await _send('GET', '/v1/weather?lat=${lat.toStringAsFixed(3)}&lng=${lng.toStringAsFixed(3)}');
    return [for (final d in (j['days'] as List? ?? const [])) DayWeather(Map<String, dynamic>.from(d as Map))];
  }

  Future<void> deleteAccount() async => _send('DELETE', '/v1/me/account', auth: _need());

  // ------------------------------------------------------------ accounts (sign up / log in)

  Future<MeInfo> signUp(SignUpForm f) async => MeInfo.fromJson(await _send('POST', '/v1/auth/signup', body: f.toJson()));
  Future<MeInfo> logInEmail(String email, String password) async =>
      MeInfo.fromJson(await _send('POST', '/v1/auth/login', body: {'email': email.trim(), 'password': password}));
  Future<MeInfo> googleAuth(String idToken, {SignUpForm? signUp}) async => MeInfo.fromJson(await _send('POST', '/v1/auth/google',
      body: {'idToken': idToken, 'mode': signUp == null ? 'login' : 'signup', if (signUp != null) ...signUp.toJson()..remove('password')}));
  /// Tells the server this phone is watching the match video; returns how many are.
  Future<int> watch(String matchId, String device) async =>
      ((await _send('POST', '/v1/matches/${Uri.encodeComponent(matchId)}/watch', body: {'device': device}))['viewers'] as num?)?.toInt() ?? 0;
  Future<void> setPassword(String password) async => _send('PUT', '/v1/auth/password', body: {'password': password}, auth: _need());
}

class SignUpForm {
  SignUpForm({this.name = '', this.email = '', this.password = '', this.countryCode = '+91', this.phone = '', this.state = '', this.city = '', this.agree = false});
  String name, email, password, countryCode, phone, state, city;
  bool agree;
  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'countryCode': countryCode,
        'phone': phone.replaceAll(RegExp(r'\D'), ''),
        'state': state.trim(),
        'city': city.trim(),
        'agree': agree,
      };
}

/// 0 weak (too short), 1 medium, 2+ strong — the same rule as the server.
int passwordScore(String pw) {
  if (pw.length < 8) return 0;
  var n = 0;
  if (RegExp(r'\d').hasMatch(pw)) n++;
  if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) n++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) n++;
  return n > 3 ? 3 : n;
}

/// A bookable time at a ground, e.g. "Morning 6–10 AM, ₹1,500".
class Slot {
  Slot({this.id, this.label = '', required this.start, required this.end, this.price = 0, this.days = 127, this.status = 'free'});
  final String? id;
  String label;
  int start; // minutes after midnight
  int end;
  int price;
  int days; // bit 0 Monday … bit 6 Sunday
  final String status; // free, booked, requested, mine, closed

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        id: j['id'] as String?,
        label: '${j['label'] ?? ''}',
        start: (j['start'] as num?)?.toInt() ?? 0,
        end: (j['end'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toInt() ?? 0,
        days: (j['days'] as num?)?.toInt() ?? 127,
        status: '${j['status'] ?? 'free'}',
      );
  Map<String, dynamic> toJson() => {if (id != null) 'id': id, 'label': label, 'start': start, 'end': end, 'price': price, 'days': days};
}

class GroundSlots {
  GroundSlots(Map<String, dynamic> j)
      : mine = j['mine'] == true,
        date = '${j['date'] ?? ''}',
        slots = [for (final s in (j['slots'] as List? ?? const [])) Slot.fromJson(Map<String, dynamic>.from(s as Map))],
        days = [for (final d in (j['days'] as List? ?? const [])) ('${(d as Map)['date']}', ((d)['free'] as num?)?.toInt() ?? 0)];
  final bool mine;
  final String date;
  final List<Slot> slots;
  final List<(String, int)> days; // date, free slots
}

class Booking {
  Booking(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get groundId => '${j['groundId'] ?? ''}';
  String get groundName => '${j['groundName'] ?? ''}';
  String get slotLabel => '${j['slotLabel'] ?? ''}';
  int? get start => (j['start'] as num?)?.toInt();
  int? get end => (j['end'] as num?)?.toInt();
  int get price => (j['price'] as num?)?.toInt() ?? 0;
  String get date => '${j['date'] ?? ''}';
  String get team => '${j['team'] ?? ''}';
  String get note => '${j['note'] ?? ''}';
  String get status => '${j['status'] ?? ''}';
  String get by => '${j['by'] ?? ''}';
  String? get phone => j['phone'] as String?;
}

class DayWeather {
  DayWeather(Map<String, dynamic> j)
      : date = '${j['date'] ?? ''}',
        code = (j['code'] as num?)?.toInt(),
        max = (j['max'] as num?)?.round(),
        min = (j['min'] as num?)?.round(),
        rain = (j['rain'] as num?)?.round();
  final String date;
  final int? code; // WMO weather code
  final int? max, min, rain;

  String get emoji {
    final c = code ?? 0;
    if (c >= 95) return '⛈';
    if (c >= 61 || (c >= 51 && c <= 57) || c >= 80) return '🌧';
    if (c >= 45 && c <= 48) return '🌫';
    if (c >= 2) return '⛅';
    return '☀️';
  }
}
