// Opens the picture studio for a player, a match, two players or a certificate,
// filling everything in from matches saved on this phone.
import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../data/photos.dart';
import '../data/repository.dart';
import '../scoring/engine.dart';
import '../scoring/insights.dart';
import '../scoring/stats.dart';
import '../scoring/tournament.dart';
import '../ui/screens/scoring_sheets.dart';
import '../ui/widgets/common.dart';
import 'designs.dart';
import 'studio_screen.dart';
import 'themes.dart';

const _daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _daysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
const _monEn = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const _monHi = ['जन', 'फ़र', 'मार्च', 'अप्रै', 'मई', 'जून', 'जुला', 'अग', 'सित', 'अक्टू', 'नव', 'दिस'];

String posterDate(DateTime d, String lang) =>
    lang == 'hi' ? '${_daysHi[d.weekday - 1]} ${d.day} ${_monHi[d.month - 1]}' : '${_daysEn[d.weekday - 1]} ${d.day} ${_monEn[d.month - 1]}';

String posterTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String certDate(DateTime d) => '${d.day} ${_monEn[d.month - 1][0]}${_monEn[d.month - 1].substring(1).toLowerCase()} ${d.year}';

List<StatMatch> statMatchesOf(Repository repo, {String? playerId}) => [
      for (final m in repo.matchList)
        if (playerId == null || m.playersA.contains(playerId) || m.playersB.contains(playerId)) StatMatch(id: m.id, teamIds: [m.teamA, m.teamB], state: m.state),
    ];

ArtTeam artTeam(Repository repo, String teamId) {
  final t = repo.teams[teamId];
  return ArtTeam(name: t?.name ?? '?', short: t?.short ?? '?', color: Palette.team(t?.colorIndex ?? 0), logo: PhotoStore.file(t?.logo));
}

Team? teamOfPlayer(Repository repo, String playerId) => repo.teams.values.where((t) => t.playerIds.contains(playerId) && !t.remote).firstOrNull ??
    repo.teams.values.where((t) => t.playerIds.contains(playerId)).firstOrNull;

String levelName(Level l, String lang) => '${levelEmoji[l.tier]} ${st('tier_${levelTiers[l.tier]}', lang).toUpperCase()}${l.step > 0 ? ' ${'I' * l.step}' : ''}';

// ---------------------------------------------------------------- player card

Future<void> openPlayerCard(BuildContext context, String playerId) {
  final repo = context.repo;
  final pl = repo.players[playerId];
  if (pl == null) return Future.value();
  final list = statMatchesOf(repo, playerId: playerId);
  final s = playerStats(playerId, list);
  final potm = potmCount(playerId, list);
  final level = Level(xpOf(s, potm: potm));
  final form = <(int, bool)>[];
  for (final sm in list) {
    for (final inn in sm.state.innings) {
      final c = inn.batters[playerId];
      if (c != null) form.add((c.runs, !c.out));
    }
  }
  final last = form.take(5).toList().reversed.toList(); // matchList is newest first
  final team = teamOfPlayer(repo, playerId);
  String one(double v) => v == 0 ? '-' : v.toStringAsFixed(1);
  final year = list.isEmpty ? DateTime.now().year : repo.matches[list.first.id]!.updatedAt.year;
  PlayerCardData data(String lang) => PlayerCardData(
        name: pl.name,
        role: pl.role,
        team: team == null ? null : artTeam(repo, team.id),
        photo: PhotoStore.file(pl.photo),
        matches: s.matches,
        runs: s.runs,
        average: s.innings == 0 ? '-' : one(s.average),
        strikeRate: s.balls == 0 ? '-' : one(s.strikeRate),
        highest: s.highestText,
        wickets: s.wickets,
        best: s.best,
        sixes: s.sixes,
        form: last,
        potm: potm,
        fifties: s.fifties + s.hundreds,
        levelName: levelName(level, lang),
        season: st('season_n', lang, {'n': year}).toUpperCase(),
      );
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StudioScreen(
        title: context.tr('player_card'),
        fileName: 'gullyscore-card-${pl.id}',
        shareText: context.tr('card_share_text', {'name': pl.name}),
        teamColors: [if (team != null) Palette.team(team.colorIndex)],
        builder: (t, size, lang) => PlayerCardArt(d: data(lang), theme: t, size: size, lang: lang),
      ),
    ),
  );
}

