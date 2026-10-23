// Clips cut by themselves during a live stream (every four, six and wicket),
// kept on the phone. Share one, or join a player's clips into a reel.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../ui/widgets/common.dart';
import 'live_engine.dart';

class Clip {
  Clip({required this.file, required this.kind, required this.over, required this.batter, required this.bowler, required this.label, required this.at});
  final String file; // file name inside the match folder
  final String kind; // six, four, wicket
  final String over; // e.g. 16.4
  final String batter; // player id
  final String bowler;
  final String label; // e.g. "SIX · Suraj"
  final int at; // when (ms since epoch)

  Map<String, dynamic> toJson() => {'file': file, 'kind': kind, 'over': over, 'batter': batter, 'bowler': bowler, 'label': label, 'at': at};
  factory Clip.fromJson(Map<String, dynamic> j) => Clip(
        file: '${j['file']}',
        kind: '${j['kind']}',
        over: '${j['over'] ?? ''}',
        batter: '${j['batter'] ?? ''}',
        bowler: '${j['bowler'] ?? ''}',
        label: '${j['label'] ?? ''}',
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class HighlightStore {
  /// Tests point this at a temp folder.
  static Future<Directory> Function() root = () async => Directory('${(await getApplicationDocumentsDirectory()).path}/live');

  static Future<Directory> folder(String matchId) async {
    final d = Directory('${(await root()).path}/$matchId');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<List<Clip>> load(String matchId) async {
    try {
      final f = File('${(await folder(matchId)).path}/clips.json');
      if (!f.existsSync()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [for (final x in list) Clip.fromJson(Map<String, dynamic>.from(x as Map))];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String matchId, List<Clip> clips) async {
    final f = File('${(await folder(matchId)).path}/clips.json');
    await f.writeAsString(jsonEncode([for (final c in clips) c.toJson()]));
  }

  static Future<void> add(String matchId, Clip c) async {
    final list = await load(matchId);
    list.add(c);
    await save(matchId, list);
  }

  static Future<String> path(String matchId, String file) async => '${(await folder(matchId)).path}/$file';
}

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  List<Clip>? _clips;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    HighlightStore.load(widget.matchId).then((c) {
      if (mounted) setState(() => _clips = c..sort((a, b) => a.at.compareTo(b.at)));
    });
  }

  Future<void> _share(Clip c) async {
    final p = await HighlightStore.path(widget.matchId, c.file);
    if (!File(p).existsSync()) return _gone();
    await SharePlus.instance.share(ShareParams(files: [XFile(p, mimeType: 'video/mp4')], text: '🏏 ${c.label} (${c.over}) · GullyScore'));
  }

  void _gone() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('clip_missing'))));
  }

  Future<void> _reel(List<Clip> clips, String name) async {
    if (_busy || clips.isEmpty) return;
    setState(() => _busy = true);
    final failed = context.tr('reel_failed');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final paths = [for (final c in clips) await HighlightStore.path(widget.matchId, c.file)];
      final out = await HighlightStore.path(widget.matchId, 'reel_${DateTime.now().millisecondsSinceEpoch}.mp4');
      final ok = await liveEngine.concat(paths, out);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
        return;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(out, mimeType: 'video/mp4')], text: '🏏 $name · GullyScore'));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(Clip c) async {
    final p = await HighlightStore.path(widget.matchId, c.file);
    if (!File(p).existsSync()) return _gone();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _PlayerDialog(path: p, title: '${c.label} · ${c.over}'));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final clips = _clips;
    final repo = context.repo;
    final byBatter = <String, List<Clip>>{};
    for (final c in clips ?? const <Clip>[]) {
      if (c.kind != 'wicket' && c.batter.isNotEmpty) byBatter.putIfAbsent(c.batter, () => []).add(c);
    }
    final stars = byBatter.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('highlights'))),
      body: clips == null
          ? const Center(child: CircularProgressIndicator())
          : clips.isEmpty
              ? Center(child: EmptyState(icon: Icons.movie_filter_outlined, title: context.tr('no_clips'), body: context.tr('no_clips_body')))
              : ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 40), children: [
                  Text(context.tr('clips_n', {'n': clips.length}), style: Tx.label(p.text2)),
                  const SizedBox(height: Space.s),
                  GoldButton(
                    label: _busy ? context.tr('auth_please_wait') : context.tr('match_reel'),
                    icon: Icons.movie_creation_outlined,
                    onPressed: _busy ? null : () => _reel(clips, context.tr('match_reel')),
                  ),
                  if (stars.isNotEmpty) ...[
                    const SizedBox(height: Space.l),
                    SectionHeader(context.tr('player_reels')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in stars.take(6))
                        ActionChip(
                          avatar: const Icon(Icons.play_circle_outline_rounded, size: 18),
                          label: Text('${repo.playerName(e.key)} · ${e.value.length}'),
                          onPressed: _busy ? null : () => _reel(e.value, repo.playerName(e.key)),
                        ),
                    ]),
                  ],
                  const SizedBox(height: Space.l),
                  SectionHeader(context.tr('all_clips')),
                  for (final c in clips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () => _play(c),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: (c.kind == 'six' ? const Color(0xFFA855F7) : c.kind == 'four' ? const Color(0xFF2B7BD3) : const Color(0xFFE53935)).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(c.kind == 'six' ? '💥' : c.kind == 'four' ? '🏏' : '🎯', style: const TextStyle(fontSize: 20)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                              Text(context.tr('over_n', {'n': c.over}), style: Tx.small(p.text2)),
                            ]),
                          ),
                          IconButton(tooltip: context.tr('share'), onPressed: () => _share(c), icon: Icon(Icons.share_rounded, color: p.goldText)),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}

class _PlayerDialog extends StatefulWidget {
  const _PlayerDialog({required this.path, required this.title});
  final String path;
  final String title;
  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<_PlayerDialog> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AspectRatio(
            aspectRatio: _c.value.isInitialized ? _c.value.aspectRatio : 16 / 9,
            child: _c.value.isInitialized ? VideoPlayer(_c) : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              IconButton(
                onPressed: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                icon: Icon(_c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ),
        ]),
      );
}
