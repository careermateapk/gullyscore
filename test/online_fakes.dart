// Canned answers from the online service, so the online screens can be
// drawn in tests (small phone, big text, light/dark, Hindi).
import 'package:gullyscore/data/cloud.dart';
import 'package:gullyscore/data/google_auth.dart';

final _now = DateTime(2026, 10, 22, 10).millisecondsSinceEpoch;

Map<String, dynamic> _sum(String a, String b, String status, {bool live = true}) => {
      'title': '$a vs $b',
      'status': status,
      'innings': [
        {'team': a, 'score': '133/6', 'overs': '20.0', 'extras': '4', 'batting': [], 'bowling': [], 'fow': []},
        if (live) {'team': b, 'score': '87/3', 'overs': '11.2', 'extras': '2', 'batting': [], 'bowling': [], 'fow': []},
      ],
      'thisOver': ['1', '4'],
    };

Map<String, dynamic> match(String id, String status, {String a = 'Madhubani Super Strikers XI', String b = 'Jhanjharpur Warriors', Map<String, dynamic>? me}) => {
      'id': id,
      'updated': _now,
      'finished': status == 'result',
      'title': 'MPL 2026 Winter Edition',
      'status': status,
      'scheduled': status == 'upcoming' ? _now + 86400000 : null,
      'ground': 'Sakri high school ground, Madhubani',
      'teamA': {'id': 'tA', 'name': a},
      'teamB': {'id': 'tB', 'name': b},
      'winner': status == 'result' ? 'tA' : '',
      'summary': _sum(a, b, status == 'result' ? '$a won by 46 runs' : 'MS need 47 runs from 52 balls', live: status != 'upcoming'),
      if (me != null) 'me': me,
    };

final _team = {
  'scorerId': 's1',
  'id': 'tA',
  'name': 'Madhubani Super Strikers XI',
  'played': 12,
  'won': 8,
  'lost': 4,
  'form': ['W', 'W', 'L', 'W', 'T'],
  'next': match('u1', 'upcoming'),
  'rating': 4.6,
  'ratings': 38,
  'matches': [match('l1', 'live'), match('u1', 'upcoming'), match('r1', 'result')],
};

final meJson = {
  'email': 'surajkumarthakur.longname@gmail.com',
  'name': 'Suraj Kumar Thakur',
  'hasPhone': true,
  'profiles': [
    {'status': 'ok', 'name': 'Suraj Kumar Thakur', 'team': 'Madhubani Super Strikers XI'},
  ],
  'matches': [
    match('l1', 'live', me: {'r': 158, 'b': 131, '4s': 16, '6s': 9, 'notOut': true, 'w': 5, 'o': '4.0', 'rc': 38, 'hat': true, 'ct': 3}),
    match('u1', 'upcoming'),
    match('r1', 'result', me: {'r': 75, 'b': 38, 'notOut': true}),
  ],
  'teams': [_team, {..._team, 'id': 'tC', 'name': 'Rajnagar XI', 'rating': null, 'next': null}],
  'totals': {'matches': 140, 'runs': 10412, 'wickets': 109, 'best': 158, 'bestNotOut': true},
};

Map<String, dynamic> _comment(String id, {List<Map<String, dynamic>> replies = const []}) => {
      'id': id,
      'author': {'name': 'Suraj Kumar Thakur', 'team': 'Delhi Daredevils Cricket Club'},
      'isTeam': replies.isEmpty,
      'stars': 4.7,
      'body': 'Bahut achha match tha, poori team ne fair khela. Next time phir khelenge!',
      'created': _now - 3600000,
      'mine': false,
      'reactions': [
        {'emoji': '👍', 'n': 12},
        {'emoji': '❤️', 'n': 5},
        {'emoji': '🔥', 'n': 3},
      ],
      'myReaction': '👍',
      'replies': replies.length + 3,
      'firstReplies': replies,
    };

