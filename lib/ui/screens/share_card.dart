// Score card picture for WhatsApp and other apps.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/engine.dart';
import '../widgets/common.dart';
import 'scoring_sheets.dart';

/// Share choices for a match: picture, and live link when online is set up.
Future<void> showShareOptions(BuildContext context, MatchRecord m) async {
  final sync = context.sync;
  if (!sync.enabled) return shareMatchCard(context, m);
  final choice = await showAppSheet<String>(context, (ctx) {
    final p = Palette.of(ctx);
    Widget option(IconData icon, String title, String sub, String value) => ListTile(
          leading: Icon(icon, color: p.goldText),
          title: Text(title, style: Tx.body(p.text, w: FontWeight.w700)),
          subtitle: Text(sub, style: Tx.label(p.text2, w: FontWeight.w500)),
          minTileHeight: 64,
          onTap: () => Navigator.pop(ctx, value),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(ctx.tr('share_score')),
        option(Icons.link_rounded, ctx.tr('share_live_link'), ctx.tr('share_live_link_sub'), 'link'),
        option(Icons.image_outlined, ctx.tr('share_picture'), ctx.tr('share_picture_sub'), 'picture'),
      ]),
    );
  });
  if (choice == null || !context.mounted) return;
  if (choice == 'picture') return shareMatchCard(context, m);
  final repo = context.repo;
  final messenger = ScaffoldMessenger.of(context);
  final offline = context.tr('link_needs_internet');
  final text = context.tr('live_link_text', {'a': repo.teamName(m.teamA), 'b': repo.teamName(m.teamB), 'link': sync.liveLink(m.id)});
  var online = true;
  try {
    if (!m.remote) await sync.pushNow(m.id);
  } catch (_) {
    online = false; // the link still works once this phone gets internet
  }
  await SharePlus.instance.share(ShareParams(text: text));
  if (!online) messenger.showSnackBar(SnackBar(content: Text(offline)));
}

/// Share sheet for any picture: shows [child] and shares it as a PNG.
Future<void> sharePicture(BuildContext context, {required String title, required Widget child, required String text, required String fileName}) {
  return showAppSheet<void>(context, (ctx) => _ShareSheet(title: title, text: text, fileName: fileName, child: child));
}

Future<void> shareMatchCard(BuildContext context, MatchRecord m) {
  final repo = context.repo;
  final st = m.state;
  final lines = <String>['${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}'];
  for (final inn in st.innings) {
    final t = inn.battingTeam == 0 ? m.teamA : m.teamB;
    lines.add('${repo.teamName(t)} ${inn.runs}/${inn.wickets} (${inn.overs})');
  }
  if (st.finished) lines.add(st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB)));
  lines.add(context.tr('scored_with'));
  return sharePicture(context, title: context.tr('share_score'), text: lines.join('\n'), fileName: 'gullyscore-${m.id}', child: ScoreCardImage(m: m));
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.title, required this.text, required this.fileName, required this.child});
  final String title;
  final String text;
  final String fileName;
  final Widget child;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundary = GlobalKey();
  bool _working = false;
  String? _error;

  Future<void> _share() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final failed = context.tr('share_failed');
    try {
      final obj = _boundary.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) throw StateError('not ready');
      final image = await obj.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('no bytes');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.fileName}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: widget.text));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: Tx.section(p.text).copyWith(fontSize: 19)),
        const SizedBox(height: Space.m),
        RepaintBoundary(key: _boundary, child: widget.child),
        if (_error != null) ...[
          const SizedBox(height: Space.s),
          Text(_error!, style: Tx.small(p.liveText)),
        ],
        const SizedBox(height: Space.l),
        GoldButton(
          label: _working ? context.tr('preparing') : context.tr('share_picture'),
          icon: Icons.share_rounded,
          onPressed: _working ? null : _share,
        ),
      ]),
    );
  }
}

/// The picture itself. Always dark so it looks the same for everyone.
class ScoreCardImage extends StatelessWidget {
  const ScoreCardImage({super.key, required this.m});
  final MatchRecord m;

  @override
  Widget build(BuildContext context) {
    const p = Palette.darkP;
    final repo = context.repo;
    final st = m.state;
    Widget row(Innings inn) {
      final t = repo.teams[inn.battingTeam == 0 ? m.teamA : m.teamB];
      final top = inn.batters.values.toList()..sort((a, b) => b.runs.compareTo(a.runs));
      final best = inn.bowlers.values.toList()..sort((a, b) => b.wickets != a.wickets ? b.wickets.compareTo(a.wickets) : a.runs.compareTo(b.runs));
      return Padding(
        padding: const EdgeInsets.only(top: Space.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Crest(logo: t?.logo, color: Palette.team(t?.colorIndex ?? 0), text: t?.short ?? '', size: 30),
            const SizedBox(width: Space.s),
            Expanded(child: Text(t?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800))),
            const SizedBox(width: Space.s),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${inn.runs}/${inn.wickets}', style: Tx.score(30, p.text)),
                  const SizedBox(width: 6),
                  Text('(${inn.overs})', style: Tx.score(16, p.text2, w: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
          if (top.isNotEmpty && top.first.runs > 0)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 4),
              child: Text('${repo.playerName(top.first.id)} ${top.first.runs}${top.first.out ? '' : '*'} (${top.first.balls})', style: Tx.small(p.text2)),
            ),
          if (best.isNotEmpty && best.first.wickets > 0)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 2),
              child: Text('${repo.playerName(best.first.id)} ${best.first.wickets}/${best.first.runs}', style: Tx.small(p.text2)),
            ),
        ]),
      );
    }

    final status = st.finished
        ? st.resultText(repo.teamName(m.teamA), repo.teamName(m.teamB))
        : (st.current != null && st.innings.length == 2 && !st.current!.ended)
            ? context.tr('need_runs', {'n': st.runsNeeded ?? 0, 'b': st.ballsLeft ?? 0})
            : context.tr('in_progress');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corners.hero),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF17325A), Color(0xFF070F1E)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: p.gold, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.bar_chart_rounded, size: 20, color: Color(0xFF070F1E)),
          ),
          const SizedBox(width: Space.s),
          Flexible(child: Text('GullyScore', maxLines: 1, overflow: TextOverflow.clip, style: Tx.score(20, p.text, w: FontWeight.w800))),
          const Spacer(),
          if (m.title.isNotEmpty) Flexible(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2))),
        ]),
        for (final inn in st.innings) row(inn),
        const SizedBox(height: Space.m),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Text(status, style: Tx.body(p.goldText, w: FontWeight.w800).copyWith(fontSize: 14)),
        ),
        if (m.venue.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text(m.venue, style: Tx.label(p.text2)),
        ],
      ]),
    );
  }
}
