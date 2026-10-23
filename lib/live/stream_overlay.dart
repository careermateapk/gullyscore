// What is drawn on top of the live video: the score bar (6 colour themes)
// and the big graphics (intro, need runs, new batter, four/six/wicket,
// sponsor card, innings summary, replay). Drawn at 640×360 and sent to the
// camera as a picture, so YouTube viewers see it too.
import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../data/repository.dart';
import '../scoring/engine.dart';
import '../scoring/insights.dart';
import '../scoring/stats.dart';
import '../scoring/tournament.dart';
import '../studio/share_entry.dart' show statMatchesOf;
import '../ui/widgets/avatar.dart';

const overlaySize = Size(640, 360);

class StreamTheme {
  const StreamTheme(this.id, this.a, this.aText, this.b, this.bText, this.accent);
  final String id;
  final List<Color> a; // left block (team + score)
  final Color aText;
  final Color b; // the long strip
  final Color bText;
  final Color accent; // need / highlights

  static const all = [
    StreamTheme('gold', [Color(0xFFF4C247), Color(0xFFFFE7A3)], Color(0xFF0B1220), Color(0xF00B1220), Colors.white, Color(0xFFE53935)),
    StreamTheme('neon', [Color(0xFF0B0B0B), Color(0xFF16261C)], Color(0xFF39FF88), Color(0xEB000000), Color(0xFFDDDDDD), Color(0xFF39FF88)),
    StreamTheme('ivory', [Color(0xFFFBF6EA), Color(0xFFF1E6CC)], Color(0xFF7A1F1F), Color(0xF07A1F1F), Color(0xFFFBF6EA), Color(0xFFC9952F)),
    StreamTheme('royal', [Color(0xFF3B5BFF), Color(0xFF1E3A8A)], Colors.white, Color(0xEB0A143C), Colors.white, Color(0xFFFFC233)),
    StreamTheme('sunset', [Color(0xFFFF7A3D), Color(0xFFFF3D77)], Colors.white, Color(0xEB280814), Colors.white, Color(0xFFFFD166)),
    StreamTheme('mint', [Color(0xFF2BD38A), Color(0xFF9BF5C9)], Color(0xFF06260F), Color(0xF00B1220), Colors.white, Color(0xFF2BD38A)),
  ];

  static StreamTheme of(String id) => all.firstWhere((t) => t.id == id, orElse: () => all.first);
}

/// Three-letter team code: "Madhubani XI" → "MAD", "Darbhanga Kings" → "DK".
String teamCode(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !RegExp(r'^(XI|FC|CC)$', caseSensitive: false).hasMatch(w)).toList();
  if (words.isEmpty) return name.length <= 3 ? name.toUpperCase() : name.substring(0, 3).toUpperCase();
  if (words.length == 1) {
    final w = words.first;
    return (w.length <= 3 ? w : w.substring(0, 3)).toUpperCase();
  }
  return words.take(3).map((w) => w[0]).join().toUpperCase();
}

String _first(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? name : parts.first;
}

/// Everything the overlay shows, worked out from the match.
class OverlayData {
  OverlayData({
    this.batCode = '',
    this.bowlCode = '',
    this.batName = '',
    this.bowlName = '',
    this.score = '0/0',
    this.overs = '0.0',
    this.strikerId,
    this.striker = '',
    this.strikerScore = '',
    this.nonStriker = '',
    this.nonStrikerScore = '',
    this.bowler = '',
    this.bowlerFigures = '',
    this.lastBalls = const [],
    this.need,
    this.ballsLeft,
    this.winChance,
    this.target,
    this.title = '',
    this.venue = '',
    this.result = '',
    this.inningsNo = 0,
  });

  final String batCode, bowlCode, batName, bowlName, score, overs;
  final String? strikerId;
  final String striker, strikerScore, nonStriker, nonStrikerScore, bowler, bowlerFigures;
  final List<String> lastBalls;
  final int? need, ballsLeft, winChance, target;
  final String title, venue, result;
  final int inningsNo;

