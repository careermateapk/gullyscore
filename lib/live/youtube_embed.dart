// The YouTube live video, shown at the top of the match page.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/scope.dart';
import 'youtube.dart';

class YoutubeLive extends StatefulWidget {
  const YoutubeLive({super.key, required this.streamRef});
  final String streamRef; // 'v:…' or 'c:…'

  @override
  State<YoutubeLive> createState() => _YoutubeLiveState();
}

class _YoutubeLiveState extends State<YoutubeLive> {
  WebViewController? _c;
  bool _open = false; // the video loads only after a tap (saves data)

  void _start() {
    final base = context.sync.cloud.baseUrl;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(youtubeEmbedUri(base, widget.streamRef));
    setState(() {
      _c = c;
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _open && _c != null
            ? WebViewWidget(controller: _c!)
            : Material(
                color: Colors.black,
                child: InkWell(
                  onTap: _start,
                  child: Stack(children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF79B559), Color(0xFF3D7D2B)]),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(7)),
                        child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        tooltip: context.tr('open_youtube'),
                        onPressed: () => launchUrl(youtubeWatchUri(widget.streamRef), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                      ),
                    ),
                    Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                        ),
                        const SizedBox(height: 8),
                        Text(context.tr('watch_live_video'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8)])),
                      ]),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}
