// Instagram-style stories: Season Wrapped (a player's year) and the Match Story.
// Every slide is a 360 × 640 picture that can be shared on its own.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../data/models.dart';
import '../data/photos.dart';
import '../scoring/engine.dart';
import '../scoring/insights.dart';
import '../scoring/stats.dart';
import '../scoring/tournament.dart';
import 'designs.dart';
import 'share_entry.dart';
import 'studio_screen.dart';
import 'themes.dart';

typedef SlideBuilder = Widget Function(String lang);

/// Full-screen stories with progress bars. Tap right for next, left for back.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.title, required this.slides, required this.fileName, required this.shareText});
  final String title;
  final List<SlideBuilder> slides;
  final String fileName;
  final String shareText;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  final _key = GlobalKey();
  int _i = 0;
  bool _working = false;

  void _go(int d) {
    final n = _i + d;
    if (n < 0) return;
    if (n >= widget.slides.length) {
      Navigator.maybePop(context);
      return;
    }
    setState(() => _i = n);
  }

  Future<void> _share() async {
    setState(() => _working = true);
    final failed = context.tr('share_failed');
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await sharePng(_key, fileName: '${widget.fileName}-${_i + 1}', text: widget.shareText)) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.settings.lang;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              for (var k = 0; k < widget.slides.length; k++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: Colors.white.withValues(alpha: k <= _i ? 1 : 0.3)),
                  ),
                ),
                if (k < widget.slides.length - 1) const SizedBox(width: 4),
              ],
            ]),
          ),
          Row(children: [
            const SizedBox(width: 12),
            Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            IconButton(
              tooltip: context.tr('close'),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ]),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final w = MediaQuery.sizeOf(context).width;
                _go(d.localPosition.dx < w * 0.33 ? -1 : 1);
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    // One slide at a time: the share key must sit on a single picture.
                    child: StudioCanvas(key: ValueKey(_i), size: StudioSize.story, boundaryKey: _key, child: widget.slides[_i](lang)),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B1220), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _working ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: Text(_working ? context.tr('preparing') : context.tr('share_this'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                height: 50,
                child: IconButton.filledTonal(
                  tooltip: context.tr('next'),
                  style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                  onPressed: () => _go(1),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- slide helpers

Widget _fit(Widget w, {Alignment align = Alignment.center}) => FittedBox(fit: BoxFit.scaleDown, alignment: align, child: w);

class _Slide extends StatelessWidget {
  const _Slide({required this.theme, required this.children, this.center = false});
  final StudioTheme theme;
  final List<Widget> children;
  final bool center;
  @override
  Widget build(BuildContext context) => StudioBackground(
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
              Row(children: [StudioBrand(theme: theme), const Spacer()]),
              ...children,
            ],
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.theme, required this.emoji, required this.label, required this.value});
  final StudioTheme theme;
  final String emoji;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Glass(
        theme: theme,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 6),
          _fit(Text(label.toUpperCase(), maxLines: 1, style: studioCap(theme, size: 6.8)), align: Alignment.centerLeft),
          const SizedBox(height: 3),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: studioText(11, theme.text, w: FontWeight.w800, height: 1.25)),
        ]),
      );
}

Widget _bigStat(StudioTheme t, String v, String label) => Expanded(
      child: Glass(
        theme: t,
        radius: 14,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Column(children: [
          _fit(Text(v, style: studioNum(24, t.text))),
          const SizedBox(height: 3),
          _fit(Text(label.toUpperCase(), style: studioCap(t, size: 6.5))),
        ]),
      ),
    );

const _dayKeys = ['day_mon', 'day_tue', 'day_wed', 'day_thu', 'day_fri', 'day_sat', 'day_sun'];

// ---------------------------------------------------------------- Season Wrapped

