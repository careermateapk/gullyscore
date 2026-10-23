// Go live on YouTube from the phone camera. The score bar and big graphics
// are drawn on the video, every four/six/wicket becomes a clip, the last
// ball can be replayed, and sponsors show at each over break.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../live/highlights.dart';
import '../../live/live_engine.dart';
import '../../live/stream_overlay.dart';
import '../../live/youtube.dart';
import '../../scoring/engine.dart';
import '../../scoring/tournament.dart';
import '../widgets/common.dart';
import 'scoring_sheets.dart';

const _ink = Color(0xFF0B1220);
const _gold = Color(0xFFF4C247);
const _red = Color(0xFFE53935);

enum _Status { ready, connecting, live, reconnecting, failed }

class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  // ---------- setup
  final _key = TextEditingController();
  final _link = TextEditingController();
  bool _showKey = false;
  String _quality = '720';
  String _theme = 'gold';
  bool _graphics = true;
  bool _sponsors = true;
  bool _clips = true;
  bool _camera = false; // false = setup page, true = camera page
  bool _preparing = false;
  String? _setupError;

  // ---------- live
  final _engine = liveEngine;
  StreamSubscription<LiveEvent>? _sub;
  _Status _status = _Status.ready;
  String _reason = '';
  DateTime? _since;
  Timer? _clock;
  bool _muted = false;
  bool _bar = true;
  bool _replaying = false;
  bool _busy = false;

  // ---------- overlay
  final _overlayKey = GlobalKey();
  Graphic _graphic = Graphic.none;
  String _boundary = '';
  String? _batterId;
  Sponsor? _sponsor;
  int _sponsorIndex = 0;
  final _queue = <(Graphic, Object?, int)>[];
  Timer? _graphicTimer;
  bool _pushing = false;
  bool _pushAgain = false;

  // ---------- clips
  int _seg = 0;
  String? _segPath;
  String? _replayClip;
  bool _replayClipKept = false;
  Future<void> _clipJobs = Future.value();
  String _ballsSig = '';
  int _ballCount = -1;
  Set<String> _seenBatters = {};
  int _inningsSeen = -1;
  bool _finishedSeen = false;

  MatchRecord? get _m => context.repo.matches[widget.matchId];

  Repository? _repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = context.repo;
      _repo!.addListener(_onRepo);
    }
  }

  void _onRepo() {
    if (!mounted || !_camera) return;
    final m = _m;
    if (m != null) _watch(m);
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _key.text = p.getString('live.key') ?? '';
        _link.text = p.getString('live.link') ?? '';
        _quality = p.getString('live.quality') ?? '720';
        _theme = p.getString('live.theme') ?? 'gold';
        _graphics = p.getBool('live.graphics') ?? true;
        _sponsors = p.getBool('live.sponsors') ?? true;
        _clips = p.getBool('live.clips') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('live.key', _key.text.trim());
      await p.setString('live.link', _link.text.trim());
      await p.setString('live.quality', _quality);
      await p.setString('live.theme', _theme);
      await p.setBool('live.graphics', _graphics);
      await p.setBool('live.sponsors', _sponsors);
      await p.setBool('live.clips', _clips);
    } catch (_) {}
  }

  @override
  void dispose() {
    _repo?.removeListener(_onRepo);
    _sub?.cancel();
    _clock?.cancel();
    _graphicTimer?.cancel();
    _key.dispose();
    _link.dispose();
    if (_camera) {
      _engine.cutSegment(null);
      _engine.release();
      _restoreOrientation();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ setup → camera

  String get _url {
    final k = _key.text.trim();
    if (k.startsWith('rtmp://') || k.startsWith('rtmps://')) return k;
    return 'rtmp://a.rtmp.youtube.com/live2/$k';
  }

  Future<void> _openCamera() async {
    final m = _m;
    if (m == null) return;
    final link = _link.text.trim();
    final ref = youtubeRef(link);
    if (_key.text.trim().length < 8) {
      setState(() => _setupError = context.tr('live_need_key'));
      return;
    }
    if (link.isNotEmpty && ref == null) {
      setState(() => _setupError = context.tr('live_bad_link'));
      return;
    }
    setState(() {
      _setupError = null;
      _preparing = true;
    });
    await _save();
    if (!mounted) return;
    context.repo.setStream(m, ref ?? '');
    final denied = context.tr('live_need_permission');
    final failed = context.tr('live_camera_failed');
    try {
      final ok = await _engine.permissions();
      if (!ok) {
        setState(() {
          _setupError = denied;
          _preparing = false;
        });
        return;
      }
      if (_engine.real) {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      final hd = _quality == '720';
      await _engine.prepare(width: hd ? 1280 : 854, height: hd ? 720 : 480, bitrate: hd ? 2500 * 1024 : 1200 * 1024);
      _sub ??= _engine.events.listen(_onEvent);
      if (!mounted) return;
      setState(() {
        _camera = true;
        _preparing = false;
      });
      _primeWatch();
      _show(Graphic.intro, null, 6);
    } catch (e) {
      await _restoreOrientation();
      if (mounted) {
        setState(() {
          _setupError = '$failed ($e)';
          _preparing = false;
        });
      }
    }
  }

  Future<void> _restoreOrientation() async {
    if (!_engine.real) return;
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _close() async {
    if (_status == _Status.live || _status == _Status.connecting || _status == _Status.reconnecting) {
      final ok = await _confirmEnd();
      if (!ok) return;
      await _endLive();
    }
    await _engine.cutSegment(null);
    await _engine.release();
    await _restoreOrientation();
    if (!mounted) return;
    setState(() => _camera = false);
    Navigator.maybePop(context);
  }

  // ------------------------------------------------------------ going live

  Future<void> _goLive() async {
    if (_busy) return;
    _busy = true;
    try {
      setState(() {
        _status = _Status.connecting;
        _reason = '';
      });
      await _engine.start(_url);
      if (_clips) {
        _seg = 0;
        _segPath = await HighlightStore.path(widget.matchId, 'seg_$_seg.mp4');
        await _engine.startSegment(_segPath!);
      }
    } catch (e) {
      setState(() {
        _status = _Status.failed;
        _reason = '$e';
      });
    } finally {
      _busy = false;
    }
  }

  Future<bool> _confirmEnd() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('live_end_q')),
          content: Text(ctx.tr('live_end_body')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('live_end'), style: const TextStyle(color: _red))),
          ],
        ),
      ) ??
      false;

  Future<void> _endLive() async {
    await _engine.cutSegment(null);
    final last = _segPath;
    _segPath = null;
    if (last != null) _deleteLater(last);
    await _engine.stop();
    _clock?.cancel();
    if (mounted) {
      setState(() {
        _status = _Status.ready;
        _since = null;
      });
    }
  }

  void _onEvent(LiveEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'connecting':
        setState(() => _status = _Status.connecting);
      case 'live':
        setState(() {
          _status = _Status.live;
          _since ??= DateTime.now();
        });
        _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      case 'reconnecting':
        setState(() => _status = _Status.reconnecting);
      case 'failed':
        _clock?.cancel();
        _clock = null;
        setState(() {
          _status = _Status.failed;
          _reason = '${e.data['reason'] ?? ''}';
        });
      case 'stopped':
        if (_status != _Status.failed) setState(() => _status = _Status.ready);
      case 'replayDone':
        setState(() {
          _replaying = false;
          if (_graphic == Graphic.replay) _graphic = Graphic.none;
        });
        _pushOverlay();
    }
  }

  // ------------------------------------------------------------ overlay

  StreamOverlayState _overlayState(MatchRecord m) {
    final repo = context.repo;
    final st = m.state;
    final sponsors = repo.sponsorsOf(m);
    final title = sponsors.where((s) => s.role == 'title').firstOrNull ?? sponsors.firstOrNull;
    final summary = <(String, String)>[];
    final inn = st.current;
    if (inn != null) {
      final bats = inn.batters.values.toList()..sort((a, b) => b.runs.compareTo(a.runs));
      for (final b in bats.take(3)) {
        summary.add((repo.playerName(b.id), '${b.runs}${b.out ? '' : '*'} (${b.balls})'));
      }
      final bowls = inn.bowlers.values.toList()..sort((a, b) => b.wickets != a.wickets ? b.wickets.compareTo(a.wickets) : a.runs.compareTo(b.runs));
      for (final b in bowls.take(2)) {
        summary.add((repo.playerName(b.id), '${b.wickets}-${b.runs} (${b.overs})'));
      }
    }
    return StreamOverlayState(
      theme: StreamTheme.of(_theme),
      data: OverlayData.of(repo, st, teamA: m.teamA, teamB: m.teamB, title: m.title, venue: m.venue),
      graphic: _graphic,
      showBar: _bar,
      boundary: _boundary,
      batterId: _batterId,
      sponsor: _sponsor,
      cornerSponsor: _sponsors ? title : null,
      summary: summary,
    );
  }

  /// Sends the overlay picture to the camera (after the next frame is drawn).
  void _pushOverlay() {
    if (!_engine.real || !_camera) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final b = _overlayKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (b != null) {
          final img = await b.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          if (data != null) await _engine.overlay(data.buffer.asUint8List());
        }
      } catch (_) {
      } finally {
        _pushing = false;
        if (_pushAgain) {
          _pushAgain = false;
          _pushOverlay();
        }
      }
    });
  }

  /// Shows a big graphic for [seconds]; others wait their turn.
  void _show(Graphic g, Object? payload, int seconds) {
    if (!_graphics && g != Graphic.sponsor && g != Graphic.summary) return;
    if (_graphic != Graphic.none && _graphic != Graphic.replay) {
      _queue.add((g, payload, seconds));
      return;
    }
    _graphicTimer?.cancel();
    setState(() {
      _graphic = g;
      if (g == Graphic.boundary) _boundary = payload as String? ?? '';
      if (g == Graphic.batter) _batterId = payload as String?;
      if (g == Graphic.sponsor) _sponsor = payload as Sponsor?;
    });
    _pushOverlay();
    _graphicTimer = Timer(Duration(seconds: seconds), _hideGraphic);
  }

  void _hideGraphic() {
    if (!mounted) return;
    _graphicTimer?.cancel();
    setState(() => _graphic = Graphic.none);
    _pushOverlay();
    if (_queue.isNotEmpty) {
      final (g, p, s) = _queue.removeAt(0);
      _show(g, p, s);
    }
  }

  // ------------------------------------------------------------ watching the score

  void _primeWatch() {
    final m = _m;
    if (m == null) return;
    final st = m.state;
    final inn = st.current;
    _ballCount = inn?.balls.length ?? 0;
    _inningsSeen = inn?.number ?? -1;
    _seenBatters = {...?inn?.battingOrder};
    _finishedSeen = st.finished;
    _ballsSig = _sig(m);
  }

  String _sig(MatchRecord m) => '${m.events.length}';

  /// Called when the match changes (a ball, undo, new batter...).
  void _watch(MatchRecord m) {
    final sig = _sig(m);
    if (sig == _ballsSig) return;
    _ballsSig = sig;
    final st = m.state;
    final inn = st.current;
    final count = inn?.balls.length ?? 0;
    final number = inn?.number ?? -1;
    if (number != _inningsSeen) {
      _inningsSeen = number;
      _ballCount = count;
      _seenBatters = {...?inn?.battingOrder};
    } else if (inn != null && count > _ballCount) {
      _ballCount = count;
      _onBall(m, st, inn, inn.balls.last);
    } else {
      _ballCount = count;
    }
    if (inn != null) {
      for (final id in inn.battingOrder) {
        if (_seenBatters.add(id) && inn.battingOrder.length > 2) _show(Graphic.batter, id, 7);
      }
    }
    if (st.finished && !_finishedSeen) {
      _finishedSeen = true;
      _show(Graphic.summary, null, 15);
    } else if (inn != null && inn.ended && inn.number == 0) {
      _show(Graphic.summary, null, 12);
    }
    _pushOverlay();
  }

  void _onBall(MatchRecord m, MatchState st, Innings inn, BallLog b) {
    final repo = context.repo;
    String? kind;
    if (b.isWicket) {
      kind = 'wicket';
    } else if (b.isSix) {
      kind = 'six';
    } else if (b.isFour) {
      kind = 'four';
    }
    if (kind != null) _show(Graphic.boundary, kind == 'six' ? 'SIX!' : kind == 'four' ? 'FOUR!' : 'WICKET!', 3);
    // over finished: sponsor card, or the chase graphic near the end
    if (b.legal && inn.legalBalls % 6 == 0 && !inn.ended && !st.finished) {
      final sponsors = repo.sponsorsOf(m);
      final need = st.runsNeeded;
      final left = st.ballsLeft;
      if (_sponsors && sponsors.isNotEmpty) {
        _show(Graphic.sponsor, sponsors[_sponsorIndex++ % sponsors.length], 7);
      }
      if (inn.number == 1 && need != null && left != null && left <= 36 && need > 0) _show(Graphic.need, null, 6);
    }
    _cutClip(b, kind, repo.playerName(b.outPlayer ?? b.striker));
  }

  // ------------------------------------------------------------ clips and replay

  void _cutClip(BallLog b, String? kind, String who) {
    final prev = _segPath;
    if (prev == null || !_clips) return;
    _seg++;
    final matchId = widget.matchId;
    final over = b.overBall;
    final striker = b.striker;
    final bowler = b.bowler;
    final label = kind == null ? '' : '${kind == 'six' ? 'SIX' : kind == 'four' ? 'FOUR' : 'WICKET'} · $who';
    _clipJobs = _clipJobs.then((_) async {
      final next = await HighlightStore.path(matchId, 'seg_$_seg.mp4');
      _segPath = next;
      await _engine.cutSegment(next);
      final dur = await _engine.durationMs(prev);
      final name = 'clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final out = await HighlightStore.path(matchId, name);
      final ok = dur > 1000 && await _engine.trim(prev, out, (dur - 10000).clamp(0, dur), dur);
      _deleteLater(prev);
      if (!ok) return;
      final old = _replayClip;
      if (old != null && !_replayClipKept) _deleteLater(old);
      _replayClip = out;
      _replayClipKept = kind != null;
      if (kind != null) {
        await HighlightStore.add(matchId, Clip(file: name, kind: kind, over: over, batter: striker, bowler: bowler, label: label, at: DateTime.now().millisecondsSinceEpoch));
      }
    }).catchError((_) {});
  }

  void _deleteLater(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _replay() async {
    final clip = _replayClip;
    if (_replaying) return;
    if (clip == null || !File(clip).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(_clips ? 'live_no_replay' : 'live_clips_off'))));
      return;
    }
    _graphicTimer?.cancel();
    setState(() {
      _replaying = true;
      _graphic = Graphic.replay;
    });
    _pushOverlay();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _engine.replay(clip);
  }

  // ------------------------------------------------------------ scoring

  void _add(Map<String, dynamic> e) {
    final m = _m;
    if (m == null) return;
    if (context.settings.haptics) HapticFeedback.selectionClick();
    context.repo.addEvent(m, e);
  }

  Future<String?> _addPlayer(MatchRecord m, int team, String name) async {
    final repo = context.repo;
    final t = repo.teams[team == 0 ? m.teamA : m.teamB];
    if (t == null) return null;
    final p = repo.addPlayer(t, name);
    (team == 0 ? m.playersA : m.playersB).add(p.id);
    repo.setEvents(m, m.events);
    return p.id;
  }

  Future<int?> _pickRuns(String title, List<int> options) => showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in options)
              SizedBox(
                width: 54,
                height: 46,
                child: OutlinedButton(onPressed: () => Navigator.pop(ctx, r), style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), child: Text('$r', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              ),
          ]),
        ),
      );

  Future<void> _extra(String kind) async {
    final options = switch (kind) {
      BallKind.wide => [0, 1, 2, 3, 4],
      BallKind.noBall => [0, 1, 2, 3, 4, 5, 6],
      _ => [1, 2, 3, 4],
    };
    final r = await _pickRuns(extraTitle(context, kind), options);
    if (r == null || !mounted) return;
    _add({'t': Ev.ball, 'kind': kind, 'runs': r});
  }

  Future<void> _wicket(MatchRecord m, MatchState st) async {
    final inn = st.current!;
    final w = await pickWicket(
      context,
      striker: inn.striker!,
      nonStriker: inn.nonStriker!,
      fielders: st.bowlingTeamNow == 0 ? m.playersA : m.playersB,
      name: context.repo.playerName,
    );
    if (w == null || !mounted) return;
    _add({
      't': Ev.ball,
      'kind': BallKind.normal,
      'runs': w.runs,
      'out': {'kind': w.kind, 'player': w.outPlayer, if (w.fielder != null) 'fielder': w.fielder},
    });
  }

  Future<void> _nextStep(MatchRecord m, MatchState st) async {
    final repo = context.repo;
    final name = repo.playerName;
    List<String> squad(int t) => t == 0 ? m.playersA : m.playersB;
    switch (st.nextStep) {
      case NextStep.startInnings:
        final bat = st.battingTeamNow;
        final bowl = 1 - bat;
        final s = await pickPlayer(context, title: context.tr('pick_striker'), ids: squad(bat), name: name, onAdd: (n) => _addPlayer(m, bat, n));
        if (s == null || !mounted) return;
        final n = await pickPlayer(context,
            title: context.tr('pick_non_striker'), ids: squad(bat).where((p) => p != s).toList(), name: name, onAdd: (x) => _addPlayer(m, bat, x));
        if (n == null || !mounted) return;
        final b = await pickPlayer(context, title: context.tr('pick_bowler'), ids: squad(bowl), name: name, onAdd: (x) => _addPlayer(m, bowl, x));
        if (b == null || !mounted) return;
        _add({'t': Ev.start, 'striker': s, 'nonStriker': n, 'bowler': b});
      case NextStep.newBatter:
        final bat = st.battingTeamNow;
        final id = await pickPlayer(context, title: context.tr('pick_new_batter'), ids: st.availableBatters(), name: name, onAdd: (x) => _addPlayer(m, bat, x));
        if (id == null || !mounted) return;
        _add({'t': Ev.batter, 'player': id});
      case NextStep.newBowler:
        final bowl = st.bowlingTeamNow;
        final last = st.current?.lastOverBowler;
        final id = await pickPlayer(context,
            title: context.tr('pick_next_bowler'),
            ids: squad(bowl),
            name: name,
            disabled: last == null ? const <String>{} : {last},
            disabledReason: context.tr('bowled_last_over'),
            onAdd: (x) => _addPlayer(m, bowl, x));
        if (id == null || !mounted) return;
        _add({'t': Ev.bowler, 'player': id});
      case NextStep.ball:
      case NextStep.finished:
        break;
    }
  }

  void _undo(MatchRecord m) {
    if (!m.events.any((e) => e['t'] == Ev.ball)) return;
    context.repo.setEvents(m, undoLast(m.events));
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final m = _m;
        if (m == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('match_not_found'))));
        }
        if (_camera) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _close();
            },
            child: _cameraPage(m),
          );
        }
        return _setupPage(m);
      },
    );
  }

  // ---------- setup page

  Widget _setupPage(MatchRecord m) {
    final p = Palette.of(context);
    final repo = context.repo;
    final hasSponsors = repo.sponsorsOf(m).isNotEmpty;
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Text('$n', style: Tx.label(p.goldText)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Tx.small(p.text))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('live_title'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 40), children: [
        Text('${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}', style: Tx.section(p.text)),
        const SizedBox(height: 4),
        Text(context.tr('live_sub'), style: Tx.small(p.text2)),
        const SizedBox(height: Space.m),
        AppCard(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(context.tr('live_how_title'), style: Tx.body(p.text, w: FontWeight.w800)),
              subtitle: Text(context.tr('live_how_sub'), style: Tx.small(p.text2)),
              children: [
                step(1, context.tr('live_how_1')),
                step(2, context.tr('live_how_2')),
                step(3, context.tr('live_how_3')),
                step(4, context.tr('live_how_4')),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://studio.youtube.com'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(context.tr('live_open_studio')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: context.tr('live_key'),
            helperText: context.tr('live_key_help'),
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              tooltip: context.tr('auth_show_password'),
              onPressed: () => setState(() => _showKey = !_showKey),
              icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: context.tr('live_link'),
            helperText: context.tr('live_link_help'),
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.smart_display_outlined),
          ),
        ),
        const SizedBox(height: Space.l),
        Text(context.tr('live_quality'), style: Tx.label(p.text2)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: Text(context.tr('live_hd')), selected: _quality == '720', onSelected: (_) => setState(() => _quality = '720')),
          ChoiceChip(label: Text(context.tr('live_sd')), selected: _quality == '480', onSelected: (_) => setState(() => _quality = '480')),
        ]),
        const SizedBox(height: Space.l),
        Text(context.tr('live_theme'), style: Tx.label(p.text2)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in StreamTheme.all)
            Semantics(
              button: true,
              selected: t.id == _theme,
              label: context.tr('theme_${t.id}'),
              child: GestureDetector(
                onTap: () => setState(() => _theme = t.id),
                child: Container(
                  width: 92,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.id == _theme ? p.goldText : p.line, width: t.id == _theme ? 2.5 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(children: [
                      Expanded(flex: 2, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: t.a)))),
                      Expanded(flex: 3, child: ColoredBox(color: t.b, child: Center(child: Text(context.tr('theme_${t.id}'), maxLines: 1, style: TextStyle(color: t.bText, fontSize: 10, fontWeight: FontWeight.w800))))),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: Space.m),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _graphics,
          onChanged: (v) => setState(() => _graphics = v),
          title: Text(context.tr('live_graphics')),
          subtitle: Text(context.tr('live_graphics_sub')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _sponsors && hasSponsors,
          onChanged: hasSponsors ? (v) => setState(() => _sponsors = v) : null,
          title: Text(context.tr('live_sponsors')),
          subtitle: Text(context.tr(hasSponsors ? 'live_sponsors_sub' : 'live_no_sponsors')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _clips,
          onChanged: (v) => setState(() => _clips = v),
          title: Text(context.tr('live_clips')),
          subtitle: Text(context.tr('live_clips_sub')),
        ),
        if (_setupError != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(_setupError!, style: Tx.small(p.liveText, w: FontWeight.w800)),
          ),
        const SizedBox(height: Space.m),
        GoldButton(
          label: _preparing ? context.tr('auth_please_wait') : context.tr('live_open_camera'),
          icon: Icons.videocam_rounded,
          onPressed: _preparing ? null : _openCamera,
        ),
        const SizedBox(height: Space.s),
        Text(context.tr('live_battery'), textAlign: TextAlign.center, style: Tx.small(p.text2)),
      ]),
    );
  }

  // ---------- camera page

  Widget _cameraPage(MatchRecord m) {
    final st = m.state;
    final overlay = _overlayState(m);
    final live = _status == _Status.live || _status == _Status.reconnecting || _status == _Status.connecting;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Stack(children: [
          Positioned.fill(child: _engine.preview()),
          // What goes on the video, drawn off-screen and sent to the camera.
          Positioned(
            left: -3000,
            top: 0,
            width: overlaySize.width,
            height: overlaySize.height,
            child: RepaintBoundary(key: _overlayKey, child: StreamOverlay(state: overlay)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                Row(children: [
                  _statusChip(),
                  const Spacer(),
                  if (_replaying) _chip(context.tr('live_replaying'), _red),
                ]),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _column([
                      _btn(live ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, live ? context.tr('live_end') : context.tr('live_go'),
                          live ? () async {
                              if (await _confirmEnd()) await _endLive();
                            } : _goLive,
                          color: _red, filled: true),
                      _btn(Icons.replay_rounded, context.tr('live_replay'), _replaying ? null : _replay),
                      _btn(_muted ? Icons.mic_off_rounded : Icons.mic_rounded, context.tr(_muted ? 'live_unmute' : 'live_mute'), () {
                        setState(() => _muted = !_muted);
                        _engine.mute(_muted);
                      }),
                      _btn(Icons.cameraswitch_rounded, context.tr('live_switch_camera'), _engine.switchCamera),
                    ]),
                    const Spacer(),
                    _column([
                      _graphicsMenu(m),
                      _btn(_bar ? Icons.subtitles_rounded : Icons.subtitles_off_rounded, context.tr('live_score_bar'), () {
                        setState(() => _bar = !_bar);
                        _pushOverlay();
                      }),
                      _btn(Icons.movie_filter_outlined, context.tr('highlights'),
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => HighlightsScreen(matchId: m.id)))),
                      _btn(Icons.close_rounded, context.tr('close'), _close),
                    ]),
                  ]),
                ),
                const SizedBox(height: 6),
                _pad(m, st),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String text, Color c, {Widget? lead}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (lead != null) ...[lead, const SizedBox(width: 6)],
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      );

  Widget _statusChip() {
    switch (_status) {
      case _Status.ready:
        return _chip(context.tr('live_ready'), const Color(0xB3000000));
      case _Status.connecting:
        return _chip(context.tr('live_connecting'), const Color(0xCC8A6D1B));
      case _Status.reconnecting:
        return _chip(context.tr('live_reconnecting'), const Color(0xCC8A6D1B));
      case _Status.failed:
        return Flexible(child: _chip('${context.tr('live_failed')} ${_reason.isEmpty ? '' : '· $_reason'}', _red));
      case _Status.live:
        final d = _since == null ? Duration.zero : DateTime.now().difference(_since!);
        String two(int n) => n.toString().padLeft(2, '0');
        final t = d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
        return _chip('LIVE  $t', _red, lead: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)));
    }
  }

  Widget _column(List<Widget> children) => SizedBox(
        width: 50,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: children),
            ),
          ),
        ),
      );

  Widget _btn(IconData icon, String tip, VoidCallback? onTap, {Color? color, bool filled = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            label: tip,
            child: Material(
              color: filled ? (color ?? _gold) : const Color(0xB30B1220),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: onTap,
                child: SizedBox(width: 46, height: 46, child: Icon(icon, color: onTap == null ? Colors.white38 : Colors.white, size: 22)),
              ),
            ),
          ),
        ),
      );

  Widget _graphicsMenu(MatchRecord m) {
    final repo = context.repo;
    final sponsors = repo.sponsorsOf(m);
    final st = m.state;
    final inn = st.current;
    return PopupMenuButton<String>(
      tooltip: context.tr('live_graphics_menu'),
      onSelected: (v) {
        _queue.clear();
        _graphicTimer?.cancel();
        setState(() => _graphic = Graphic.none);
        switch (v) {
          case 'intro':
            _show(Graphic.intro, null, 8);
          case 'need':
            _show(Graphic.need, null, 8);
          case 'batter':
            _show(Graphic.batter, inn?.striker, 8);
          case 'summary':
            _show(Graphic.summary, null, 12);
          case 'sponsor':
            if (sponsors.isNotEmpty) _show(Graphic.sponsor, sponsors[_sponsorIndex++ % sponsors.length], 8);
          case 'hide':
            _pushOverlay();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'intro', child: Text(ctx.tr('live_g_intro'))),
        if (st.runsNeeded != null && (inn?.number ?? 0) == 1) PopupMenuItem(value: 'need', child: Text(ctx.tr('live_g_need'))),
        if (inn?.striker != null) PopupMenuItem(value: 'batter', child: Text(ctx.tr('live_g_batter'))),
        PopupMenuItem(value: 'summary', child: Text(ctx.tr('live_g_summary'))),
        if (sponsors.isNotEmpty) PopupMenuItem(value: 'sponsor', child: Text(ctx.tr('live_g_sponsor'))),
        PopupMenuItem(value: 'hide', child: Text(ctx.tr('live_g_hide'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: const Color(0xB30B1220), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// The scoring buttons along the bottom.
  Widget _pad(MatchRecord m, MatchState st) {
    Widget key(String label, VoidCallback onTap, {Color? bg, Color fg = Colors.white}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: bg ?? const Color(0xD90B1220),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: SizedBox(
                  height: 42,
                  child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16)))),
                ),
              ),
            ),
          ),
        );
    final next = st.nextStep;
    if (next != NextStep.ball) {
      final label = switch (next) {
        NextStep.startInnings => context.tr('pick_openers'),
        NextStep.newBatter => context.tr('pick_new_batter'),
        NextStep.newBowler => context.tr('pick_next_bowler'),
        _ => context.tr('match_finished'),
      };
      return Row(children: [
        key(label, () => _nextStep(m, st), bg: next == NextStep.finished ? null : _gold, fg: next == NextStep.finished ? Colors.white : _ink),
        if (m.events.any((e) => e['t'] == Ev.ball)) SizedBox(width: 70, child: Row(children: [key('↶', () => _undo(m))])),
      ]);
    }
    return Row(children: [
      for (final r in [0, 1, 2, 3, 4, 6])
        key('$r', () => _add({'t': Ev.ball, 'kind': BallKind.normal, 'runs': r}),
            bg: r == 4 ? const Color(0xE62B7BD3) : r == 6 ? const Color(0xE6A855F7) : null),
      key(context.tr('wd_short'), () => _extra(BallKind.wide)),
      key(context.tr('nb_short'), () => _extra(BallKind.noBall)),
      key(context.tr('bye_short'), () => _extra(BallKind.bye)),
      key('W', () => _wicket(m, st), bg: const Color(0xE6E53935)),
      key('↶', () => _undo(m)),
    ]);
  }
}

/// Menu → Live streaming: pick which of your matches to stream.
Future<void> pickMatchToStream(BuildContext context) async {
  final repo = context.repo;
  final mine = [for (final m in repo.matchList) if (!m.remote && !m.state.finished) m];
  if (mine.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('live_no_match'))));
    return;
  }
  if (mine.length == 1) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveStreamScreen(matchId: mine.first.id)));
    return;
  }
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(ctx.tr('live_pick_match'), style: Tx.section(Palette.of(ctx).text))),
        for (final m in mine)
          ListTile(
            leading: const Icon(Icons.sports_cricket_rounded),
            title: Text('${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: m.title.isEmpty ? null : Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, m.id),
          ),
      ]),
    ),
  );
  if (id != null && context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveStreamScreen(matchId: id)));
}