// ---------------------------------------------------------------- match poster

PosterData posterData(Repository repo, MatchRecord m, String lang) {
  final st0 = m.state;
  String score(int team) {
    final inn = st0.innings.where((i) => i.battingTeam == team).firstOrNull;
    return inn == null ? '' : '${inn.runs}/${inn.wickets}';
  }

  String overs(int team) {
    final inn = st0.innings.where((i) => i.battingTeam == team).firstOrNull;
    return inn == null ? '' : '(${inn.overs})';
  }

  final r = st0.result;
  var status = '';
  if (st0.finished && r != null) {
    if (r.tie) {
      status = st('match_tied', lang);
    } else if (r.noResult) {
      status = st('no_result', lang);
    } else {
      status = st(r.byRuns ? 'won_by_runs' : 'won_by_wkts', lang, {'n': r.margin});
    }
  } else if (st0.innings.length == 2 && st0.current != null && !st0.current!.ended) {
    status = st('need_runs', lang, {'n': st0.runsNeeded ?? 0, 'b': st0.ballsLeft ?? 0});
  }
  final potm = playerOfMatch(st0);
  var potmLine = '';
  if (potm != null) {
    final parts = <String>[];
    for (final inn in st0.innings) {
      final b = inn.batters[potm];
      if (b != null && (b.runs > 0 || b.balls > 0)) parts.add('${b.runs}${b.out ? '' : '*'} (${b.balls})');
      final w = inn.bowlers[potm];
      if (w != null && w.balls > 0) parts.add('${w.wickets}/${w.runs}');
    }
    potmLine = parts.join(' · ');
  }
  String top(bool bat) {
    BatterCard? bb;
    BowlerCard? bw;
    for (final inn in st0.innings) {
      for (final b in inn.batters.values) {
        if (b.id != potm && (bb == null || b.runs > bb.runs)) bb = b;
      }
      for (final w in inn.bowlers.values) {
        if (w.id != potm && (bw == null || w.wickets > bw.wickets || (w.wickets == bw.wickets && w.runs < bw.runs))) bw = w;
      }
    }
    if (bat) return bb == null || bb.runs == 0 ? '' : '${repo.playerName(bb.id).split(' ').first} ${bb.runs}${bb.out ? '' : '*'}';
    return bw == null || bw.wickets == 0 ? '' : '${repo.playerName(bw.id).split(' ').first} ${bw.wickets}/${bw.runs}';
  }

  final when = m.scheduledAt ?? m.createdAt;
  final sponsor = repo.sponsorsOf(m).firstOrNull;
  return PosterData(
    a: artTeam(repo, m.teamA),
    b: artTeam(repo, m.teamB),
    title: m.title,
    date: posterDate(when, lang),
    time: posterTime(when),
    overs: m.overs,
    ground: m.venue,
    sponsor: sponsor == null ? '' : [sponsor.name, if (sponsor.place.isNotEmpty) sponsor.place].join(' · '),
    scoreA: score(0),
    scoreB: score(1),
    oversA: overs(0),
    oversB: overs(1),
    status: status,
    winner: r?.winner,
    potmName: potm == null ? '' : repo.playerName(potm),
    potmLine: potmLine,
    potmPhoto: potm == null ? null : PhotoStore.file(repo.players[potm]?.photo),
    topBat: top(true),
    topBowl: top(false),
  );
}

Future<void> openPoster(BuildContext context, MatchRecord m) {
  final st0 = m.state;
  final start = st0.finished ? PosterKind.result : (st0.innings.isEmpty ? PosterKind.matchDay : PosterKind.live);
  return Navigator.push(context, MaterialPageRoute(builder: (_) => _PosterStudio(m: m, start: start)));
}

class _PosterStudio extends StatefulWidget {
  const _PosterStudio({required this.m, required this.start});
  final MatchRecord m;
  final PosterKind start;
  @override
  State<_PosterStudio> createState() => _PosterStudioState();
}

class _PosterStudioState extends State<_PosterStudio> {
  late PosterKind _kind = widget.start;

