// The share pictures themselves: player card, match posters, face-off and
// certificate. Each is drawn 360 points wide in any StudioTheme.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'themes.dart';

// ---------------------------------------------------------------- shared bits

class ArtTeam {
  const ArtTeam({required this.name, required this.short, required this.color, this.logo});
  final String name;
  final String short;
  final Color color;
  final File? logo; // only on this phone; the picture is made here
}

/// Round team badge with a foil ring (logo when there is one).
class FoilCrest extends StatelessWidget {
  const FoilCrest({super.key, required this.team, required this.theme, this.size = 78});
  final ArtTeam team;
  final StudioTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.035),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: theme.foil),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: ClipOval(
        child: team.logo != null
            ? Image.file(team.logo!, fit: BoxFit.cover, errorBuilder: (c, e, s) => _letters())
            : _letters(),
      ),
    );
  }

  Widget _letters() => DecoratedBox(
        decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(-0.4, -0.5), radius: 1.3, colors: [team.color, const Color(0xFF0B1220)])),
        child: Center(child: Text(team.short, style: studioNum(size * 0.39, Colors.white))),
      );
}

/// Player face with a foil ring (photo when there is one, else a drawn player).
class FoilPortrait extends StatelessWidget {
  const FoilPortrait({super.key, required this.theme, this.photo, this.initials = '', this.size = 76, this.color = const Color(0xFF3B82F6)});
  final StudioTheme theme;
  final File? photo;
  final String initials;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.035),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: theme.foil),
        boxShadow: [BoxShadow(color: const Color(0x55000000), blurRadius: 24, offset: const Offset(0, 12)), BoxShadow(color: theme.glass, spreadRadius: 6)],
      ),
      child: ClipOval(
        child: photo != null
            ? Image.file(photo!, fit: BoxFit.cover, errorBuilder: (c, e, s) => _drawn())
            : _drawn(),
      ),
    );
  }

  Widget _drawn() => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.15)!, Color.lerp(color, Colors.black, 0.55)!])),
        child: initials.isNotEmpty ? Center(child: Text(initials, style: studioNum(size * 0.36, Colors.white))) : CustomPaint(painter: _PersonPainter()),
      );
}

class _PersonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 110;
    canvas.drawCircle(Offset(55 * u, 44 * u), 20 * u, Paint()..color = const Color(0xFFF1C7A1));
    final hair = Path()
      ..moveTo(33 * u, 40 * u)
      ..cubicTo(35 * u, 26 * u, 46 * u, 19 * u, 56 * u, 19 * u)
      ..cubicTo(66 * u, 19 * u, 77 * u, 26 * u, 78 * u, 40 * u)
      ..cubicTo(71 * u, 34 * u, 41 * u, 34 * u, 33 * u, 40 * u)
      ..close();
    canvas.drawPath(hair, Paint()..color = const Color(0xFF1E293B));
    final body = Path()
      ..moveTo(14 * u, 110 * u)
      ..cubicTo(16 * u, 84 * u, 33 * u, 72 * u, 55 * u, 72 * u)
      ..cubicTo(77 * u, 72 * u, 94 * u, 84 * u, 96 * u, 110 * u)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFF97316));
    final v = Path()
      ..moveTo(48 * u, 74 * u)
      ..lineTo(55 * u, 84 * u)
      ..lineTo(62 * u, 74 * u)
      ..close();
    canvas.drawPath(v, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PersonPainter old) => false;
}

/// Small rounded label at the top right ("SEASON 2026").
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.theme, this.fill});
  final String text;
  final StudioTheme theme;
  final Color? fill;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: fill ?? theme.glass,
          borderRadius: BorderRadius.circular(99),
          border: fill == null ? Border.all(color: theme.line) : null,
        ),
        child: Text(text, maxLines: 1, style: studioText(7.5, fill == null ? theme.sub : Colors.white, w: FontWeight.w800, spacing: 1.3, height: 1)),
      );
}

Widget _fit(Widget w, {Alignment align = Alignment.centerLeft}) => FittedBox(fit: BoxFit.scaleDown, alignment: align, child: w);

