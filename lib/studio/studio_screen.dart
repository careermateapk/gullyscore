// Canva-style editor for share pictures: pick a look, a colour, a size and
// the language, see it big, then share it as a sharp picture.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../ui/widgets/common.dart';
import 'themes.dart';

typedef StudioBuilder = Widget Function(StudioTheme theme, StudioSize size, String lang);

/// A fixed-size picture (360 points wide), scaled to fit and never affected
/// by the phone's text size.
class StudioCanvas extends StatelessWidget {
  const StudioCanvas({super.key, required this.size, required this.child, this.boundaryKey});
  final StudioSize size;
  final Widget child;
  final GlobalKey? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final inner = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(width: 360, height: size.height, child: ClipRect(child: child)),
    );
    return AspectRatio(
      aspectRatio: 360 / size.height,
      child: FittedBox(fit: BoxFit.contain, child: boundaryKey == null ? inner : RepaintBoundary(key: boundaryKey, child: inner)),
    );
  }
}

/// Saves a RepaintBoundary as a PNG and opens the share menu (WhatsApp, Instagram, Save…).
Future<bool> sharePng(GlobalKey key, {required String fileName, required String text}) async {
  final obj = key.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return false;
  final image = await obj.toImage(pixelRatio: 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return false;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName.png');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text));
  return true;
}

class StudioScreen extends StatefulWidget {
  const StudioScreen({
    super.key,
    required this.title,
    required this.builder,
    required this.fileName,
    required this.shareText,
    this.sizes = const [StudioSize.post, StudioSize.story, StudioSize.square],
    this.teamColors = const [],
    this.top,
    this.themes = true,
  });
  final String title;
  final StudioBuilder builder;
  final String fileName;
  final String shareText;
  final List<StudioSize> sizes;
  final List<Color> teamColors; // offered as colours, e.g. the player's team
  final Widget? top; // e.g. Match day / Live / Result switch
  final bool themes; // false for pictures with one fixed look (certificates)

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _key = GlobalKey();
  String _theme = studioThemes.first.id;
  late StudioSize _size = widget.sizes.first;
  Color? _tint;
  String? _lang;
  bool _working = false;

  StudioTheme get _look {
    final t = themeById(_theme);
    return _tint == null ? t : t.tinted(_tint!);
  }

  Future<void> _share() async {
    setState(() => _working = true);
    final failed = context.tr('share_failed');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await sharePng(_key, fileName: widget.fileName, text: widget.shareText);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lang = _lang ?? context.settings.lang;
    final look = _look;
    final preview = widget.builder(look, _size, lang);
    final screenH = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: Space.l), children: [
            if (widget.top != null) Padding(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.m), child: widget.top),
            // Big preview with a soft glow in the picture's colour.
            Center(
              child: Container(
                constraints: BoxConstraints(maxHeight: (screenH * 0.5).clamp(260, 520)),
                margin: const EdgeInsets.symmetric(horizontal: Space.edge),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: look.bg.first.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 2),
                    const BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 14)),
                  ],
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(16), child: StudioCanvas(size: _size, boundaryKey: _key, child: preview)),
              ),
            ),
            const SizedBox(height: Space.m),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              if (widget.sizes.length > 1)
                for (final s in widget.sizes) ChoiceChipX(label: context.tr(s.key), selected: s == _size, onTap: () => setState(() => _size = s)),
              ChoiceChipX(label: 'हिंदी', selected: lang == 'hi', onTap: () => setState(() => _lang = lang == 'hi' ? 'en' : 'hi')),
            ]),
            if (widget.themes) ...[
            _Header(context.tr('templates')),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                itemCount: studioThemes.length,
                separatorBuilder: (c, i) => const SizedBox(width: 10),
                itemBuilder: (c, i) {
                  final t = studioThemes[i];
                  final on = t.id == _theme;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: context.tr('theme_${t.id}'),
                    child: GestureDetector(
                      onTap: () => setState(() => _theme = t.id),
                      child: SizedBox(
                        width: 84,
                        child: Column(children: [
                          AnimatedContainer(
                            duration: Motion.fade,
                            width: 84,
                            height: 105,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: on ? p.gold : Colors.transparent, width: 2),
                              boxShadow: on ? [BoxShadow(color: p.gold.withValues(alpha: 0.3), blurRadius: 10)] : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: IgnorePointer(child: ExcludeSemantics(child: StudioCanvas(size: StudioSize.post, child: widget.builder(_tint == null ? t : t.tinted(_tint!), StudioSize.post, lang)))),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ExcludeSemantics(
                            child: Text(context.tr('theme_${t.id}'),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(on ? p.goldText : p.text2, w: FontWeight.w800)),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            _Header(context.tr('colours')),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.edge), children: [
                _Swatch(colors: themeById(_theme).bg, selected: _tint == null, label: context.tr('theme_$_theme'), onTap: () => setState(() => _tint = null)),
                for (final c in [...widget.teamColors, ...Palette.teamColors.where((x) => !widget.teamColors.contains(x))])
                  _Swatch(colors: [c, Color.lerp(c, Colors.black, 0.7)!], selected: _tint == c, label: context.tr('colours'), onTap: () => setState(() => _tint = c)),
              ]),
            ),
            ],
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, Space.m),
            child: GoldButton(
              label: _working ? context.tr('preparing') : context.tr('share_or_save'),
              icon: Icons.ios_share_rounded,
              onPressed: _working ? null : _share,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
        child: Text(text, style: Tx.section(Palette.of(context).text)),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colors, required this.selected, required this.onTap, required this.label});
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fade,
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? p.gold : Colors.transparent, width: 2.5)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors.length >= 2 ? colors : [colors.first, colors.first]),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