  @override
  Widget build(BuildContext context) {
    final repo = context.repo;
    final m = widget.m;
    final a = repo.teams[m.teamA], b = repo.teams[m.teamB];
    return StudioScreen(
      key: ValueKey(_kind),
      title: context.tr('match_poster'),
      fileName: 'gullyscore-poster-${m.id}',
      shareText: context.tr('poster_share_text', {'a': repo.teamName(m.teamA), 'b': repo.teamName(m.teamB)}),
      teamColors: [if (a != null) Palette.team(a.colorIndex), if (b != null) Palette.team(b.colorIndex)],
      top: Segmented<PosterKind>(
        values: PosterKind.values,
        labels: [context.tr('poster_tab_day'), context.tr('poster_tab_live'), context.tr('poster_tab_result')],
        selected: _kind,
        onChanged: (k) => setState(() => _kind = k),
      ),
      builder: (t, size, lang) => PosterArt(d: posterData(repo, m, lang), kind: _kind, theme: t, size: size, lang: lang),
    );
  }
}

// ---------------------------------------------------------------- face-off

Future<void> openFaceOff(BuildContext context, String a, String b) {
  final repo = context.repo;
  final all = statMatchesOf(repo);
  FaceOffSide side(String id) {
    final s = playerStats(id, all);
    final t = teamOfPlayer(repo, id);
    return FaceOffSide(
      name: repo.playerName(id),
      team: t?.name ?? '',
      photo: PhotoStore.file(repo.players[id]?.photo),
      values: [s.runs, s.average, s.strikeRate, s.highest, s.wickets, s.sixes],
    );
  }

  final sa = playerStats(a, all), sb = playerStats(b, all);
  String one(double v) => v.toStringAsFixed(1);
  final texts = [
    ('${sa.runs}', '${sb.runs}'),
    (one(sa.average), one(sb.average)),
    (one(sa.strikeRate), one(sb.strikeRate)),
    (sa.highestText, sb.highestText),
    ('${sa.wickets}', '${sb.wickets}'),
    ('${sa.sixes}', '${sb.sixes}'),
  ];
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StudioScreen(
        title: context.tr('compare_players'),
        fileName: 'gullyscore-faceoff',
        shareText: context.tr('faceoff_share_text', {'a': repo.playerName(a), 'b': repo.playerName(b)}),
        builder: (t, size, lang) => FaceOffArt(
          a: side(a),
          b: side(b),
          labels: [for (final k in ['runs', 'average', 'strike_rate', 'highest', 'wickets', 'sixes']) st(k, lang)],
          texts: texts,
          theme: t,
          size: size,
          lang: lang,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- certificates

Future<void> openCertificate(BuildContext context, {required CertificateData Function(String lang) data, required String fileName, required String shareText}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StudioScreen(
        title: context.tr('certificate'),
        fileName: fileName,
        shareText: shareText,
        sizes: const [StudioSize.wide],
        themes: false,
        builder: (t, size, lang) => CertificateArt(d: data(lang), lang: lang),
      ),
    ),
  );
}

Future<void> openMomCertificate(BuildContext context, MatchRecord m) async {
  final repo = context.repo;
  final st0 = m.state;
  final id = playerOfMatch(st0);
  if (id == null) return;
  var runs = 0, balls = 0, wk = 0, conceded = 0, catches = 0;
  for (final inn in st0.innings) {
    final b = inn.batters[id];
    if (b != null) {
      runs += b.runs;
      balls += b.balls;
    }
    final w = inn.bowlers[id];
    if (w != null) {
      wk += w.wickets;
      conceded += w.runs;
    }
    catches += inn.batters.values.where((x) => x.fielderId == id && x.outKind == OutKind.caught).length;
  }
  final vs = '${repo.teamName(m.teamA)} vs ${repo.teamName(m.teamB)}';
  await openCertificate(
    context,
    fileName: 'certificate-${m.id}',
    shareText: context.tr('mom_share_text', {'name': repo.playerName(id), 'm': vs}),
    data: (lang) => CertificateData(
      kicker: st('player_of_match', lang),
      name: repo.playerName(id),
      reason: st('cert_reason_mom', lang, {'m': vs}),
      event: m.title.isEmpty ? vs : m.title,
      date: certDate(m.updatedAt),
      number: m.id.toUpperCase(),
      stats: [
        if (balls > 0) ('$runs', st('runs', lang)),
        if (balls > 0) ('$balls', st('balls', lang)),
        if (wk > 0 || conceded > 0) ('$wk/$conceded', st('bowling', lang)),
        if (catches > 0) ('$catches', st('catches', lang)),
      ],
    ),
  );
}

Future<void> openChampionCertificate(BuildContext context, Tournament t, String teamId) {
  final repo = context.repo;
  final team = repo.teams[teamId];
  final view = repo.viewOf(t);
  final played = view.statMatches.where((m) => m.teamIds.contains(teamId)).toList();
  var won = 0;
  for (final sm in played) {
    final r = sm.state.result;
    if (r?.winner != null && sm.teamIds[r!.winner!] == teamId) won++;
  }
  return openCertificate(
    context,
    fileName: 'champions-${t.id}',
    shareText: context.tr('champions_share_text', {'team': repo.teamName(teamId), 't': t.name}),
    data: (lang) => CertificateData(
      kicker: st('champions', lang),
      name: repo.teamName(teamId),
      reason: st('cert_reason_champions', lang, {'t': t.name}),
      event: t.name,
      date: certDate(DateTime.now()),
      number: t.id.toUpperCase(),
      seal: '🏆',
      stats: [
        ('${played.length}', st('matches', lang)),
        ('$won', st('won', lang)),
        ('${team?.playerIds.length ?? 0}', st('players', lang)),
      ],
    ),
  );
}

Future<void> openSeriesCertificate(BuildContext context, Tournament t) async {
  final repo = context.repo;
  final view = repo.viewOf(t);
  final table = mvpTable(view.statMatches.map((m) => m.state));
  if (table.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('no_series_player'))));
    return;
  }
  final id = table.first.$1;
  final s = playerStats(id, view.statMatches);
  final potm = view.statMatches.where((m) => playerOfMatch(m.state) == id).length;
  await openCertificate(
    context,
    fileName: 'series-${t.id}',
    shareText: context.tr('series_share_text', {'name': repo.playerName(id), 't': t.name}),
    data: (lang) => CertificateData(
      kicker: st('player_of_series', lang),
      name: repo.playerName(id),
      reason: st('cert_reason_series', lang, {'r': s.runs, 'w': s.wickets, 'n': s.matches}),
      event: t.name,
      date: certDate(DateTime.now()),
      number: '${t.id}-${id.substring(0, id.length < 4 ? id.length : 4)}'.toUpperCase(),
      seal: '⭐',
      stats: [
        ('${s.runs}', st('runs', lang)),
        ('${s.wickets}', st('wickets', lang)),
        if (potm > 0) ('$potm×', st('potm_short', lang)),
        ('${s.matches}', st('matches', lang)),
      ],
    ),
  );
}

