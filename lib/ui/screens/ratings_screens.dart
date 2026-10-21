// Ratings after a match (fair play, behaviour, on time + comment), and a
// team's ratings page with comments, reactions and replies.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'match_centre_screen.dart';
import 'online.dart';
import 'scoring_sheets.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.size = 16, this.onChanged});
  final double value;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        onChanged == null
            ? Icon(value >= i - 0.25 ? Icons.star_rounded : (value >= i - 0.75 ? Icons.star_half_rounded : Icons.star_outline_rounded),
                size: size, color: value >= i - 0.75 ? p.goldText : p.text2)
            : Semantics(
                button: true,
                label: '$i',
                selected: value >= i,
                child: InkResponse(
                  onTap: () => onChanged!(i),
                  radius: size * 0.8,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(value >= i ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: value >= i ? p.goldText : p.text2),
                  ),
                ),
              ),
    ]);
  }
}

/// On a finished match: "Rate <other team>" for players of this match.
class RateTeamButton extends StatefulWidget {
  const RateTeamButton({super.key, required this.matchId});
  final String matchId;

  @override
  State<RateTeamButton> createState() => _RateTeamButtonState();
}

class _RateTeamButtonState extends State<RateTeamButton> {
  Future<RatingTarget>? _f;

  @override
  Widget build(BuildContext context) {
    final sync = context.sync;
    if (!sync.enabled || !sync.loggedIn) return const SizedBox.shrink();
    _f ??= sync.social.ratingTarget(widget.matchId);
    final p = Palette.of(context);
    return FutureBuilder<RatingTarget>(
      future: _f,
      builder: (context, snap) {
        final t = snap.data;
        if (t == null || t.team == null) return const SizedBox.shrink();
        if (t.rated) {
          return Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: AppCard(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamRatingsScreen(scorerId: t.scorerId, teamId: t.team!.id, teamName: t.team!.name))),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: p.win),
                const SizedBox(width: Space.s),
                Expanded(child: Text(context.tr('you_rated', {'team': t.team!.name}), style: Tx.small(p.text, w: FontWeight.w700))),
                Text(context.tr('see_comments'), style: Tx.small(p.goldText, w: FontWeight.w800)),
              ]),
            ),
          );
        }
        if (!t.canRate) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: OutlineBtn(
            label: context.tr('rate_team', {'team': t.team!.name}),
            icon: Icons.star_outline_rounded,
            height: 48,
            onPressed: () async {
              final ok = await showRateSheet(context, matchId: widget.matchId, team: t.team!.name);
              if (ok == true && mounted) setState(() => _f = sync.social.ratingTarget(widget.matchId));
            },
          ),
        );
      },
    );
  }
}

Future<bool?> showRateSheet(BuildContext context, {required String matchId, required String team}) {
  return showAppSheet<bool>(context, (ctx) => _RateSheet(matchId: matchId, team: team));
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.matchId, required this.team});
  final String matchId;
  final String team;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _fair = 0, _behaviour = 0, _ontime = 0;
  final Set<String> _tags = {};
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_fair == 0 || _behaviour == 0 || _ontime == 0) {
      _snack(context, context.tr('rate_all_three'));
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await context.sync.social.rate(widget.matchId, fair: _fair, behaviour: _behaviour, ontime: _ontime, tags: _tags.toList(), comment: _comment.text.trim());
      if (mounted) _snack(context, context.tr('thanks_rating'));
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        _snack(context, onlineError(context, e));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget q(String title, String sub, int v, ValueChanged<int> on) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Tx.body(p.text, w: FontWeight.w800)),
                Text(sub, style: Tx.label(p.text2, w: FontWeight.w600)),
              ]),
            ),
            Stars(value: v.toDouble(), size: 26, onChanged: on),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('rate_team', {'team': widget.team}), subtitle: context.tr('rate_sub')),
        q(context.tr('fair_play'), context.tr('fair_play_sub'), _fair, (v) => setState(() => _fair = v)),
        Divider(color: p.line, height: 1),
        q(context.tr('behaviour'), context.tr('behaviour_sub'), _behaviour, (v) => setState(() => _behaviour = v)),
        Divider(color: p.line, height: 1),
        q(context.tr('on_time'), context.tr('on_time_sub'), _ontime, (v) => setState(() => _ontime = v)),
        const SizedBox(height: Space.m),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in ratingTags)
            ChoiceChipX(
              label: context.tr('tag_$t'),
              selected: _tags.contains(t),
              onTap: () => setState(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
            ),
        ]),
        const SizedBox(height: Space.m),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: context.tr('comment_optional')),
        ),
        Row(children: [
          Expanded(child: OutlineBtn(label: context.tr('later'), height: 48, onPressed: _busy ? null : () => Navigator.pop(context))),
          const SizedBox(width: Space.s),
          Expanded(flex: 2, child: GoldButton(label: context.tr('submit_rating'), height: 48, onPressed: _busy ? null : _submit)),
        ]),
      ]),
    );
  }
}