/// A box with a big value and a small label underneath.
class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {required this.theme, this.size = 19});
  final String value;
  final String label;
  final StudioTheme theme;
  final double size;
  @override
  Widget build(BuildContext context) => Glass(
        theme: theme,
        radius: 12,
        padding: const EdgeInsets.fromLTRB(9, 8, 6, 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _fit(Text(value, maxLines: 1, style: studioNum(size, theme.text))),
          const SizedBox(height: 4),
          _fit(Text(label.toUpperCase(), maxLines: 1, style: studioCap(theme, size: 6.5))),
        ]),
      );
}

// ---------------------------------------------------------------- player card

class PlayerCardData {
  const PlayerCardData({
    required this.name,
    required this.role,
    required this.team,
    this.photo,
    this.matches = 0,
    this.runs = 0,
    this.average = '-',
    this.strikeRate = '-',
    this.highest = '-',
    this.wickets = 0,
    this.best = '-',
    this.sixes = 0,
    this.form = const [],
    this.potm = 0,
    this.fifties = 0,
    this.levelName = '',
    this.season = '',
  });
  final String name;
  final String role;
  final ArtTeam? team;
  final File? photo;
  final int matches;
  final int runs;
  final String average;
  final String strikeRate;
  final String highest;
  final int wickets;
  final String best;
  final int sixes;
  final List<(int, bool)> form; // last innings, oldest first: runs, not out
  final int potm;
  final int fifties;
  final String levelName; // e.g. "⚡ PRO II"
  final String season;
}