Map<String, dynamic> _post(String id, String kind) => {
      'id': id,
      'kind': kind,
      'body': 'Sunday 7 AM friendly at Gaziabad ground. Need 1 bowler + 1 wicket-keeper. 10 overs, tennis ball.',
      'place': 'Gaziabad Sector 62 ground',
      'created': _now - 1200000,
      'author': {'name': 'Delhi Daredevils Cricket Club'},
      'mine': kind == 'general',
      'joins': 5,
      'joined': kind == 'tournament',
      'paid': false,
      'hasContact': true,
      if (kind == 'tournament') 'contact': '+919111111111',
      'extra': {
        'when': 'Sunday 7 AM',
        if (kind == 'players') 'need': 2,
        if (kind == 'poll') 'options': ['Suraj Kumar Thakur', 'Ravi Jha', 'Amit Mishra'],
        if (kind == 'tournament') ...{'fee': 500, 'upi': 'mithilapremierleague@okaxis', 'teams': 8, 'lastDate': '28 Oct', 'prize': '₹5,000 + trophy'},
      },
      if (kind == 'poll') 'votes': [50, 23, 13],
      if (kind == 'poll') 'myVote': 0,
    };

Future<Map<String, dynamic>> fakeSend(String method, String path, {Object? body, String? auth}) async {
  if (path.startsWith('/v1/feed')) {
    final kind = Uri.parse(path).queryParameters['kind'];
    final st = kind == 'results' ? 'result' : kind!;
    return {'matches': [match('a', st), match('b', st, a: 'DD', b: 'GB')], 'counts': {'live': 6, 'upcoming': 4}};
  }
  if (path.startsWith('/v1/posts')) {
    return {'posts': [for (final k in ['players', 'opponent', 'poll', 'tournament', 'general']) _post('p$k', k)]};
  }
  if (path.startsWith('/v1/leaderboard')) {
    return {
      'players': [
        for (var i = 0; i < 6; i++) {'name': 'Suraj Kumar Thakur $i', 'team': 'Madhubani Super Strikers XI', 'runs': 10412 - i, 'wickets': 109, 'matches': 140, 'best': 158},
      ],
    };
  }
  if (path.contains('/ratings')) {
    return {
      'count': 38,
      'overall': 4.6,
      'fair': 4.7,
      'behaviour': 4.6,
      'ontime': 4.0,
      'tags': {'sportsmen': 21, 'tough': 3, 'late': 2, 'again': 17},
      'comments': [_comment('c1', replies: [_comment('c2')]), _comment('c3')],
    };
  }
  if (path.endsWith('/asks')) {
    return {
      'asks': [
        {
          'id': 'a1',
          'title': 'vs Jhanjharpur Warriors Cricket Club',
          'when': 'Sunday 25 Oct, 7:00 AM',
          'place': 'Sakri high school ground',
          'need': 11,
          'mine': true,
          'myAnswer': 'yes',
          'yes': 8,
          'no': 2,
          'maybe': 1,
          'waiting': 3,
          'players': [
            for (final a in ['yes', 'no', 'maybe', '']) {'playerId': 'p$a', 'name': 'Suraj Kumar Thakur Junior', 'answer': a},
          ],
        },
      ],
    };
  }
  if (path.contains('/khata')) {
    return {
      'month': '2026-10',
      'spent': 128400,
      'share': 9172,
      'players': 14,
      'pending': 74000,
      'people': [
        {'playerId': 'k1', 'name': 'Amit Kumar Mishra Senior', 'paid': 0, 'due': 9172},
        {'playerId': 'k2', 'name': 'Mohan', 'paid': 9172, 'due': 0},
      ],
      'items': [
        {'id': 'i1', 'kind': 'expense', 'amount': 120000, 'note': '2 leather balls and stumps for the whole season', 'name': 'Suraj Kumar Thakur', 'created': _now},
        {'id': 'i2', 'kind': 'payment', 'amount': 9172, 'note': '', 'name': 'Mohan', 'created': _now},
      ],
    };
  }
  if (path.endsWith('/rating')) return {'canRate': true, 'scorerId': 's1', 'team': {'id': 'tB', 'name': 'Jhanjharpur Warriors'}};
  if (path.startsWith('/v1/teams/')) return _team;
  return {};
}

/// Enabled cloud that knows the logged-in player.
class OnlineCloud implements CloudApi {
  @override
  bool get enabled => true;
  @override
  String get baseUrl => 'https://gs.test';
  @override
  Future<MeInfo> me(String userToken) async => MeInfo.fromJson(meJson);
  @override
  Future<RemoteMatch?> getMatch(String id, {int since = 0}) async => null;
  @override
  Future<List<Claim>> claims(String auth) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.error(CloudError(0, 'test'));
}

class NoGoogle implements GoogleAuth {
  @override
  bool get available => true;
  @override
  Future<String> idToken() async => 'x';
  @override
  Future<void> signOut() async {}
}
