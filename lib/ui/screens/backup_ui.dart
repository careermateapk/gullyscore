// Make a backup file and restore from one.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/backup.dart';

void _say(ScaffoldMessengerState m, String text) => m
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Builds the backup file and opens the share sheet so it can be saved to
/// Google Drive, WhatsApp, Files, etc.
Future<void> makeBackup(BuildContext context) async {
  final repo = context.repo;
  final settings = context.settings;
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.tr('backup_failed');
  final shareText = context.tr('backup_share_text');
  try {
    await repo.saveNow();
    final now = DateTime.now();
    final bytes = Backup.build(repo.toJson(), at: now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${Backup.fileName(now)}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], text: shareText));
    settings.setLastBackup(now);
  } catch (_) {
    _say(messenger, failed);
  }
}

/// Lets the user pick a backup file and, after asking, replaces the data on
/// this phone with it.
Future<void> restoreBackup(BuildContext context) async {
  final repo = context.repo;
  final messenger = ScaffoldMessenger.of(context);
  final notBackup = context.tr('not_a_backup');
  final done = context.tr('restore_done');
  final failed = context.tr('restore_failed');
  try {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !context.mounted) return;
    final BackupContents contents;
    try {
      contents = Backup.read(await picked.readAsBytes());
    } on FormatException {
      _say(messenger, notBackup);
      return;
    }
    if (!context.mounted) return;
    final when = contents.created;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restore_q')),
        content: Text(ctx.tr('restore_body', {
          'm': contents.matchCount,
          't': contents.teamCount,
          'd': when == null ? '-' : '${when.day}-${when.month}-${when.year}',
        })),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('restore'), style: TextStyle(color: Palette.of(ctx).goldText, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Backup.restorePhotos(contents.photos);
    await repo.restoreFrom(contents.data);
    _say(messenger, done);
  } catch (_) {
    _say(messenger, failed);
  }
}