String _n(int v) {
  final s = '$v';
  if (v < 1000) return s;
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class PlayerCardArt extends StatelessWidget {
  const PlayerCardArt({super.key, required this.d, required this.theme, required this.size, required this.lang});
  final PlayerCardData d;
  final StudioTheme theme;
  final StudioSize size;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final tall = size == StudioSize.story;
    final short = size == StudioSize.square;
    final words = d.name.trim().split(RegExp(r'\s+'));
    final first = words.length > 1 ? words.sublist(0, words.length - 1).join(' ') : '';
    final last = words.isEmpty ? '' : words.last;
    final maxForm = d.form.fold<int>(1, (a, f) => math.max(a, f.$1));
    return StudioBackground(
      theme: t,
      child: Padding(
        padding: EdgeInsets.fromLTRB(17, tall ? 26 : 17, 17, tall ? 22 : 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            StudioBrand(theme: t),
            const Spacer(),
            _Pill(d.season.isEmpty ? st('player_card', lang).toUpperCase() : d.season, theme: t),
          ]),
          SizedBox(height: tall ? 26 : (short ? 10 : 14)),
          Row(children: [
            FoilPortrait(theme: t, photo: d.photo, size: short ? 62 : 76, color: d.team?.color ?? const Color(0xFF3B82F6)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.role.isNotEmpty || d.levelName.isNotEmpty)
                  _fit(Text([if (d.role.isNotEmpty) d.role.toUpperCase(), if (d.levelName.isNotEmpty) d.levelName].join(' · '), maxLines: 1, style: studioCap(t, size: 7.5))),
                const SizedBox(height: 4),
                if (first.isNotEmpty) _fit(Text(first.toUpperCase(), maxLines: 1, style: studioNum(short ? 24 : 30, t.text, height: 0.92))),
                _fit(FoilText(last.toUpperCase(), theme: t, size: short ? 24 : 30, height: 0.98)),
                if (d.team != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
                    decoration: BoxDecoration(color: t.glass, borderRadius: BorderRadius.circular(99), border: Border.all(color: t.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(color: d.team!.color, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(d.team!.short, style: studioText(5.5, Colors.white, w: FontWeight.w800, height: 1)),
                      ),
                      const SizedBox(width: 5),
                      Flexible(child: Text(d.team!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: studioText(8.5, t.text, w: FontWeight.w800, height: 1.1))),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
          SizedBox(height: tall ? 24 : (short ? 10 : 13)),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                flex: 21,
                child: Glass(
                  theme: t,
                  radius: 14,
                  padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(st('runs', lang).toUpperCase(), style: studioCap(t, size: 7)),
                    const SizedBox(height: 3),
                    _fit(FoilText(_n(d.runs), theme: t, size: short ? 38 : 48, height: 0.9)),
                    const Spacer(),
                    _fit(Text(st('sr_short', lang, {'v': d.strikeRate}), maxLines: 1, style: studioText(8, t.sub, w: FontWeight.w700))),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 20,
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _Stat('${d.matches}', st('matches', lang), theme: t)),
                    const SizedBox(width: 6),
                    Expanded(child: _Stat(d.average, st('average', lang), theme: t)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _Stat(d.highest, st('highest', lang), theme: t)),
                    const SizedBox(width: 6),
                    Expanded(child: _Stat('${d.wickets}', st('wickets', lang), theme: t)),
                  ]),
                ]),
              ),
            ]),
          ),
          if (!short) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _Stat(d.best, st('best_bowling', lang), theme: t)),
              const SizedBox(width: 6),
              Expanded(child: _Stat('${d.sixes}', st('sixes', lang), theme: t)),
              const SizedBox(width: 6),
              Expanded(child: _Stat('${d.fifties}', st('fifties', lang), theme: t)),
            ]),
          ],
          if (!short && d.form.isNotEmpty) ...[
            SizedBox(height: tall ? 22 : 10),
            Text(st('last_innings_n', lang, {'n': d.form.length}).toUpperCase(), style: studioCap(t, size: 7)),
            const SizedBox(height: 4),
            SizedBox(
              height: tall ? 70 : 44,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (i, f) in d.form.indexed) ...[
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      _fit(Text('${f.$1}${f.$2 ? '*' : ''}', style: studioNum(10, t.text)), align: Alignment.center),
                      const SizedBox(height: 3),
                      Container(
                        height: math.max(4.0, f.$1 / maxForm * (tall ? 46 : 26)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: f.$1 >= 50 || f.$1 == maxForm ? LinearGradient(colors: t.foil) : null,
                          color: f.$1 >= 50 || f.$1 == maxForm ? null : t.line,
                        ),
                      ),
                    ]),
                  ),
                  if (i < d.form.length - 1) const SizedBox(width: 5),
                ],
              ]),
            ),
          ],
          const Spacer(),
          Glass(
            theme: t,
            radius: 13,
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _fit(Text(
                      [if (d.potm > 0) '🏆 ${st('potm_times', lang, {'n': d.potm})}', '🔥 ${st('sixes_n', lang, {'n': d.sixes})}'].join(' · '),
                      maxLines: 1,
                      style: studioText(9, t.text, w: FontWeight.w800))),
                  const SizedBox(height: 2),
                  _fit(Text(st('card_footer', lang), maxLines: 1, style: studioText(7.5, t.sub, w: FontWeight.w700))),
                ]),
              ),
              const SizedBox(width: 8),
              Text('GullyScore', style: studioNum(14, t.accent)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- match posters

enum PosterKind { matchDay, live, result }

class PosterData {
  const PosterData({
    required this.a,
    required this.b,
    this.title = '',
    this.date = '',
    this.time = '',
    this.overs = 0,
    this.ground = '',
    this.sponsor = '',
    this.scoreA = '',
    this.scoreB = '',
    this.oversA = '',
    this.oversB = '',
    this.status = '',
    this.winner,
    this.potmName = '',
    this.potmLine = '',
    this.potmPhoto,
    this.topBat = '',
    this.topBowl = '',
  });
  final ArtTeam a;
  final ArtTeam b;
  final String title; // tournament or "Friendly"
  final String date;
  final String time;
  final int overs;
  final String ground;
  final String sponsor;
  final String scoreA, scoreB, oversA, oversB;
  final String status; // "Need 41 off 21" or "won by 24 runs"
  final int? winner; // 0 a, 1 b
  final String potmName, potmLine;
  final File? potmPhoto;
  final String topBat, topBowl;
}

class PosterArt extends StatelessWidget {
  const PosterArt({super.key, required this.d, required this.kind, required this.theme, required this.size, required this.lang});
  final PosterData d;
  final PosterKind kind;
  final StudioTheme theme;
  final StudioSize size;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final tall = size == StudioSize.story;
    final short = size == StudioSize.square;
    final head = switch (kind) {
      PosterKind.matchDay => st('poster_match_day', lang),
      PosterKind.live => st('poster_live', lang),
      PosterKind.result => st('poster_result', lang),
    };
    Widget team(ArtTeam x, int i) => Expanded(
          child: Column(children: [
            FoilCrest(team: x, theme: t, size: short ? 62 : (tall ? 92 : 78)),
            const SizedBox(height: 7),
            Text(x.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: studioText(10.5, t.text, w: FontWeight.w800, height: 1.2)),
            if (kind != PosterKind.matchDay && (i == 0 ? d.scoreA : d.scoreB).isNotEmpty) ...[
              const SizedBox(height: 5),
              _fit(
                  Text.rich(TextSpan(children: [
                    TextSpan(text: i == 0 ? d.scoreA : d.scoreB, style: studioNum(26, d.winner == null || d.winner == i ? t.text : t.sub)),
                    TextSpan(text: '  ${i == 0 ? d.oversA : d.oversB}', style: studioText(9, t.sub, w: FontWeight.w700)),
                  ])),
                  align: Alignment.center),
            ],
          ]),
        );
    Widget cell(String label, String value) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Column(children: [
              Text(label.toUpperCase(), maxLines: 1, style: studioCap(t, size: 6.5)),
              const SizedBox(height: 3),
              _fit(Text(value, maxLines: 1, style: studioNum(16, t.text)), align: Alignment.center),
            ]),
          ),
        );
    final info = Container(
      decoration: BoxDecoration(color: t.glass, borderRadius: BorderRadius.circular(13), border: Border.all(color: t.line)),
      child: IntrinsicHeight(
        child: Row(children: [
          cell(st('date', lang), d.date),
          VerticalDivider(width: 1, color: t.line),
          cell(st('time', lang), d.time),
          VerticalDivider(width: 1, color: t.line),
          cell(st('overs', lang), '${d.overs}'),
        ]),
      ),
    );
    final resultBox = d.potmName.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.24), t.accent.withValues(alpha: 0.05)]),
              border: Border.all(color: t.accent.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              FoilPortrait(theme: t, photo: d.potmPhoto, initials: _initials(d.potmName), size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fit(Text('🏆 ${st('player_of_match', lang).toUpperCase()}', style: studioCap(t, size: 7).copyWith(color: t.accent))),
                  _fit(Text(d.potmName, maxLines: 1, style: studioText(12.5, t.text, w: FontWeight.w800))),
                  if (d.potmLine.isNotEmpty) _fit(Text(d.potmLine, maxLines: 1, style: studioText(9, t.sub, w: FontWeight.w700))),
                ]),
              ),
            ]),
          );
    return StudioBackground(
      theme: t,
      child: Stack(children: [
        Positioned(
          left: -10,
          right: -10,
          top: tall ? 210 : 150,
          child: Center(child: FoilText('VS', theme: t, size: 200, opacity: 0.09)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(17, tall ? 26 : 17, 17, tall ? 22 : 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              StudioBrand(theme: t),
              const Spacer(),
              if (kind == PosterKind.result)
                _Pill(st('result', lang).toUpperCase(), theme: t)
              else
                _Pill('● ${st('live_on_app', lang).toUpperCase()}', theme: t, fill: const Color(0xFFFF3B5C)),
            ]),
            const Spacer(),
            if (d.title.isNotEmpty)
              _fit(Text(d.title.toUpperCase(), maxLines: 1, style: studioCap(t, size: 7.5).copyWith(letterSpacing: 2.2)), align: Alignment.center),
            const SizedBox(height: 4),
            _fit(FoilText(kind == PosterKind.result && d.status.isNotEmpty ? d.status.toUpperCase() : head, theme: t, size: short ? 40 : 52, letterSpacing: 1.5), align: Alignment.center),
            if (kind == PosterKind.live && d.status.isNotEmpty) ...[
              const SizedBox(height: 4),
              _fit(Text(d.status, style: studioText(12, t.text, w: FontWeight.w800)), align: Alignment.center),
            ],
            SizedBox(height: tall ? 30 : (short ? 10 : 18)),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              team(d.a, 0),
              Padding(padding: EdgeInsets.only(top: short ? 20 : 28), child: FoilText('VS', theme: t, size: 24)),
              team(d.b, 1),
            ]),
            SizedBox(height: tall ? 30 : (short ? 10 : 16)),
            if (kind == PosterKind.matchDay) ...[
              info,
              const SizedBox(height: 9),
              if (d.ground.isNotEmpty) _fit(Text('📍 ${d.ground}', maxLines: 1, style: studioText(10, t.text, w: FontWeight.w800)), align: Alignment.center),
            ] else if (kind == PosterKind.result && resultBox != null && !short) ...[
              resultBox,
              if (d.topBat.isNotEmpty || d.topBowl.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  if (d.topBat.isNotEmpty) Expanded(child: _Stat(d.topBat, st('top_bat', lang), theme: t, size: 12)),
                  if (d.topBat.isNotEmpty && d.topBowl.isNotEmpty) const SizedBox(width: 6),
                  if (d.topBowl.isNotEmpty) Expanded(child: _Stat(d.topBowl, st('top_bowl', lang), theme: t, size: 12)),
                ]),
              ],
            ] else if (d.ground.isNotEmpty)
              _fit(Text('📍 ${d.ground}', maxLines: 1, style: studioText(10, t.text, w: FontWeight.w800)), align: Alignment.center),
            const Spacer(),
            if (kind == PosterKind.matchDay && !short) ...[
              _fit(Text(st('poster_cheer', lang), style: studioText(9, t.sub, w: FontWeight.w800)), align: Alignment.center),
              const SizedBox(height: 7),
            ],
            Glass(
              theme: t,
              radius: 13,
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (d.sponsor.isNotEmpty) ...[
                      Text(st('powered_by', lang).toUpperCase(), style: studioCap(t, size: 6.5)),
                      _fit(Text(d.sponsor, maxLines: 1, style: studioText(11, t.text, w: FontWeight.w800))),
                    ] else
                      _fit(Text(st('poster_footer', lang), maxLines: 1, style: studioText(9.5, t.text, w: FontWeight.w800))),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('GullyScore', style: studioNum(14, t.accent)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  if (w.length == 1) return w.first.substring(0, math.min(2, w.first.length)).toUpperCase();
  return (w.first[0] + w.last[0]).toUpperCase();
}

// ---------------------------------------------------------------- face-off (player comparison)

class FaceOffSide {
  const FaceOffSide({required this.name, required this.team, this.photo, required this.values});
  final String name;
  final String team;
  final File? photo;
  final List<num> values; // same order as FaceOffArt.labels
}

class FaceOffArt extends StatelessWidget {
  const FaceOffArt({super.key, required this.a, required this.b, required this.labels, required this.texts, required this.theme, required this.size, required this.lang, this.lowerIsBetter = const {}});
  final FaceOffSide a;
  final FaceOffSide b;
  final List<String> labels;
  final List<(String, String)> texts; // shown values (e.g. "96*")
  final Set<int> lowerIsBetter; // e.g. economy
  final StudioTheme theme;
  final StudioSize size;
  final String lang;

  static const _teal = [Color(0xFF5EEAD4), Color(0xFF0EA5E9)];

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final tall = size == StudioSize.story;
    final short = size == StudioSize.square;
    var wa = 0, wb = 0;
    final rows = <Widget>[];
    final count = short ? math.min(4, labels.length) : labels.length;
    for (var i = 0; i < count; i++) {
      final va = a.values[i].toDouble(), vb = b.values[i].toDouble();
      final low = lowerIsBetter.contains(i);
      final aWins = va != vb && ((va > vb) != low);
      final bWins = va != vb && !aWins;
      if (aWins) wa++;
      if (bWins) wb++;
      final tot = va.abs() + vb.abs();
      final pa = tot == 0 ? 0.5 : (low ? vb.abs() / tot : va.abs() / tot);
      rows.add(Padding(
        padding: EdgeInsets.only(top: tall ? 13 : 8),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(texts[i].$1, style: studioNum(18, aWins ? t.accent : t.text.withValues(alpha: 0.75))),
            Expanded(child: _fit(Text(labels[i].toUpperCase(), maxLines: 1, style: studioCap(t, size: 7)), align: Alignment.center)),
            Text(texts[i].$2, style: studioNum(18, bWins ? _teal.first : t.text.withValues(alpha: 0.75))),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 6,
            child: Row(children: [
              Expanded(
                flex: math.max(1, (pa * 100).round()),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(9), right: Radius.circular(2)),
                    gradient: LinearGradient(colors: aWins ? t.foil : [t.accent.withValues(alpha: 0.25), t.accent.withValues(alpha: 0.25)]),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                flex: math.max(1, 100 - (pa * 100).round()),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(9)),
                    gradient: LinearGradient(colors: bWins ? _teal : [_teal.first.withValues(alpha: 0.25), _teal.first.withValues(alpha: 0.25)]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ));
    }
    Widget side(FaceOffSide s, List<Color> ring) => Expanded(
          child: Column(children: [
            Container(
              width: short ? 54 : 66,
              height: short ? 54 : 66,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: ring), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))]),
              child: ClipOval(
                child: s.photo != null
                    ? Image.file(s.photo!, fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(-0.4, -0.5), radius: 1.4, colors: [ring.last, const Color(0xFF0B1220)])),
                        child: Center(child: Text(_initials(s.name), style: studioNum(22, Colors.white))),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            _fit(Text(s.name.toUpperCase(), maxLines: 1, style: studioNum(17, t.text)), align: Alignment.center),
            if (s.team.isNotEmpty) _fit(Text(s.team, maxLines: 1, style: studioText(8, t.sub, w: FontWeight.w700)), align: Alignment.center),
          ]),
        );
    final verdict = wa == wb ? st('faceoff_tie', lang) : st('faceoff_wins', lang, {'name': (wa > wb ? a : b).name.split(' ').first});
    return StudioBackground(
      theme: t,
      child: Padding(
        padding: EdgeInsets.fromLTRB(17, tall ? 26 : 16, 17, tall ? 22 : 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [StudioBrand(theme: t), const Spacer(), _Pill(st('face_off', lang).toUpperCase(), theme: t)]),
          SizedBox(height: tall ? 28 : 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side(a, t.foil),
            Padding(padding: const EdgeInsets.only(top: 18), child: FoilText('VS', theme: t, size: 28)),
            side(b, _teal),
          ]),
          ...rows,
          const Spacer(),
          Glass(
            theme: t,
            radius: 13,
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
            child: Row(children: [
              FoilText('$wa – $wb', theme: t, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _fit(Text(verdict, maxLines: 1, style: studioText(11, t.text, w: FontWeight.w800))),
                  _fit(Text(st('faceoff_footer', lang), maxLines: 1, style: studioText(8, t.sub, w: FontWeight.w700))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- certificate

class CertificateData {
  const CertificateData({required this.kicker, required this.name, required this.reason, required this.event, required this.date, this.stats = const [], this.number = '', this.seal = '🏆'});
  final String kicker; // e.g. "Player of the Series"
  final String name;
  final String reason; // one or two lines
  final String event; // tournament or match
  final String date;
  final List<(String, String)> stats; // value, label
  final String number;
  final String seal;
}

/// Ivory and gold, like a printed certificate. Drawn 360 × 256 (landscape).
class CertificateArt extends StatelessWidget {
  const CertificateArt({super.key, required this.d, required this.lang});
  final CertificateData d;
  final String lang;

  static const _ink = Color(0xFF1A1408);
  static const _brown = Color(0xFF7A5A1A);
  static const _foil = [Color(0xFF7A4E0E), Color(0xFFD9A441), Color(0xFF6B430B), Color(0xFFC8922F)];
  static const _ivory = StudioTheme(
    id: 'ivory',
    bg: [Color(0xFFFFFDF6), Color(0xFFF5EDDA), Color(0xFFEADCB9)],
    text: _ink,
    sub: _brown,
    foil: _foil,
    glass: Color(0x73FFFFFF),
    line: Color(0x8CC9A04A),
    beam: Color(0x00000000),
    light: true,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -1), radius: 1.6, colors: [Color(0xFFFFFDF6), Color(0xFFF5EDDA), Color(0xFFEADCB9)], stops: [0, 0.7, 1])),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _CertFrame())),
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 18, 36, 16),
          child: Column(children: [
            Row(children: [
              const Spacer(),
              _fit(Text(d.event.toUpperCase(), maxLines: 1, style: studioText(6.5, _brown, w: FontWeight.w800, spacing: 1.6)), align: Alignment.center),
              const Spacer(),
            ]),
            const SizedBox(height: 4),
            FoilText(st('certificate', lang).toUpperCase(), theme: _ivory, size: 27, letterSpacing: 3),
            Text(d.kicker.toUpperCase(), maxLines: 1, style: studioText(7, _brown, w: FontWeight.w800, spacing: 2.4)),
            const SizedBox(height: 6),
            Text(st('presented_to', lang), style: studioText(7, const Color(0xFF6B5A3A), w: FontWeight.w600).copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 2),
            _fit(Text(d.name, maxLines: 1, style: studioText(19, _ink, w: FontWeight.w800, height: 1.15)), align: Alignment.center),
            Container(width: 150, height: 1, margin: const EdgeInsets.only(top: 2), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x00C9A04A), Color(0xFFC9A04A), Color(0x00C9A04A)]))),
            const SizedBox(height: 5),
            Text(d.reason, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: studioText(7.5, const Color(0xFF4A3D24), w: FontWeight.w600, height: 1.4)),
            if (d.stats.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final s in d.stats.take(4))
                  Container(
                    width: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: const Color(0x73FFFFFF), borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0x8CC9A04A))),
                    child: Column(children: [
                      _fit(Text(s.$1, style: studioNum(14, const Color(0xFF6B430B))), align: Alignment.center),
                      _fit(Text(s.$2.toUpperCase(), style: studioText(4.8, _brown, w: FontWeight.w800, spacing: 0.6)), align: Alignment.center),
                    ]),
                  ),
              ]),
            ],
            const Spacer(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(children: [
                  Text('GullyScore', style: studioText(9, const Color(0xFF2A2010), w: FontWeight.w800)),
                  Container(height: 0.6, color: const Color(0xFF8A6A2A), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
                  Text(st('verified_by', lang).toUpperCase(), style: studioText(5, _brown, w: FontWeight.w800, spacing: 0.6)),
                ]),
              ),
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [Color(0xFF8A5A12), Color(0xFFF4D27A), Color(0xFFB8862B), Color(0xFFF6E3A8), Color(0xFF8A5A12)]),
                  boxShadow: [BoxShadow(color: Color(0x597A4E0E), blurRadius: 10, offset: Offset(0, 4))],
                ),
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF3C9), Color(0xFFE2B24A)])),
                  alignment: Alignment.center,
                  child: Text(d.seal, style: const TextStyle(fontSize: 17)),
                ),
              ),
              Expanded(
                child: Column(children: [
                  Text(d.date, style: studioText(8, const Color(0xFF2A2010), w: FontWeight.w800)),
                  Container(height: 0.6, color: const Color(0xFF8A6A2A), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
                  Text(st('date', lang).toUpperCase(), style: studioText(5, _brown, w: FontWeight.w800, spacing: 0.6)),
                ]),
              ),
            ]),
          ]),
        ),
        if (d.number.isNotEmpty) Positioned(top: 16, right: 30, child: Text('No. ${d.number}', style: studioText(4.8, const Color(0xFF8A7A5A), w: FontWeight.w700))),
      ]),
    );
  }
}

class _CertFrame extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFC9A04A)
      ..strokeWidth = 1.2;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(7, 7, s.width - 14, s.height - 14), const Radius.circular(3)), gold);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(11, 11, s.width - 22, s.height - 22), const Radius.circular(2)), gold..strokeWidth = 0.5);
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = const LinearGradient(colors: [Color(0xFF8A5A12), Color(0xFFF4D27A), Color(0xFFB8862B)]).createShader(Offset.zero & s);
    for (final (x, y, sx, sy) in [(13.0, 13.0, 1.0, 1.0), (s.width - 13, 13.0, -1.0, 1.0), (13.0, s.height - 13, 1.0, -1.0), (s.width - 13, s.height - 13, -1.0, -1.0)]) {
      final p = Path()
        ..moveTo(x, y + 26 * sy)
        ..lineTo(x, y + 8 * sy)
        ..quadraticBezierTo(x, y, x + 8 * sx, y)
        ..lineTo(x + 26 * sx, y);
      canvas.drawPath(p, corner);
      canvas.drawCircle(Offset(x + 7 * sx, y + 7 * sy), 1.6, Paint()..color = const Color(0xFFC9A04A));
    }
  }

  @override
  bool shouldRepaint(_CertFrame old) => false;
}
