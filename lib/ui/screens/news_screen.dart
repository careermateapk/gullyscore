// News: match reports written automatically from finished matches.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../scoring/report.dart';
import '../widgets/common.dart';
import 'help.dart';
import 'home_screen.dart';
import 'match_centre_screen.dart';
import 'share_card.dart';

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: context.repo,
      builder: (context, _) {
        final repo = context.repo;
        final lang = AppScope.of(context).settings.lang;
        final items = <(MatchRecord, MatchReport)>[];
        for (final m in repo.matchList) {
          final r = buildReport(m.state, teamA: repo.teamName(m.teamA), teamB: repo.teamName(m.teamB), name: repo.playerName, lang: lang);
          if (r != null) items.add((m, r));
        }
        return SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
              child: Row(children: [
                Expanded(child: Semantics(header: true, child: Text(context.tr('nav_news'), style: Tx.title(p.text)))),
                IconBtn(icon: Icons.help_outline_rounded, tooltip: context.tr('help'), onPressed: () => showHelp(context, 'news')),
              ]),
            ),
            if (items.isEmpty)
              EmptyState(icon: Icons.article_outlined, title: context.tr('no_reports'), body: context.tr('no_reports_body'))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.edge, Space.xs, Space.edge, 0),
                child: _LeadStory(m: items.first.$1, r: items.first.$2),
              ),
              for (final it in items.skip(1))
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
                  child: _StoryRow(m: it.$1, r: it.$2),
                ),
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Text(context.tr('reports_note'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
              ),
            ],
          ]),
        );
      },
    );
  }
}

void _open(BuildContext context, MatchRecord m) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(matchId: m.id)));

class _LeadStory extends StatelessWidget {
  const _LeadStory({required this.m, required this.r});
  final MatchRecord m;
  final MatchReport r;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final st = m.state;
    final winner = st.result?.winner;
    final team = context.repo.teams[winner == 1 ? m.teamB : m.teamA];
    return Pressable(
      onTap: () => _open(context, m),
      semanticLabel: r.headline,
      child: HeroCard(
        glow: Palette.team(team?.colorIndex ?? 0),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Tag(context.tr('match_report'), color: p.goldText, background: p.gold.withValues(alpha: 0.14)),
          const SizedBox(height: Space.m),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(r.headline, style: Tx.title(p.text).copyWith(fontSize: 22, height: 1.25))),
            const SizedBox(width: Space.m),
            Crest(logo: team?.logo, color: Palette.team(team?.colorIndex ?? 0), text: team?.short ?? '', size: 44),
          ]),
          const SizedBox(height: Space.s),
          Text([if (m.title.isNotEmpty) m.title, agoText(context, m.updatedAt)].join(' · '), style: Tx.label(p.text2)),
        ]),
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({required this.m, required this.r});
  final MatchRecord m;
  final MatchReport r;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final winner = m.state.result?.winner;
    final team = context.repo.teams[winner == 1 ? m.teamB : m.teamA];
    return AppCard(
      onTap: () => _open(context, m),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 72,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: [Palette.team(team?.colorIndex ?? 0), Palette.team(team?.colorIndex ?? 0).withValues(alpha: 0.45)]),
          ),
          child: Center(child: Crest(color: Colors.white.withValues(alpha: 0.28), size: 30)),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.headline, maxLines: 3, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(height: 1.3)),
            const SizedBox(height: 4),
            Text('${context.tr('match_report')} · ${agoText(context, m.updatedAt)}', style: Tx.label(p.text2, w: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final repo = context.repo;
    final m = repo.matches[matchId];
    final lang = AppScope.of(context).settings.lang;
    final r = m == null ? null : buildReport(m.state, teamA: repo.teamName(m.teamA), teamB: repo.teamName(m.teamB), name: repo.playerName, lang: lang);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: m == null || r == null
            ? Center(child: EmptyState(icon: Icons.article_outlined, title: context.tr('match_not_found'), body: context.tr('match_not_found_body')))
            : ListView(padding: const EdgeInsets.fromLTRB(20, Space.m, 20, Space.xl), children: [
                Row(children: [
                  IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                  const Spacer(),
                  IconBtn(icon: Icons.ios_share_rounded, tooltip: context.tr('share_score'), onPressed: () => shareMatchCard(context, m)),
                ]),
                const SizedBox(height: Space.l),
                Align(alignment: Alignment.centerLeft, child: Tag([context.tr('match_report'), if (m.title.isNotEmpty) m.title].join(' · '), color: p.goldText, background: p.gold.withValues(alpha: 0.14))),
                const SizedBox(height: Space.m),
                Semantics(header: true, child: Text(r.headline, style: Tx.title(p.text).copyWith(fontSize: 28, height: 1.18))),
                const SizedBox(height: Space.m),
                Row(children: [
                  const AppLogo(size: 22),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(context.tr('auto_report_byline', {'t': agoText(context, m.updatedAt)}), style: Tx.small(p.text2))),
                ]),
                const SizedBox(height: Space.l),
                ResultCard(m: m, st: m.state),
                const SizedBox(height: Space.s),
                Row(children: [
                  Expanded(child: _Kv(label: context.tr('top_score'), value: r.topScore)),
                  const SizedBox(width: Space.s),
                  Expanded(child: _Kv(label: context.tr('best_bowling'), value: r.bestBowling)),
                  const SizedBox(width: Space.s),
                  Expanded(child: _Kv(label: context.tr('sixes'), value: '${r.sixes}')),
                ]),
                const SizedBox(height: Space.l),
                for (final para in r.paragraphs)
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(para, style: Tx.body(p.text).copyWith(fontSize: 16, height: 1.65))),
                const SizedBox(height: Space.s),
                OutlineBtn(
                  label: context.tr('full_scorecard'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: m.id))),
                ),
              ]),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2)),
        Text(value, style: Tx.score(22, p.text, w: FontWeight.w800)),
      ]),
    );
  }
}
