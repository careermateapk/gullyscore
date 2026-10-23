// Match cards for matches whose live video is on (feed and Home).
import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../data/cloud.dart';
import '../ui/widgets/common.dart';
import 'stream_overlay.dart' show teamCode;
import 'youtube_embed.dart';

String _scoreLine(MatchListItem m) {
  final innings = (m.summary['innings'] as List? ?? const []);
  if (innings.isEmpty) return '';
  final last = innings.last as Map;
  final team = '${last['team'] ?? ''}';
  return '${teamCode(team)} ${last['score'] ?? ''}  ${last['overs'] ?? ''} ov';
}

String _teams(MatchListItem m) {
  final a = m.teamA.name.isNotEmpty ? m.teamA.name : '${m.summary['title'] ?? ''}'.split(' vs ').first;
  final b = m.teamB.name.isNotEmpty ? m.teamB.name : '${m.summary['title'] ?? ''}'.split(' vs ').last.split(' · ').first;
  return '$a vs $b';
}

/// The video picture with the score strip, LIVE VIDEO tag and 👁 count.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.m, this.small = false});
  final MatchListItem m;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final line = _scoreLine(m);
    return Stack(children: [
      const Positioned.fill(child: FieldPicture()),
      Center(
        child: Container(
          width: small ? 34 : 46,
          height: small ? 34 : 46,
          decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: small ? 22 : 30),
        ),
      ),
      Positioned(left: 8, top: 8, child: liveTag(context.tr(small ? 'live' : 'live_video_tag'))),
      if (m.viewers > 0) Positioned(right: 8, top: 8, child: ViewersChip(n: m.viewers)),
      if (line.isNotEmpty)
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(color: const Color(0xE60B1220), borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.centerLeft,
            child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ),
    ]);
  }
}

/// Big card in the Matches list.
class VideoMatchCard extends StatelessWidget {
  const VideoMatchCard({super.key, required this.m, required this.onTap});
  final MatchListItem m;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderColor: const Color(0x80E53935),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Corners.card)),
          child: AspectRatio(aspectRatio: 16 / 8, child: _Thumb(m: m)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_teams(m), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text([if (m.title.isNotEmpty) m.title, if (m.headline.isNotEmpty) m.headline].join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(p.goldText, w: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

/// Home: "📺 Live videos now" — a sideways list of matches with video.
class LiveVideosStrip extends StatefulWidget {
  const LiveVideosStrip({super.key, required this.onOpen});
  final void Function(String matchId) onOpen;
  @override
  State<LiveVideosStrip> createState() => _LiveVideosStripState();
}

class _LiveVideosStripState extends State<LiveVideosStrip> {
  List<MatchListItem> _list = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || !context.sync.enabled) return;
    try {
      final r = await context.sync.social.feed('live');
      if (mounted) setState(() => _list = r.matches.where((m) => m.stream.isNotEmpty).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
        child: Text('📺 ${context.tr('live_videos_now')} · ${_list.length}', style: Tx.section(p.text)),
      ),
      SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.edge),
          itemCount: _list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (c, i) {
            final m = _list[i];
            return SizedBox(
              width: 240,
              child: AppCard(
                padding: EdgeInsets.zero,
                onTap: () => widget.onOpen(m.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(Corners.card)),
                    child: SizedBox(height: 124, child: _Thumb(m: m, small: true)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_teams(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
                      if (m.title.isNotEmpty) Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