/// Pick another player (for Compare and Head to head).
Future<String?> pickOtherPlayer(BuildContext context, String except, {List<(String, int)> suggested = const []}) {
  final repo = context.repo;
  final seen = <String>{};
  final ids = <String>[
    for (final s in suggested)
      if (s.$1 != except && repo.players.containsKey(s.$1) && seen.add(s.$1)) s.$1,
    for (final p in repo.players.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
      if (p.id != except && seen.add(p.id)) p.id,
  ];
  return showAppSheet<String>(context, (ctx) {
    final p = Palette.of(ctx);
    return SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: Space.edge), child: Text(ctx.tr('choose_player'), style: Tx.section(p.text))),
        const SizedBox(height: Space.s),
        Expanded(
          child: ids.isEmpty
              ? Center(child: Text(ctx.tr('no_other_players'), style: Tx.body(p.text2)))
              : ListView.builder(
                  itemCount: ids.length,
                  itemBuilder: (c, i) {
                    final id = ids[i];
                    final faced = suggested.where((s) => s.$1 == id).firstOrNull;
                    return ListTile(
                      minTileHeight: 56,
                      title: Text(repo.playerName(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w700)),
                      subtitle: faced == null ? null : Text(ctx.tr('balls_between', {'n': faced.$2}), style: Tx.label(p.text2)),
                      onTap: () => Navigator.pop(ctx, id),
                    );
                  },
                ),
        ),
      ]),
    );
  });
}