  static OverlayData of(Repository repo, MatchState st, {required String teamA, required String teamB, String title = '', String venue = ''}) {
    final names = [repo.teamName(teamA), repo.teamName(teamB)];
    final inn = st.current;
    final bat = st.battingTeamNow;
    String pScore(Innings i, String? id) {
      if (id == null) return '';
      final c = i.batters[id];
      return c == null ? '0 (0)' : '${c.runs}${c.out ? '' : '*'} (${c.balls})';
    }

    String figures(Innings i, String? id) {
      if (id == null) return '';
      final c = i.bowlers[id];
      return c == null ? '0-0-0-0' : '${c.overs}-${c.maidens}-${c.runs}-${c.wickets}';
    }

    final need = st.runsNeeded;
    final left = st.ballsLeft;
    int? chance;
    if (need != null && left != null && inn != null && inn.number == 1 && !st.finished) {
      chance = chaseWinChance(need, left, 10 - inn.wickets);
    }
    final r = st.finished ? st.resultText(names[0], names[1]) : '';
    return OverlayData(
      batCode: teamCode(names[bat]),
      bowlCode: teamCode(names[1 - bat]),
      batName: names[bat],
      bowlName: names[1 - bat],
      score: inn == null ? '0/0' : '${inn.runs}/${inn.wickets}',
      overs: inn?.overs ?? '0.0',
      strikerId: inn?.striker,
      striker: inn?.striker == null ? '' : _first(repo.playerName(inn!.striker!)),
      strikerScore: inn == null ? '' : pScore(inn, inn.striker),
      nonStriker: inn?.nonStriker == null ? '' : _first(repo.playerName(inn!.nonStriker!)),
      nonStrikerScore: inn == null ? '' : pScore(inn, inn.nonStriker),
      bowler: inn?.bowler == null ? '' : _first(repo.playerName(inn!.bowler!)),
      bowlerFigures: inn == null ? '' : figures(inn, inn.bowler),
      lastBalls: inn == null ? const [] : [for (final b in inn.balls.reversed.take(6).toList().reversed) b.isWicket ? 'W' : b.label],
      need: (inn != null && inn.number == 1) ? need : null,
      ballsLeft: left,
      winChance: chance,
      target: st.target,
      title: title,
      venue: venue,
      result: r,
      inningsNo: inn?.number ?? 0,
    );
  }
}

enum Graphic { none, intro, need, batter, boundary, sponsor, summary, replay }

class OverlayState {
  const OverlayState({
    required this.theme,
    required this.data,
    this.graphic = Graphic.none,
    this.showBar = true,
    this.boundary = '',
    this.batterId,
    this.sponsor,
    this.cornerSponsor,
    this.summary = const [],
  });
  final StreamTheme theme;
  final OverlayData data;
  final Graphic graphic;
  final bool showBar;
  final String boundary; // SIX! / FOUR! / WICKET!
  final String? batterId;
  final Sponsor? sponsor;
  final Sponsor? cornerSponsor; // small logo in the corner all match
  final List<(String, String)> summary; // innings summary lines
}

const _saira = 'Saira';

TextStyle _t(double size, Color c, {FontWeight w = FontWeight.w800, String? family}) =>
    TextStyle(fontSize: size, color: c, fontWeight: w, fontFamily: family ?? 'Hanken', fontFamilyFallback: const ['NotoDeva'], height: 1.1);

