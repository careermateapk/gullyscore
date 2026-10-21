// A player's photo, or their initials when there is no photo.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/photos.dart';
import '../screens/crop_screen.dart';
import '../screens/scoring_sheets.dart';
import 'common.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.playerId, this.size = 36, this.color, this.ring});
  final String playerId;
  final double size;
  final Color? color; // background when there is no photo
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final pl = repo.players[playerId];
    final file = PhotoStore.file(pl?.photo);
    final initials = Text(
      initialsOf(pl?.name ?? '?'),
      style: TextStyle(color: color == null ? p.text : Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36, height: 1),
    );
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? p.raised,
          border: ring == null ? null : Border.all(color: ring!, width: 2),
        ),
        child: file == null
            ? initials
            : Image.file(
                file,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: px,
                gaplessPlayback: true,
                errorBuilder: (c, e, st) => initials,
              ),
      ),
    );
  }
}

/// Take, choose or remove a player's photo.
Future<void> editPlayerPhoto(BuildContext context, String playerId) async {
  final repo = context.repo;
  final pl = repo.players[playerId];
  if (pl == null) return;
  final choice = await showAppSheet<String>(context, (ctx) {
    final p = Palette.of(ctx);
    Widget option(IconData icon, String label, String value, {Color? color}) => ListTile(
          leading: Icon(icon, color: color ?? p.goldText),
          title: Text(label, style: Tx.body(color ?? p.text, w: FontWeight.w700)),
          minTileHeight: 56,
          onTap: () => Navigator.pop(ctx, value),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(ctx.tr('player_photo'), subtitle: ctx.tr('photo_stays_on_phone')),
        Center(child: PlayerAvatar(playerId: playerId, size: 88)),
        const SizedBox(height: Space.m),
        option(Icons.photo_camera_outlined, ctx.tr('take_photo'), 'camera'),
        option(Icons.photo_library_outlined, ctx.tr('choose_from_gallery'), 'gallery'),
        if (pl.photo != null) option(Icons.delete_outline_rounded, ctx.tr('remove_photo'), 'remove', color: p.liveText),
      ]),
    );
  });
  if (choice == null || !context.mounted) return;
  if (choice == 'remove') {
    await repo.setPlayerPhoto(pl, null);
    return;
  }
  final failed = context.tr('photo_failed');
  final messenger = ScaffoldMessenger.of(context);
  try {
    final name = await pickCropSave(context, camera: choice == 'camera', circle: true, prefix: playerId);
    if (name != null) await repo.setPlayerPhoto(pl, name);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// Avatar that opens the photo sheet when tapped, with a small camera badge.
class EditableAvatar extends StatelessWidget {
  const EditableAvatar({super.key, required this.playerId, this.size = 72, this.color});
  final String playerId;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: () => editPlayerPhoto(context, playerId),
      semanticLabel: context.tr('change_photo'),
      child: SizedBox(
        width: size + 4,
        height: size + 4,
        child: Stack(children: [
          PlayerAvatar(playerId: playerId, size: size, color: color, ring: p.gold),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(color: p.gold, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 2)),
              child: Icon(Icons.photo_camera_rounded, size: size * 0.18, color: const Color(0xFF0B1220)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Take, choose or remove a team's logo.
Future<void> editTeamLogo(BuildContext context, String teamId) async {
  final repo = context.repo;
  final team = repo.teams[teamId];
  if (team == null) return;
  final choice = await showAppSheet<String>(context, (ctx) {
    final p = Palette.of(ctx);
    Widget option(IconData icon, String label, String value, {Color? color}) => ListTile(
          leading: Icon(icon, color: color ?? p.goldText),
          title: Text(label, style: Tx.body(color ?? p.text, w: FontWeight.w700)),
          minTileHeight: 56,
          onTap: () => Navigator.pop(ctx, value),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(ctx.tr('team_logo'), subtitle: ctx.tr('photo_stays_on_phone')),
        Center(child: Crest(logo: team.logo, color: Palette.team(team.colorIndex), text: team.short, size: 80)),
        const SizedBox(height: Space.m),
        option(Icons.photo_library_outlined, ctx.tr('choose_from_gallery'), 'gallery'),
        option(Icons.photo_camera_outlined, ctx.tr('take_photo'), 'camera'),
        if (team.logo != null) option(Icons.delete_outline_rounded, ctx.tr('remove_logo'), 'remove', color: p.liveText),
      ]),
    );
  });
  if (choice == null || !context.mounted) return;
  if (choice == 'remove') {
    await repo.setTeamLogo(team, null);
    return;
  }
  final failed = context.tr('photo_failed');
  final messenger = ScaffoldMessenger.of(context);
  try {
    final name = await pickCropSave(context, camera: choice == 'camera', circle: false, prefix: 'logo_$teamId');
    if (name != null) await repo.setTeamLogo(team, name);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
