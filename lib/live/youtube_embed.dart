// The YouTube live video, shown at the top of the match page. While it is
// playing, the phone tells our server once in a while, so the match list
// can show how many people are watching in GullyScore.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/scope.dart';
import 'youtube.dart';

/// An anonymous id for this phone (only used to count watchers once).
Future<String> watcherId() async {
  try {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('watch.device');
    if (id == null) {
      const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final r = Random.secure();
      id = List.generate(20, (_) => abc[r.nextInt(abc.length)]).join();
      await p.setString('watch.device', id);
    }
    return id;
  } catch (_) {
    return 'unknown0000';
  }
}

/// "👁 1.2k" for the number of people watching.
String viewersText(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
  return '$n';
}

/// Explains what the 👁 number means.
Future<void> explainViewers(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('👁 ${ctx.tr('viewers_what')}'),
        content: Text(ctx.tr('viewers_body')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('got_it')))],
      ),
    );

class YoutubeLive extends StatefulWidget {
  const YoutubeLive({super.key, required this.streamRef, this.matchId, this.autoplay = false});
  final String streamRef; // 'v:…' or 'c:…'
  final String? matchId; // counted as a watcher while playing
  final bool autoplay;

  @override
  State<YoutubeLive> createState() => _YoutubeLiveState();
}

class _YoutubeLiveState extends State<YoutubeLive> {
  WebViewController? _c;
  bool _open = false; // the video loads only after a tap (saves data), unless autoplay
  Timer? _ping;
  int? _viewers;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _start() : null);
  }

  @override
  void dispose() {
    _ping?.cancel();
    super.dispose();
  }

  void _start() {
    final sync = context.sync;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(youtubeEmbedUri(sync.cloud.baseUrl, widget.streamRef));
    setState(() {
      _c = c;
      _open = true;
    });
    final id = widget.matchId;
    if (id != null && sync.enabled) {
      Future<void> tick() async {
        try {
          final n = await sync.social.watch(id, await watcherId());
          if (mounted) setState(() => _viewers = n);
        } catch (_) {}
      }

      tick();
      _ping = Timer.periodic(const Duration(seconds: 45), (_) => tick());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned.fill(
            child: _open && _c != null
                ? WebViewWidget(controller: _c!)
                : Material(
                    color: Colors.black,
                    child: InkWell(
                      onTap: _start,
                      child: Stack(children: [
                        const Positioned.fill(child: FieldPicture()),
                        Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                            ),
                            const SizedBox(height: 8),
                            Text(context.tr('watch_live_video'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8)])),
                          ]),
                        ),
                      ]),
                    ),
                  ),
          ),
          Positioned(left: 10, top: 10, child: liveTag(context.tr('live_video_tag'))),
          if (_viewers != null && _viewers! > 0)
            Positioned(left: 10, bottom: 10, child: ViewersChip(n: _viewers!)),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: context.tr('open_youtube'),
              onPressed: () => launchUrl(youtubeWatchUri(widget.streamRef), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
            ),
          ),
        ]),
      ),
    );
  }
}

Widget liveTag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(7)),
      child: Text('● $text', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
    );

/// "👁 1.2k ⓘ" — tap to see what it means.
class ViewersChip extends StatelessWidget {
  const ViewersChip({super.key, required this.n});
  final int n;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: context.tr('viewers_what'),
        child: GestureDetector(
          onTap: () => explainViewers(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(7)),
            child: Text('👁 ${viewersText(n)}  ⓘ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ),
      );
}

/// A drawn cricket ground (shown before the video loads, and on cards).
class FieldPicture extends StatelessWidget {
  const FieldPicture({super.key});
  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _FieldPainter());
}

class _FieldPainter extends CustomPainter {
  const _FieldPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
            Color(0xFF9FD3FF),
            Color(0xFFD6ECFF),
            Color(0xFF78B558),
            Color(0xFF579C3E),
            Color(0xFF447F2E),
          ], stops: [
            0,
            0.28,
            0.29,
            0.65,
            1,
          ]).createShader(r));
    final trees = Paint()..color = const Color(0xFF2F6B2A);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(Offset(s.width * (i / 6), s.height * 0.3), s.height * 0.09, trees);
    }
    final pitch = Path()
      ..moveTo(s.width * 0.46, s.height * 0.34)
      ..lineTo(s.width * 0.54, s.height * 0.34)
      ..lineTo(s.width * 0.62, s.height)
      ..lineTo(s.width * 0.38, s.height)
      ..close();
    canvas.drawPath(pitch, Paint()..color = const Color(0xFFD2B87C));
    final st = Paint()..color = const Color(0xFFF6EFE0);
    for (final x in [0.492, 0.5, 0.508]) {
      canvas.drawRect(Rect.fromLTWH(s.width * x, s.height * 0.3, 2, s.height * 0.09), st);
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => false;
}
