// Move and zoom a picture inside a frame, then save just that part.
// Circle frame for player photos, rounded square for team logos.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/photos.dart';
import '../widgets/common.dart';

/// Opens the crop screen; returns JPEG bytes (512×512) or null if cancelled.
Future<Uint8List?> cropPicture(BuildContext context, String path, {required bool circle}) {
  return Navigator.push<Uint8List>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => CropScreen(path: path, circle: circle)));
}

/// Pick from camera or gallery, crop, and save. Returns the saved file name.
Future<String?> pickCropSave(BuildContext context, {required bool camera, required bool circle, required String prefix}) async {
  final path = await PhotoStore.pickRaw(camera: camera);
  if (path == null || !context.mounted) return null;
  final bytes = await cropPicture(context, path, circle: circle);
  if (bytes == null) return null;
  return PhotoStore.saveBytes(prefix, bytes);
}

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.path, required this.circle});
  final String path;
  final bool circle;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _boundary = GlobalKey();
  final _ctrl = TransformationController();
  Size? _imageSize;
  double? _side;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final img = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() => _imageSize = Size(img.width.toDouble(), img.height.toDouble()));
      img.dispose();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Size of the picture so its shorter side fills the frame.
  Size _fitted(double side) {
    final s = _imageSize!;
    final k = side / (s.width < s.height ? s.width : s.height);
    return Size(s.width * k, s.height * k);
  }

  /// Centres the picture the first time the frame size is known.
  void _centre(double side) {
    if (_side != null) return;
    _side = side;
    final f = _fitted(side);
    _ctrl.value = Matrix4.translationValues(-(f.width - side) / 2, -(f.height - side) / 2, 0);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final obj = _boundary.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary || obj.size.width <= 0) throw StateError('not ready');
      final image = await obj.toImage(pixelRatio: 512 / obj.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      image.dispose();
      if (data == null) throw StateError('no data');
      // JPEG keeps pictures small, so backups stay small too.
      final jpg = img.encodeJpg(img.Image.fromBytes(width: w, height: h, bytes: data.buffer, numChannels: 4), quality: 85);
      if (mounted) Navigator.pop(context, jpg);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
            child: Row(children: [
              IconButton(
                tooltip: context.tr('cancel'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  widget.circle ? context.tr('crop_photo') : context.tr('crop_logo'),
                  textAlign: TextAlign.center,
                  style: Tx.body(Colors.white, w: FontWeight.w800).copyWith(fontSize: 17),
                ),
              ),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              if (_failed) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Text(context.tr('photo_failed'), textAlign: TextAlign.center, style: Tx.body(Colors.white)),
                  ),
                );
              }
              if (_imageSize == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC94A)));
              final side = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) - 48;
              _centre(side);
              final f = _fitted(side);
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Stack(children: [
                    RepaintBoundary(
                      key: _boundary,
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: _ctrl,
                          constrained: false,
                          minScale: 1,
                          maxScale: 6,
                          boundaryMargin: EdgeInsets.zero,
                          child: Image.file(File(widget.path), width: f.width, height: f.height, fit: BoxFit.fill),
                        ),
                      ),
                    ),
                    IgnorePointer(child: CustomPaint(size: Size(side, side), painter: _FramePainter(widget.circle))),
                  ]),
                ),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
            child: Text(context.tr('crop_help'), textAlign: TextAlign.center, style: Tx.small(const Color(0xFFA9B6C9))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.l),
            child: SizedBox(
              width: double.infinity,
              child: GoldButton(
                label: _saving ? context.tr('preparing') : context.tr('use_this'),
                icon: Icons.check_rounded,
                onPressed: _saving || _imageSize == null || _failed ? null : _save,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Darkens everything outside the frame and draws the frame edge.
class _FramePainter extends CustomPainter {
  _FramePainter(this.circle);
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final frame = Path();
    if (circle) {
      frame.addOval(rect.deflate(2));
    } else {
      frame.addRRect(RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(size.width * 0.12)));
    }
    final outside = Path.combine(PathOperation.difference, Path()..addRect(rect), frame);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawPath(
      frame,
      Paint()
        ..color = const Color(0xFFFFC94A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.circle != circle;
}