Future<void> openSeasonWrapped(BuildContext context, String playerId) {
  final repo = context.repo;
  final name = repo.playerName(playerId);
  final year = DateTime.now().year;
  var recs = repo.matchList.where((m) => (m.playersA.contains(playerId) || m.playersB.contains(playerId)) && (m.scheduledAt ?? m.createdAt).year == year).toList();
  var label = '$year';
  if (recs.isEmpty) {
    recs = repo.matchList.where((m) => m.playersA.contains(playerId) || m.playersB.contains(playerId)).toList();
    label = '';
  }
  WrappedMatch wm(MatchRecord m) => WrappedMatch(
        StatMatch(id: m.id, teamIds: [m.teamA, m.teamB], state: m.state),
        m.scheduledAt ?? m.createdAt,
        m.venue,
        opponentOf: (id) => m.playersA.contains(id) ? m.teamB : m.teamA,
      );
  final list = [for (final m in recs) wm(m)];
  // runs of every player on this phone in the same matches window, for the rank
  final runs = <String, int>{};
  for (final m in (label.isEmpty ? repo.matchList : repo.matchList.where((m) => (m.scheduledAt ?? m.createdAt).year == year))) {
    for (final inn in m.state.innings) {
      for (final b in inn.batters.values) {
        runs[b.id] = (runs[b.id] ?? 0) + b.runs;
      }
    }
  }
  final w = seasonWrapped(playerId, list, runsByPlayer: runs);
  final s = playerStats(playerId, [for (final x in list) x.stat]);
  final level = Level(xpOf(s, potm: w.potm));
  final photo = PhotoStore.file(repo.players[playerId]?.photo);
  final first = name.split(' ').first;
  final sunset = themeById('sunset');
  final neon = themeById('neon');
  final midnight = themeById('midnight');
  final royal = themeById('royal');
  final emerald = themeById('emerald');

  final slides = <SlideBuilder>[
    (lang) => _Slide(theme: sunset, center: true, children: [
          const Spacer(),
          Text(st('wrapped_hello', lang, {'name': first}).toUpperCase(), textAlign: TextAlign.center, style: studioText(9.5, Colors.white, w: FontWeight.w800, spacing: 3)),
          const SizedBox(height: 8),
          _fit(Text(label.isEmpty ? st('wrapped_all_time', lang).toUpperCase() : label, style: studioNum(110, Colors.white, height: 0.85, spacing: -2))),
          _fit(Text(st('wrapped_in_cricket', lang).toUpperCase(), style: studioNum(28, Colors.white, spacing: 5))),
          const SizedBox(height: 26),
          Row(children: [
            _bigStat(sunset, '${w.matches}', st('matches', lang)),
            const SizedBox(width: 7),
            _bigStat(sunset, '${w.runs}', st('runs', lang)),
            const SizedBox(width: 7),
            _bigStat(sunset, '${w.wickets}', st('wickets', lang)),
          ]),
          const SizedBox(height: 18),
          Text(st('wrapped_tap', lang), style: studioText(11, Colors.white.withValues(alpha: 0.9), w: FontWeight.w700)),
          const Spacer(),
        ]),
    (lang) => _Slide(theme: midnight, children: [
          const Spacer(),
          Text(st('wrapped_bat_title', lang).toUpperCase(), style: studioCap(midnight, size: 9).copyWith(letterSpacing: 2.4)),
          const SizedBox(height: 6),
          _fit(FoilText('${w.runs}', theme: midnight, size: 120, height: 0.85), align: Alignment.centerLeft),
          Text(st('runs', lang).toUpperCase(), style: studioNum(26, midnight.text, spacing: 4)),
          const SizedBox(height: 16),
          Text(
            w.bestRuns >= 0
                ? st('wrapped_best_inn', lang, {'r': '${w.bestRuns}${w.bestNotOut ? '*' : ''}', 't': w.bestAgainst == null ? '' : repo.teamName(w.bestAgainst!)})
                : st('wrapped_no_bat', lang),
            style: studioText(12, midnight.text, w: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _bigStat(midnight, w.balls == 0 ? '-' : w.strikeRate.toStringAsFixed(0), st('strike_rate', lang)),
            const SizedBox(width: 7),
            _bigStat(midnight, '${w.fours}', st('fours', lang)),
            const SizedBox(width: 7),
            _bigStat(midnight, '${w.sixes}', st('sixes', lang)),
          ]),
          const Spacer(),
        ]),
    (lang) => _Slide(theme: neon, children: [
          const SizedBox(height: 26),
          Text(st('wrapped_persona_title', lang).toUpperCase(), style: studioCap(neon, size: 8.5).copyWith(letterSpacing: 2.4)),
          const SizedBox(height: 8),
          _fit(FoilText(st('persona_${w.personality}', lang).toUpperCase(), theme: neon, size: 44, height: 0.95), align: Alignment.centerLeft),
          const SizedBox(height: 8),
          Text(st('persona_${w.personality}_line', lang), style: studioText(11.5, const Color(0xFFCFE9F2), w: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _Tile(theme: neon, emoji: '🏟', label: st('wrapped_fav_ground', lang), value: w.favouriteGround == null ? '-' : st('wrapped_ground_line', lang, {'g': w.favouriteGround!, 'n': w.favouriteGroundMatches}))),
            const SizedBox(width: 8),
            Expanded(child: _Tile(theme: neon, emoji: '📅', label: st('wrapped_best_day', lang), value: w.bestWeekday == null ? '-' : st('wrapped_day_line', lang, {'d': st(_dayKeys[w.bestWeekday! - 1], lang), 'a': w.bestWeekdayAvg.round()}))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Tile(theme: neon, emoji: '😈', label: st('wrapped_nemesis', lang), value: w.nemesis == null ? st('wrapped_no_nemesis', lang) : st('wrapped_nemesis_line', lang, {'p': repo.playerName(w.nemesis!), 'n': w.nemesisOuts}))),
            const SizedBox(width: 8),
            Expanded(child: _Tile(theme: neon, emoji: '🤝', label: st('wrapped_partner', lang), value: w.partner == null ? '-' : st('wrapped_partner_line', lang, {'p': repo.playerName(w.partner!), 'n': w.partnerRuns}))),
          ]),
          const Spacer(),
        ]),
    (lang) => _Slide(theme: emerald, children: [
          const Spacer(),
          Text(st('wrapped_bowl_title', lang).toUpperCase(), style: studioCap(emerald, size: 9).copyWith(letterSpacing: 2.4)),
          const SizedBox(height: 10),
          Row(children: [
            _bigStat(emerald, '${w.wickets}', st('wickets', lang)),
            const SizedBox(width: 7),
            _bigStat(emerald, '${w.catches}', st('catches', lang)),
            const SizedBox(width: 7),
            _bigStat(emerald, '${w.potm}', st('potm_short', lang)),
          ]),
          const SizedBox(height: 14),
          if (w.bunny != null)
            _Tile(theme: emerald, emoji: '🎯', label: st('wrapped_bunny', lang), value: st('wrapped_bunny_line', lang, {'p': repo.playerName(w.bunny!), 'n': w.bunnyOuts})),
          const Spacer(),
        ]),
    (lang) => _Slide(theme: royal, center: true, children: [
          const Spacer(),
          FoilPortrait(theme: royal, photo: photo, initials: photo == null ? initials(name) : '', size: 92),
          const SizedBox(height: 12),
          _fit(Text(name.toUpperCase(), style: studioNum(30, royal.text))),
          const SizedBox(height: 14),
          if (w.rank > 0) ...[
            _fit(FoilText('#${w.rank}', theme: royal, size: 64)),
            Text(st('wrapped_rank_line', lang, {'n': w.rankOf}), textAlign: TextAlign.center, style: studioText(11, royal.sub, w: FontWeight.w700)),
            const SizedBox(height: 14),
          ],
          Glass(
            theme: royal,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Column(children: [
              Text(st('my_level', lang).toUpperCase(), style: studioCap(royal, size: 7)),
              const SizedBox(height: 4),
              _fit(Text(levelName(level, lang), style: studioNum(26, royal.text))),
            ]),
          ),
          const Spacer(),
          Text(st('wrapped_end', lang), textAlign: TextAlign.center, style: studioText(10, royal.sub, w: FontWeight.w700)),
        ]),
  ];
  if (w.wickets == 0 && w.catches == 0) slides.removeAt(3);
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StoryViewer(title: context.tr('season_wrapped'), slides: slides, fileName: 'gullyscore-wrapped', shareText: context.tr('wrapped_share_text', {'name': name}))),
  );
}