class TeamRatingsScreen extends StatefulWidget {
  const TeamRatingsScreen({super.key, required this.scorerId, required this.teamId, required this.teamName});
  final String scorerId;
  final String teamId;
  final String teamName;

  @override
  State<TeamRatingsScreen> createState() => _TeamRatingsScreenState();
}

class _TeamRatingsScreenState extends State<TeamRatingsScreen> {
  String _sort = 'new';
  TeamRatings? _data;
  Object? _error;
  final Map<String, List<Comment>> _allReplies = {}; // opened threads
  final Map<String, Comment> _patched = {}; // comments updated after a reaction
  Comment? _replyTo;
  String? _replyRoot;
  final _reply = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.sync.social.teamRatings(widget.scorerId, widget.teamId, sort: _sort);
      if (mounted) {
        setState(() {
          _data = d;
          _patched.clear();
          _allReplies.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _needLogin() {
    if (context.sync.loggedIn) return false;
    _snack(context, context.tr('login_needed'));
    loginAsPlayer(context);
    return true;
  }

  Future<void> _react(Comment c, String? emoji) async {
    if (_needLogin()) return;
    try {
      final n = await context.sync.social.react(c.id, emoji);
      if (mounted) setState(() => _patched[c.id] = Comment({...n.j, 'firstReplies': c.j['firstReplies']}));
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  Future<void> _pickReaction(Comment c) async {
    final p = Palette.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: p.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final e in reactionEmojis)
              InkResponse(
                onTap: () => Navigator.pop(ctx, e),
                child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) await _react(c, picked);
  }

  Future<void> _openReplies(Comment root) async {
    try {
      final r = await context.sync.social.replies(root.id);
      if (mounted) setState(() => _allReplies[root.id] = r);
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  void _startReply(Comment c, String rootId) {
    if (_needLogin()) return;
    setState(() {
      _replyTo = c;
      _replyRoot = rootId;
    });
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final to = _replyTo, root = _replyRoot;
    final text = _reply.text.trim();
    if (to == null || root == null || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await context.sync.social.reply(to.id, text);
      _reply.clear();
      _focus.unfocus();
      setState(() => _replyTo = null);
      await _openReplies(Comment({'id': root}));
      await _load();
      if (mounted) await _openReplies(Comment({'id': root}));
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _menu(Comment c) async {
    final p = Palette.of(context);
    final choice = await showAppSheet<String>(
      context,
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (c.mine)
          ListTile(leading: Icon(Icons.delete_outline_rounded, color: p.liveText), title: Text(ctx.tr('delete')), onTap: () => Navigator.pop(ctx, 'delete'))
        else
          ListTile(leading: Icon(Icons.flag_outlined, color: p.liveText), title: Text(ctx.tr('report')), onTap: () => Navigator.pop(ctx, 'report')),
        const SizedBox(height: Space.m),
      ]),
    );
    if (!mounted || choice == null) return;
    if (_needLogin()) return;
    try {
      if (choice == 'delete') {
        await context.sync.social.deleteComment(c.id);
      } else {
        await context.sync.social.report('comment', c.id);
        if (mounted) _snack(context, context.tr('reported'));
      }
      await _load();
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  Widget _commentTile(Comment c0, String rootId, {bool reply = false}) {
    final p = Palette.of(context);
    final c = _patched[c0.id] ?? c0;
    return Padding(
      padding: EdgeInsets.only(top: reply ? Space.s : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: reply ? 14 : 17,
            backgroundColor: teamColorFor(c.authorTeam.isEmpty ? c.author : c.authorTeam),
            child: Text(initials(c.author), style: Tx.label(Colors.white, w: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(c.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800))),
                if (c.isTeam) ...[const SizedBox(width: 6), Tag(context.tr('team_tag'), color: p.goldText)],
              ]),
              Text([if (c.authorTeam.isNotEmpty) c.authorTeam, agoText(context, c.created)].join(' · '), style: Tx.label(p.text2, w: FontWeight.w600)),
            ]),
          ),
          if (!reply && c.stars > 0) Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Stars(value: c.stars, size: 14))),
          IconButton(
            tooltip: context.tr('more'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.more_vert_rounded, size: 18, color: p.text2),
            onPressed: () => _menu(c),
          ),
        ]),
        Padding(
          padding: EdgeInsets.only(left: reply ? 38 : 0, top: 4),
          child: Text(c.body, style: Tx.body(p.text).copyWith(height: 1.45)),
        ),
        Padding(
          padding: EdgeInsets.only(left: reply ? 38 : 0, top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final r in c.reactions)
              _ReactionChip(emoji: r.$1, n: r.$2, mine: c.myReaction == r.$1, onTap: () => _react(c, r.$1)),
            _ReactionChip(emoji: '😊+', n: 0, mine: false, onTap: () => _pickReaction(c), semantic: context.tr('add_reaction')),
            TextButton(
              onPressed: () => _startReply(c, rootId),
              style: TextButton.styleFrom(foregroundColor: p.text2, minimumSize: const Size(44, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(context.tr('reply'), style: Tx.small(p.text2, w: FontWeight.w800)),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = _data;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(context.tr('team_ratings', {'team': widget.teamName}),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.title(p.text).copyWith(fontSize: 19)),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.goldText,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
                if (d == null && _error == null)
                  const LoadingList(count: 2)
                else if (d == null)
                  OnlineError(error: _error!, onRetry: _load)
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                    child: HeroCard(
                      child: d.count == 0
                          ? Text(context.tr('no_ratings_body'), style: Tx.body(p.text2))
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Text(d.overall!.toStringAsFixed(1), style: Tx.score(52, p.text, w: FontWeight.w900)),
                                const SizedBox(width: Space.m),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Stars(value: d.overall!, size: 16),
                                    const SizedBox(height: 4),
                                    Text(context.tr('ratings_n', {'n': d.count}), style: Tx.label(p.text2)),
                                  ]),
                                ),
                              ]),
                              const SizedBox(height: Space.s),
                              _Bar(label: context.tr('fair_play'), v: d.fair ?? 0),
                              _Bar(label: context.tr('behaviour'), v: d.behaviour ?? 0),
                              _Bar(label: context.tr('on_time'), v: d.ontime ?? 0),
                              if (d.tags.values.any((n) => n > 0)) ...[
                                const SizedBox(height: Space.m),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  for (final e in d.tags.entries)
                                    if (e.value > 0) Tag('${context.tr('tag_${e.key}')} · ${e.value}'),
                                ]),
                              ],
                            ]),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0), children: [
                      ChoiceChipX(label: context.tr('newest'), selected: _sort == 'new', onTap: () {
                        setState(() => _sort = 'new');
                        _load();
                      }),
                      const SizedBox(width: Space.s),
                      ChoiceChipX(label: context.tr('top'), selected: _sort == 'top', onTap: () {
                        setState(() => _sort = 'top');
                        _load();
                      }),
                    ]),
                  ),
                  if (d.comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Space.edge),
                      child: Text(context.tr('no_comments_yet'), textAlign: TextAlign.center, style: Tx.small(p.text2)),
                    ),
                  for (final c in d.comments)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.edge, Space.s, Space.edge, 0),
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _commentTile(c, c.id),
                          if (c.replies > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 18, top: Space.s),
                              padding: const EdgeInsets.only(left: 12),
                              decoration: BoxDecoration(border: Border(left: BorderSide(color: p.line, width: 2))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                for (final r in _allReplies[c.id] ?? c.firstReplies) _commentTile(r, c.id, reply: true),
                                if (_allReplies[c.id] == null && c.replies > c.firstReplies.length)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () => _openReplies(c),
                                      child: Text(context.tr('more_replies', {'n': c.replies - c.firstReplies.length}), style: Tx.small(p.goldText, w: FontWeight.w800)),
                                    ),
                                  ),
                              ]),
                            ),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ),
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(color: p.nav, border: Border(top: BorderSide(color: p.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(context.tr('replying_to', {'name': _replyTo!.author}), style: Tx.label(p.text2, w: FontWeight.w700))),
                  InkWell(onTap: () => setState(() => _replyTo = null), child: Icon(Icons.close_rounded, size: 18, color: p.text2)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      focusNode: _focus,
                      maxLength: 600,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: context.tr('write_reply'), counterText: ''),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  IconBtn(icon: Icons.send_rounded, tooltip: context.tr('send'), highlight: true, onPressed: _sending ? null : _send),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.n, required this.mine, required this.onTap, this.semantic});
  final String emoji;
  final int n;
  final bool mine;
  final VoidCallback onTap;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: semantic,
      selected: mine,
      child: Material(
        color: mine ? p.gold.withValues(alpha: 0.14) : p.raised,
        shape: StadiumBorder(side: BorderSide(color: mine ? p.gold : p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(n > 0 ? '$emoji $n' : emoji, style: Tx.small(mine ? p.goldText : p.text, w: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.v});
  final String label;
  final double v;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.label(p.text2, w: FontWeight.w700))),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(value: v / 5, minHeight: 6, backgroundColor: p.raised, color: p.gold),
          ),
        ),
        const SizedBox(width: 8),
        Text(v.toStringAsFixed(1), style: Tx.label(p.text, w: FontWeight.w800)),
      ]),
    );
  }
}
