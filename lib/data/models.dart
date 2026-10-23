// Plain data saved on the phone as JSON.
import '../scoring/engine.dart';

String newId() {
  final t = DateTime.now().microsecondsSinceEpoch;
  return t.toRadixString(36) + (t % 997).toRadixString(36);
}

class Player {
  Player({required this.id, required this.name, this.leftHanded = false, this.role = '', this.photo, this.remote = false, this.phone = ''});
  final String id;
  String name;
  bool leftHanded;
  String role; // free text, e.g. "Batter", "Off spin"
  String? photo; // file name inside the app's photo folder on this phone
  bool remote; // came from someone else's match that this phone follows
  String phone; // mobile number typed by the scorer, so the player can log in and see their matches

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'lh': leftHanded, 'role': role, if (photo != null) 'photo': photo, if (remote) 'remote': true, if (phone.isNotEmpty) 'phone': phone};

  /// What goes inside online match data: never the photo or the mobile number.
  Map<String, dynamic> toCloud() => {'id': id, 'name': name, 'lh': leftHanded, 'role': role};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        leftHanded: (j['lh'] as bool?) ?? false,
        role: (j['role'] as String?) ?? '',
        photo: j['photo'] as String?,
        remote: (j['remote'] as bool?) ?? false,
        phone: (j['phone'] as String?) ?? '',
      );
}

/// Keeps only digits and the last 10 of them ("+91 98765-43210" → "9876543210").
/// Empty when it is not a mobile number.
String cleanPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  return d.length >= 10 && d.length <= 15 ? d.substring(d.length - 10) : '';
}

class Team {
  Team({required this.id, required this.name, required this.colorIndex, List<String>? playerIds, this.logo, this.remote = false})
      : playerIds = playerIds ?? [];
  final String id;
  String name;
  int colorIndex;
  final List<String> playerIds;
  String? logo; // file name of the logo saved on this phone
  bool remote; // came from a followed match

  /// Two-letter short name, e.g. "Madhubani Strikers" → "MS".
  String get short => initials(name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': colorIndex, 'players': playerIds, if (logo != null) 'logo': logo, if (remote) 'remote': true};

  /// What goes online: never the logo picture.
  Map<String, dynamic> toCloud() => {'id': id, 'name': name, 'color': colorIndex, 'players': playerIds};

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        colorIndex: (j['color'] as num?)?.toInt() ?? 0,
        playerIds: [for (final p in (j['players'] as List? ?? const [])) p as String],
        logo: j['logo'] as String?,
        remote: (j['remote'] as bool?) ?? false,
      );
}

String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

class MatchRecord {
  MatchRecord({
    required this.id,
    required this.teamA,
    required this.teamB,
    required this.playersA,
    required this.playersB,
    required this.overs,
    required this.firstBatting,
    required this.createdAt,
    this.venue = '',
    this.title = '',
    this.tossText = '',
    this.tournamentId,
    this.fixtureId,
    this.remote = false,
    this.scheduledAt,
    this.tossPending = false,
    this.sponsors = const [],
    this.groundId = '',
    this.stream = '',
    List<Map<String, dynamic>>? events,
    DateTime? updatedAt,
    Set<String>? celebrated,
  })  : events = events ?? [],
        updatedAt = updatedAt ?? createdAt,
        celebrated = celebrated ?? {};

  final String id;
  final String teamA; // team ids
  final String teamB;
  final List<String> playersA; // player ids in batting order
  final List<String> playersB;
  final int overs;
  int firstBatting; // 0 = team A
  final DateTime createdAt;
  final String venue;
  final String title; // e.g. "Friendly" or tournament name
  String tossText;
  DateTime? scheduledAt; // when the match is planned (shown as Upcoming until it starts)
  bool tossPending; // scheduled match: the toss is asked when scoring starts
  final List<Map<String, dynamic>> sponsors; // followed matches only (from the tournament online)
  final String groundId; // a registered ground (Grounds near you), if picked
  String stream; // YouTube live: 'v:<video id>' or 'c:<channel id>' (empty = no video)
  final String? tournamentId;
  final String? fixtureId;
  final bool remote; // someone else's match, followed from a live link
  List<Map<String, dynamic>> events;
  DateTime updatedAt;

  /// Ball keys whose celebration already played, so it never replays
  /// when the match is opened again.
  final Set<String> celebrated;

  MatchSetup get setup => MatchSetup(overs: overs, playersA: playersA, playersB: playersB, firstBatting: firstBatting);

  MatchState get state => replay(setup, events);

  Map<String, dynamic> toJson() => {
        'id': id,
        'a': teamA,
        'b': teamB,
        'pa': playersA,
        'pb': playersB,
        'overs': overs,
        'first': firstBatting,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'venue': venue,
        'title': title,
        'toss': tossText,
        if (tournamentId != null) 'tid': tournamentId,
        if (fixtureId != null) 'fid': fixtureId,
        if (remote) 'remote': true,
        if (scheduledAt != null) 'sched': scheduledAt!.toIso8601String(),
        if (tossPending) 'tossPending': true,
        if (sponsors.isNotEmpty) 'sponsors': sponsors,
        if (groundId.isNotEmpty) 'ground': groundId,
        if (stream.isNotEmpty) 'stream': stream,
        'events': events,
        'celebrated': celebrated.toList(),
      };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
        id: j['id'] as String,
        teamA: j['a'] as String,
        teamB: j['b'] as String,
        playersA: [for (final p in (j['pa'] as List? ?? const [])) p as String],
        playersB: [for (final p in (j['pb'] as List? ?? const [])) p as String],
        overs: (j['overs'] as num?)?.toInt() ?? 20,
        firstBatting: (j['first'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated'] as String? ?? ''),
        venue: (j['venue'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        tossText: (j['toss'] as String?) ?? '',
        tournamentId: j['tid'] as String?,
        fixtureId: j['fid'] as String?,
        remote: (j['remote'] as bool?) ?? false,
        scheduledAt: DateTime.tryParse(j['sched'] as String? ?? ''),
        tossPending: (j['tossPending'] as bool?) ?? false,
        sponsors: [for (final x in (j['sponsors'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)],
        groundId: (j['ground'] as String?) ?? '',
        stream: (j['stream'] as String?) ?? '',
        events: [for (final e in (j['events'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)],
        celebrated: {for (final c in (j['celebrated'] as List? ?? const [])) c as String},
      );
}