class StreamOverlay extends StatelessWidget {
  const StreamOverlay({super.key, required this.state});
  final OverlayState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return MediaQuery.withNoTextScaling(
      child: SizedBox.fromSize(
        size: overlaySize,
        child: Stack(children: [
          // brand, top right
          Positioned(
            right: 10,
            top: 10,
            child: _chip(const Color(0xB30B1220), Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('GullyScore LIVE', style: _t(9.5, Colors.white)),
            ])),
          ),
          if (s.cornerSponsor != null && s.graphic != Graphic.sponsor)
            Positioned(left: 10, top: 10, child: _chip(const Color(0xF2FFFFFF), Text(s.cornerSponsor!.name, style: _t(9.5, const Color(0xFF7B1E14))))),
          if (s.graphic == Graphic.replay)
            Positioned(
              left: 10,
              top: s.cornerSponsor == null ? 10 : 34,
              child: Transform(
                transform: Matrix4.skewX(-0.18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF7A3D)])),
                  child: Text('⟲ REPLAY', style: _t(18, Colors.white, family: _saira)),
                ),
              ),
            ),
          if (s.graphic != Graphic.none && s.graphic != Graphic.replay) Positioned.fill(child: _graphic(context)),
          if (s.showBar && s.graphic != Graphic.replay && s.graphic != Graphic.intro && s.graphic != Graphic.summary)
            Positioned(left: 10, right: 10, bottom: 10, height: 34, child: _bar()),
        ]),
      ),
    );
  }

  Widget _chip(Color bg, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: child,
      );

  Widget _bar() {
    final t = state.theme;
    final d = state.data;
    Widget ball(String b) {
      final c = b == 'W'
          ? const Color(0xFFE53935)
          : b == '6'
              ? const Color(0xFFA855F7)
              : b == '4'
                  ? const Color(0xFF2B7BD3)
                  : Colors.white.withValues(alpha: 0.16);
      return Container(
        margin: const EdgeInsets.only(left: 3),
        constraints: const BoxConstraints(minWidth: 17),
        height: 17,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
        child: Text(b, style: _t(8.5, Colors.white)),
      );
    }

    final needText = d.need != null && d.ballsLeft != null && d.need! > 0 ? 'NEED ${d.need} · ${d.ballsLeft}' : (d.target != null && d.inningsNo == 1 ? 'TARGET ${d.target}' : '');
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(gradient: LinearGradient(colors: t.a)),
          alignment: Alignment.center,
          child: Text('${d.batCode} ${d.score}', style: _t(15, t.aText, family: _saira)),
        ),
        Expanded(
          child: Container(
            color: t.b,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(children: [
              Text('${d.overs} ov', style: _t(10.5, t.bText)),
              const SizedBox(width: 10),
              if (d.striker.isNotEmpty)
                Flexible(child: Text('${d.striker} ${d.strikerScore}', maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: _t(10.5, t.bText))),
              if (d.nonStriker.isNotEmpty) ...[
                const SizedBox(width: 9),
                Flexible(
                    child: Text('${d.nonStriker} ${d.nonStrikerScore}',
                        maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: _t(10.5, t.bText.withValues(alpha: 0.75), w: FontWeight.w700))),
              ],
              if (d.bowler.isNotEmpty) ...[
                const SizedBox(width: 9),
                Flexible(
                    child: Text('${d.bowler} ${d.bowlerFigures}',
                        maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: _t(10, t.bText.withValues(alpha: 0.7), w: FontWeight.w700))),
              ],
              const Spacer(),
              for (final b in d.lastBalls) ball(b),
            ]),
          ),
        ),
        if (needText.isNotEmpty)
          Container(
            color: t.accent,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(needText, style: _t(10, t.accent.computeLuminance() > 0.5 ? const Color(0xFF0B1220) : Colors.white)),
          ),
      ]),
    );
  }

  Widget _graphic(BuildContext context) {
    final s = state;
    final d = s.data;
    final gold = s.theme.a.first;
    switch (s.graphic) {
      case Graphic.intro:
        return _panel(
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (d.title.isNotEmpty) Text(d.title.toUpperCase(), style: _t(11, gold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(d.batName.toUpperCase(), textAlign: TextAlign.right, maxLines: 2, style: _t(28, Colors.white, family: _saira))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('VS', style: _t(20, gold, family: _saira))),
              Flexible(child: Text(d.bowlName.toUpperCase(), maxLines: 2, style: _t(28, Colors.white, family: _saira))),
            ]),
            if (d.venue.isNotEmpty) ...[const SizedBox(height: 8), Text('📍 ${d.venue}', style: _t(11, Colors.white70, w: FontWeight.w700))],
          ]),
        );
      case Graphic.need:
        Widget num(String top, String n, String bottom) => Column(mainAxisSize: MainAxisSize.min, children: [
              Text(top, style: _t(10, Colors.white70)),
              Text(n, style: _t(78, gold, family: _saira)),
              Text(bottom, style: _t(11, Colors.white)),
            ]);
        return _panel(
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              num('${d.batCode} NEED', '${d.need ?? 0}', 'RUNS'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 26), child: Text('FROM', style: _t(18, Colors.white54, family: _saira))),
              num('ONLY', '${d.ballsLeft ?? 0}', 'BALLS'),
            ]),
            if (d.winChance != null) Text('Win chance · ${d.batCode} ${d.winChance}% — ${d.bowlCode} ${100 - d.winChance!}%', style: _t(11, gold)),
          ]),
          wide: true,
        );
      case Graphic.batter:
        return Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 0, 56), child: _BatterCard(id: s.batterId, theme: s.theme)));
      case Graphic.boundary:
        final c = s.boundary.startsWith('W') ? const Color(0xFFE53935) : (s.boundary.startsWith('S') ? const Color(0xFFA855F7) : const Color(0xFF2B7BD3));
        return Center(
          child: Transform.rotate(
            angle: -0.06,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.75)]),
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 30)],
              ),
              child: Text(s.boundary, style: _t(54, Colors.white, family: _saira)),
            ),
          ),
        );
      case Graphic.sponsor:
        final sp = s.sponsor;
        if (sp == null) return const SizedBox();
        return Container(
          color: const Color(0xA60B1220),
          alignment: Alignment.center,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFBF6EA), Color(0xFFEFE3C4)]),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('BROUGHT TO YOU BY', style: _t(8.5, const Color(0xFF9A6B2F))),
              const SizedBox(height: 10),
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFFC0392B), Color(0xFF7B1E14)])),
                child: Text(sp.name.isEmpty ? '?' : sp.name[0].toUpperCase(), style: _t(28, Colors.white)),
              ),
              const SizedBox(height: 8),
              Text(sp.name, textAlign: TextAlign.center, maxLines: 2, style: _t(20, const Color(0xFF3A1F0F))),
              if (sp.place.isNotEmpty) Text(sp.place, textAlign: TextAlign.center, maxLines: 2, style: _t(10.5, const Color(0xFF7A5A3A), w: FontWeight.w700)),
              if (sp.phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('📞 ${sp.phone}', style: _t(11.5, const Color(0xFF3A1F0F)))),
            ]),
          ),
        );
      case Graphic.summary:
        return _panel(
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(d.result.isNotEmpty ? d.result.toUpperCase() : '${d.batName.toUpperCase()}  ${d.score}  (${d.overs})',
                textAlign: TextAlign.center, maxLines: 2, style: _t(20, gold, family: _saira)),
            const SizedBox(height: 10),
            for (final (a, b) in s.summary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 40),
                child: Row(children: [
                  Expanded(child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, Colors.white, w: FontWeight.w700))),
                  Text(b, style: _t(12, Colors.white)),
                ]),
              ),
          ]),
          wide: true,
        );
      case Graphic.none:
      case Graphic.replay:
        return const SizedBox();
    }
  }

  Widget _panel(Widget child, {bool wide = false}) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: wide
                ? const [Color(0x260B1220), Color(0xE00B1220), Color(0xE00B1220), Color(0x260B1220)]
                : const [Color(0xCC0B1220), Color(0xCC0B1220)],
            stops: wide ? const [0, 0.25, 0.75, 1] : null,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      );
}