// ---------------------------------------------------------------- Match Story

class _ChanceChart extends StatelessWidget {
  const _ChanceChart({required this.chances, required this.mark, required this.theme});
  final List<int> chances;
  final int? mark; // index to highlight
  final StudioTheme theme;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ChancePainter(chances, mark, theme), size: const Size(double.infinity, 80));
}

class _ChancePainter extends CustomPainter {
  _ChancePainter(this.c, this.mark, this.t);
  final List<int> c;
  final int? mark;
  final StudioTheme t;
  @override
  void paint(Canvas canvas, Size s) {
    if (c.length < 2) return;
    const up = Color(0xFF2BD38A), down = Color(0xFFFF4D4D);
    double x(int i) => i * s.width / (c.length - 1);
    double y(int v) => s.height - v / 100 * s.height;
    final mid = Paint()
      ..color = t.line
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < s.width; dx += 8) {
      canvas.drawLine(Offset(dx, s.height / 2), Offset(dx + 3, s.height / 2), mid);
    }
    final path = Path()..moveTo(x(0), y(c[0]));
    for (var i = 1; i < c.length; i++) {
      path.lineTo(x(i), y(c[i]));
    }
    final fill = Path.from(path)
      ..lineTo(x(c.length - 1), s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [up.withValues(alpha: 0.25), up.withValues(alpha: 0)]).createShader(Offset.zero & s));
    for (var i = 1; i < c.length; i++) {
      canvas.drawLine(
          Offset(x(i - 1), y(c[i - 1])),
          Offset(x(i), y(c[i])),
          Paint()
            ..color = c[i] >= c[i - 1] - 8 ? up : down
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round);
    }
    if (mark != null && mark! < c.length) {
      final o = Offset(x(mark!), y(c[mark!]));
      canvas.drawCircle(o, 5, Paint()..color = down);
      canvas.drawCircle(
          o,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_ChancePainter old) => old.c != c || old.mark != mark;
}

