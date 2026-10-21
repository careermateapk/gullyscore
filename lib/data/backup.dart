// Backup file: all matches, teams, players, tournaments and pictures in one
// JSON file the user can keep in Google Drive, WhatsApp or anywhere.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'photos.dart';

class Backup {
  static const marker = 'gullyscore_backup';

  /// Builds the backup file contents.
  static Uint8List build(Map<String, dynamic> data, {DateTime? at}) {
    final photos = <String, String>{};
    final dir = PhotoStore.dir;
    if (dir != null) {
      final d = Directory(dir);
      if (d.existsSync()) {
        for (final f in d.listSync().whereType<File>()) {
          final name = f.uri.pathSegments.last;
          photos[name] = base64Encode(f.readAsBytesSync());
        }
      }
    }
    final out = {
      marker: 1,
      'created': (at ?? DateTime.now()).toIso8601String(),
      'data': data,
      'photos': photos,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(out)));
  }

  /// Reads a backup file. Throws [FormatException] if it is not one.
  static BackupContents read(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('not a GullyScore backup');
    }
    if (json is! Map || json[marker] == null || json['data'] is! Map) {
      throw const FormatException('not a GullyScore backup');
    }
    final data = Map<String, dynamic>.from(json['data'] as Map);
    final photos = <String, Uint8List>{};
    final raw = json['photos'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final name = '$k';
        // Only plain file names: never write outside the photo folder.
        if (v is String && RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(name)) photos[name] = base64Decode(v);
      });
    }
    return BackupContents(
      data: data,
      photos: photos,
      created: DateTime.tryParse('${json['created']}'),
    );
  }

  /// Writes the pictures from a backup into the photo folder.
  static Future<void> restorePhotos(Map<String, Uint8List> photos) async {
    await PhotoStore.deleteAll();
    if (PhotoStore.dir == null) await PhotoStore.init();
    final dir = PhotoStore.dir;
    if (dir == null) return;
    for (final e in photos.entries) {
      await File('$dir/${e.key}').writeAsBytes(e.value, flush: true);
    }
  }

  static String fileName(DateTime t) =>
      'GullyScore-backup-${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}.json';
}

class BackupContents {
  BackupContents({required this.data, required this.photos, this.created});
  final Map<String, dynamic> data;
  final Map<String, Uint8List> photos;
  final DateTime? created;

  int get matchCount => (data['matches'] as List? ?? const []).length;
  int get teamCount => (data['teams'] as List? ?? const []).length;
}