class _BatterCard extends StatelessWidget {
  const _BatterCard({required this.id, required this.theme});
  final String? id;
  final StreamTheme theme;

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    if (id == null) return const SizedBox();
    final repo = context.repo;
    final name = repo.playerName(id).toUpperCase();
    final parts = name.split(' ');
    final s = playerStats(id, statMatchesOf(repo, playerId: id));
    Widget stat(String v, String k) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(9)),
            child: Column(children: [Text(v, style: _t(15, Colors.white)), Text(k, style: _t(7.5, Colors.white60))]),
          ),
        );
    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF21C2540), Color(0xF20E1626)]),
        border: Border.all(color: theme.a.first.withValues(alpha: 0.4)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PlayerAvatar(playerId: id, size: 46, ring: theme.a.first),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NEW BATTER', style: _t(8, theme.a.first)),
              Text(parts.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(18, Colors.white, family: _saira)),
              if (parts.length > 1) Text(parts.sublist(1).join(' '), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(18, theme.a.first, family: _saira)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat('${s.runs}', 'RUNS'),
          stat(s.average.toStringAsFixed(1), 'AVERAGE'),
          stat(s.strikeRate.toStringAsFixed(0), 'STRIKE RATE'),
        ]),
        if (s.sixes > 0 || s.fifties > 0) ...[
          const SizedBox(height: 8),
          Text([if (s.sixes > 0) '💥 ${s.sixes} sixes', if (s.fifties > 0) '⭐ ${s.fifties} fifties', '${s.matches} matches'].join(' · '),
              style: _t(9, Colors.white70, w: FontWeight.w700)),
        ],
      ]),
    );
  }
}
