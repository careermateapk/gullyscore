// Plain data saved on the phone as JSON.
import '../scoring/engine.dart';

String newId() {
  final t = DateTime.now().microsecondsSinceEpoch;
  return t.toRadixString(36) + (t % 997).toRadixString(36);
}

class Player {
  Player({required this.id, required this.name, this.leftHanded = false, this.role = ''});
  final String id;
  String name;
  bool leftHanded;
  String role; // free text, e.g. "Batter", "Off spin"

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lh': leftHanded, 'role': role};

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        leftHanded: (j['lh'] as bool?) ?? false,
        role: (j['role'] as String?) ?? '',
      );
}

class Team {
  Team({required this.id, required this.name, required this.colorIndex, List<String>? playerIds})
      : playerIds = playerIds ?? [];
  final String id;
  String name;
  int colorIndex;
  final List<String> playerIds;

  /// Two-letter short name, e.g. "Madhubani Strikers" → "MS".
  String get short => initials(name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': colorIndex, 'players': playerIds};

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        colorIndex: (j['color'] as num?)?.toInt() ?? 0,
        playerIds: [for (final p in (j['players'] as List? ?? const [])) p as String],
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
  final int firstBatting; // 0 = team A
  final DateTime createdAt;
  final String venue;
  final String title; // e.g. "Friendly" or tournament name
  final String tossText;
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
        events: [for (final e in (j['events'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)],
        celebrated: {for (final c in (j['celebrated'] as List? ?? const [])) c as String},
      );
}