Widget _ballDot(BallLog b, StudioTheme t) {
  final wk = b.isWicket;
  final boundary = b.isFour || b.isSix;
  final label = wk
      ? 'W'
      : b.kind == BallKind.wide
          ? 'wd'
          : b.kind == BallKind.noBall
              ? 'nb'
              : (b.teamRuns == 0 ? '•' : '${b.teamRuns}');
  return Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: wk ? const Color(0xFFFF4D4D) : (boundary ? const Color(0xFF3B82F6) : t.glass),
      border: wk || boundary ? null : Border.all(color: t.line),
      boxShadow: wk ? const [BoxShadow(color: Color(0x66FF4D4D), blurRadius: 12, spreadRadius: 1)] : null,
    ),
    child: Text(label, style: studioNum(15, Colors.white)),
  );
}

Future<void> openMatchStory(BuildContext context, MatchRecord m) {
  final repo = context.repo;
  final st0 = m.state;
  final story = matchStory(st0);
  final a = artTeam(repo, m.teamA), b = artTeam(repo, m.teamB);
  final royal = themeById('royal');
  final midnight = themeById('midnight');
  final emerald = themeById('emerald');
  final holo = themeById('holo');
  final teamName = [repo.teamName(m.teamA), repo.teamName(m.teamB)];
  String scoreOf(int team) {
    final inn = st0.innings.where((i) => i.battingTeam == team).firstOrNull;
    return inn == null ? '-' : '${inn.runs}/${inn.wickets} (${inn.overs})';
  }

  final potm = playerOfMatch(st0);
  final slides = <SlideBuilder>[
    (lang) {
      final d = posterData(repo, m, lang);
      return _Slide(theme: midnight, center: true, children: [
        const Spacer(),
        if (m.title.isNotEmpty) _fit(Text(m.title.toUpperCase(), style: studioCap(midnight, size: 8).copyWith(letterSpacing: 2))),
        const SizedBox(height: 8),
        _fit(FoilText(st('match_story', lang).toUpperCase(), theme: midnight, size: 46)),
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, x) in [(0, a), (1, b)]) ...[
            Expanded(
              child: Column(children: [
                FoilCrest(team: x, theme: midnight, size: 74),
                const SizedBox(height: 8),
                Text(x.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: studioText(11, midnight.text, w: FontWeight.w800)),
                const SizedBox(height: 4),
                _fit(Text(scoreOf(i), style: studioNum(19, d.winner == null || d.winner == i ? midnight.text : midnight.sub))),
              ]),
            ),
            if (i == 0) Padding(padding: const EdgeInsets.only(top: 26), child: FoilText('VS', theme: midnight, size: 22)),
          ],
        ]),
        const SizedBox(height: 22),
        if (d.status.isNotEmpty)
          Glass(
            theme: midnight,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: _fit(Text(d.winner == null ? d.status : '${teamName[d.winner!]} ${d.status}', style: studioText(13, midnight.accent, w: FontWeight.w800))),
          ),
        const Spacer(),
        Text(st('story_tap', lang), style: studioText(10, midnight.sub, w: FontWeight.w700)),
      ]);
    },
    if (story.turning != null)
      (lang) {
        final o = story.turning!;
        final idx = story.chase && o.innings == 1 ? o.over + 1 : null;
        final legal = o.balls.where((x) => x.legal).toList();
        return _Slide(theme: royal, children: [
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0x29FF4D4D), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x66FF4D4D))),
              child: Text('⚡ ${st('turning_point', lang).toUpperCase()}', style: studioText(9, const Color(0xFFFF8080), w: FontWeight.w800, spacing: 1)),
            ),
          ),
          const SizedBox(height: 10),
          _fit(Text(st('over_n', lang, {'n': o.over + 1}).toUpperCase(), style: studioNum(54, royal.text)), align: Alignment.centerLeft),
          _fit(FoilText(st('story_over_line', lang, {'w': o.wickets, 'r': o.runs}).toUpperCase(), theme: royal, size: 30), align: Alignment.centerLeft),
          const SizedBox(height: 12),
          Row(children: [
            FoilPortrait(theme: royal, photo: PhotoStore.file(repo.players[o.bowler]?.photo), initials: initials(repo.playerName(o.bowler)), size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(repo.playerName(o.bowler), maxLines: 1, overflow: TextOverflow.ellipsis, style: studioText(13, royal.text, w: FontWeight.w800)),
                Text(teamName[1 - st0.innings[o.innings].battingTeam], maxLines: 1, overflow: TextOverflow.ellipsis, style: studioText(9.5, royal.sub, w: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final x in o.balls.take(10)) _ballDot(x, royal)]),
          if (legal.isNotEmpty) const SizedBox(height: 14),
          if (story.chase && story.chances.length > 2)
            Glass(
              theme: royal,
              radius: 16,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: _fit(Text(st('win_chance_of', lang, {'t': teamName[st0.innings.length > 1 ? st0.innings[1].battingTeam : 0]}).toUpperCase(), style: studioCap(royal, size: 7)), align: Alignment.centerLeft)),
                  if (o.chanceBefore != null)
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${o.chanceBefore}%', style: studioNum(17, const Color(0xFF2BD38A))),
                      TextSpan(text: ' → ', style: studioNum(17, royal.text)),
                      TextSpan(text: '${o.chanceAfter}%', style: studioNum(17, (o.chanceAfter ?? 0) < (o.chanceBefore ?? 0) ? const Color(0xFFFF8080) : const Color(0xFF2BD38A))),
                    ])),
                ]),
                const SizedBox(height: 8),
                SizedBox(height: 80, child: _ChanceChart(chances: story.chances, mark: idx, theme: royal)),
              ]),
            ),
          const Spacer(),
        ]);
      },
    (lang) {
      final rows = <(String, String, String)>[];
      if (potm != null) rows.add(('🏆', st('player_of_match', lang), repo.playerName(potm)));
      for (final inn in st0.innings) {
        final bats = inn.batters.values.toList()..sort((x, y) => y.runs.compareTo(x.runs));
        if (bats.isNotEmpty && bats.first.runs > 0) {
          rows.add(('🏏', st('top_bat_of', lang, {'t': teamName[inn.battingTeam]}), '${repo.playerName(bats.first.id)} · ${bats.first.runs}${bats.first.out ? '' : '*'} (${bats.first.balls})'));
        }
        final bowls = inn.bowlers.values.toList()..sort((x, y) => y.wickets != x.wickets ? y.wickets.compareTo(x.wickets) : x.runs.compareTo(y.runs));
        if (bowls.isNotEmpty && bowls.first.wickets > 0) {
          rows.add(('🎯', st('top_bowl_of', lang, {'t': teamName[1 - inn.battingTeam]}), '${repo.playerName(bowls.first.id)} · ${bowls.first.wickets}/${bowls.first.runs}'));
        }
      }
      if (story.bestOver != null) {
        final o = story.bestOver!;
        rows.add(('💥', st('biggest_over', lang), st('biggest_over_line', lang, {'r': o.runs, 'n': o.over + 1, 'p': repo.playerName(o.bowler)})));
      }
      return _Slide(theme: emerald, children: [
        const SizedBox(height: 24),
        _fit(FoilText(st('story_stars', lang).toUpperCase(), theme: emerald, size: 40), align: Alignment.centerLeft),
        const SizedBox(height: 14),
        for (final r in rows.take(6)) ...[
          Glass(
            theme: emerald,
            radius: 14,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(children: [
              Text(r.$1, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fit(Text(r.$2.toUpperCase(), maxLines: 1, style: studioCap(emerald, size: 6.8)), align: Alignment.centerLeft),
                  const SizedBox(height: 2),
                  Text(r.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: studioText(11.5, emerald.text, w: FontWeight.w800)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 7),
        ],
        const Spacer(),
      ]);
    },
    (lang) {
      final d = posterData(repo, m, lang);
      return _Slide(theme: holo, center: true, children: [
        const Spacer(),
        FoilCrest(team: d.winner == null ? a : (d.winner == 0 ? a : b), theme: holo, size: 96),
        const SizedBox(height: 16),
        _fit(FoilText((d.status.isEmpty ? st('in_progress', lang) : d.status).toUpperCase(), theme: holo, size: 40)),
        const SizedBox(height: 6),
        if (d.winner != null) _fit(Text(teamName[d.winner!], style: studioText(15, holo.text, w: FontWeight.w800))),
        const SizedBox(height: 16),
        Text(st('story_full_card', lang), textAlign: TextAlign.center, style: studioText(10.5, holo.sub, w: FontWeight.w700, height: 1.5)),
        const Spacer(),
        Text(math.max(0, m.overs) > 0 ? '${m.overs} ${st('overs', lang)} · ${posterDate(m.scheduledAt ?? m.createdAt, lang)}' : '', style: studioText(9, holo.sub, w: FontWeight.w700)),
      ]);
    },
  ];
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StoryViewer(
        title: '${context.tr('match_story')} · ${a.short} vs ${b.short}',
        slides: slides,
        fileName: 'gullyscore-story-${m.id}',
        shareText: context.tr('story_share_text', {'a': teamName[0], 'b': teamName[1]}),
      ),
    ),
  );
}
