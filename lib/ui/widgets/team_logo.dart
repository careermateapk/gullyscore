// Team logo: pick one of 12 ready designs (the team's letters are added on
// it), or a photo from the gallery/camera, cropped. Saved on the phone only.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/photos.dart';
import '../screens/crop_screen.dart';
import '../screens/scoring_sheets.dart' show showAppSheet, SheetTitle;
import 'common.dart';

const logoDesigns = [
  ('assets/logos/logo_01.png', 'Bats'),
  ('assets/logos/logo_02.png', 'Fire'),
  ('assets/logos/logo_03.png', 'Thunder'),
  ('assets/logos/logo_04.png', 'Royals'),
  ('assets/logos/logo_05.png', 'Ball'),
  ('assets/logos/logo_06.png', 'Stars'),
  ('assets/logos/logo_07.png', 'Stumps'),
  ('assets/logos/logo_08.png', 'Eagles'),
  ('assets/logos/logo_09.png', 'Hills'),
  ('assets/logos/logo_10.png', 'Tigers'),
  ('assets/logos/logo_11.png', 'Warriors'),
  ('assets/logos/logo_12.png', 'Waves'),
];

/// A design with the team's letters on it (as shown in the picker).
class DesignLogo extends StatelessWidget {
  const DesignLogo({super.key, required this.asset, required this.letters, this.size = 56});
  final String asset;
  final String letters;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          Positioned.fill(child: Image.asset(asset, fit: BoxFit.contain)),
          if (letters.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: size * 0.08,
              child: MediaQuery.withNoTextScaling(
                child: Text(
                  letters,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Saira',
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.17,
                    color: Colors.white,
                    shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Draws a design with letters into a PNG and saves it. Returns the file name.
Future<String> saveDesignLogo(String asset, String letters, String prefix) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 512, targetHeight: 512);
  final frame = await codec.getNextFrame();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawImage(frame.image, Offset.zero, Paint()..filterQuality = FilterQuality.high);
  if (letters.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: letters,
        style: const TextStyle(
          fontFamily: 'Saira',
          fontWeight: FontWeight.w800,
          fontSize: 88,
          color: Colors.white,
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 8)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 480);
    tp.paint(canvas, Offset((512 - tp.width) / 2, 512 - 41 - tp.height));
  }
  final img = await rec.endRecording().toImage(512, 512);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  img.dispose();
  return PhotoStore.saveBytes(prefix, png!.buffer.asUint8List());
}

/// The logo sheet. Returns a saved file name, '' to remove, or null if closed.
Future<String?> pickLogo(BuildContext context, {required String letters, required String prefix, Widget? current, bool canRemove = false}) async {
  final choice = await showAppSheet<String>(context, (ctx) {
    final p = Palette.of(ctx);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(ctx.tr('team_logo'), subtitle: ctx.tr('photo_stays_on_phone')),
          if (current != null) Center(child: current),
          const SizedBox(height: Space.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: Row(children: [
              Expanded(child: OutlineBtn(label: ctx.tr('from_gallery'), icon: Icons.photo_library_outlined, height: 46, onPressed: () => Navigator.pop(ctx, 'gallery'))),
              const SizedBox(width: 8),
              Expanded(child: OutlineBtn(label: ctx.tr('from_camera'), icon: Icons.photo_camera_outlined, height: 46, onPressed: () => Navigator.pop(ctx, 'camera'))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Text(ctx.tr('or_pick_design'), style: Tx.label(p.text2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 3 * 8) / 4;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (i, d) in logoDesigns.indexed)
                  Semantics(
                    button: true,
                    label: d.$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(ctx, 'design:$i'),
                      child: Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(14)),
                        child: Column(children: [
                          DesignLogo(asset: d.$1, letters: letters, size: w * 0.78),
                          Text(d.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
          ),
          if (canRemove)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                icon: Icon(Icons.delete_outline_rounded, color: p.liveText),
                label: Text(ctx.tr('remove_logo'), style: TextStyle(color: p.liveText)),
              ),
            ),
        ]),
      ),
    );
  });
  if (choice == null || !context.mounted) return null;
  if (choice == 'remove') return '';
  if (choice.startsWith('design:')) {
    final i = int.parse(choice.substring(7));
    return saveDesignLogo(logoDesigns[i].$1, letters, prefix);
  }
  return pickCropSave(context, camera: choice == 'camera', circle: false, prefix: prefix);
}
