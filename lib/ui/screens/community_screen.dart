// Community: "need players", "find an opponent", polls and tournaments
// (with entry fee paid straight to the organiser by UPI). Posting needs a
// Google login. WhatsApp numbers are shown only to people who join.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/social.dart';
import '../widgets/common.dart';
import '../widgets/online_cards.dart';
import 'info_screens.dart';
import 'match_centre_screen.dart';
import 'online.dart';
import 'scoring_sheets.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

const _kinds = ['players', 'opponent', 'poll', 'tournament'];
const _kindIcons = {
  'players': Icons.person_add_alt_1_rounded,
  'opponent': Icons.sports_cricket_rounded,
  'poll': Icons.poll_outlined,
  'tournament': Icons.emoji_events_outlined,
  'general': Icons.chat_bubble_outline_rounded,
};

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String _kind = '';
  List<Post>? _posts;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.sync.enabled || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.sync.social.posts(kind: _kind);
      if (mounted) setState(() => _posts = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(Post p) => setState(() => _posts = [for (final x in _posts ?? const <Post>[]) x.id == p.id ? p : x]);

  Future<void> _compose() async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_to_post'));
      await loginAsPlayer(context);
      if (!sync.loggedIn) return;
    }
    if (!mounted) return;
    final p = await showAppSheet<Post>(context, (ctx) => _Compose(initialKind: _kind.isEmpty ? 'players' : _kind));
    if (p != null && mounted) setState(() => _posts = [p, ...?_posts]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final online = context.sync.enabled;
    return Stack(children: [
      SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.s),
            child: Row(children: [
              Expanded(child: Semantics(header: true, child: Text(context.tr('nav_community'), style: Tx.title(p.text)))),
              IconBtn(icon: Icons.refresh_rounded, tooltip: context.tr('refresh'), onPressed: online ? _load : null),
            ]),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.edge), children: [
              ChoiceChipX(label: context.tr('all'), selected: _kind.isEmpty, onTap: () {
                setState(() => _kind = '');
                _load();
              }),
              for (final k in _kinds) ...[
                const SizedBox(width: Space.s),
                ChoiceChipX(label: context.tr('kind_$k'), icon: _kindIcons[k], selected: _kind == k, onTap: () {
                  setState(() => _kind = k);
                  _load();
                }),
              ],
            ]),
          ),
          Expanded(
            child: !online
                ? ListView(children: [EmptyState(icon: Icons.cloud_off_rounded, title: context.tr('nav_community'), body: context.tr('online_not_set_up'))])
                : RefreshIndicator(
                    color: p.goldText,
                    backgroundColor: p.surface,
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.only(top: Space.m, bottom: 110), children: [
                      if (_posts == null && _error == null)
                        const LoadingList()
                      else if (_posts == null)
                        OnlineError(error: _error!, onRetry: _load)
                      else if (_posts!.isEmpty)
                        EmptyState(
                          icon: Icons.forum_outlined,
                          title: context.tr('no_posts'),
                          body: context.tr('no_posts_body'),
                          actionLabel: context.tr('new_post'),
                          onAction: _compose,
                        )
                      else
                        for (final post in _posts!)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                            child: PostCard(post: post, onChanged: _replace, onRemoved: _load),
                          ),
                    ]),
                  ),
          ),
        ]),
      ),
      if (online)
        Positioned(
          right: Space.edge,
          bottom: Space.l,
          child: GoldButton(label: context.tr('new_post'), icon: Icons.add_rounded, onPressed: _compose),
        ),
    ]);
  }
}

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, required this.onChanged, required this.onRemoved});
  final Post post;
  final ValueChanged<Post> onChanged;
  final VoidCallback onRemoved;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _busy = false;

  Future<void> _do(Future<Post?> Function() f) async {
    final sync = context.sync;
    if (!sync.loggedIn) {
      _snack(context, context.tr('login_needed'));
      await loginAsPlayer(context);
      if (!sync.loggedIn) return;
    }
    setState(() => _busy = true);
    try {
      final p = await f();
      if (p != null) widget.onChanged(p);
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final post = widget.post;
    var note = '';
    if (post.kind == 'tournament' && !post.joined) {
      final ctrl = TextEditingController();
      final v = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('register_team')),
          content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: ctx.tr('your_team_name'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('register'))),
          ],
        ),
      );
      ctrl.dispose();
      if (v == null || v.trim().isEmpty) return;
      note = v.trim();
    }
    if (!mounted) return;
    await _do(() => context.sync.social.join(post.id, join: !post.joined, note: note));
  }

  Future<void> _menu() async {
    final p = Palette.of(context);
    final post = widget.post;
    final choice = await showAppSheet<String>(
      context,
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (post.mine) ...[
          if (post.kind != 'poll') ListTile(leading: const Icon(Icons.people_outline_rounded), title: Text(ctx.tr('who_joined')), onTap: () => Navigator.pop(ctx, 'joins')),
          ListTile(leading: Icon(Icons.delete_outline_rounded, color: p.liveText), title: Text(ctx.tr('delete')), onTap: () => Navigator.pop(ctx, 'delete')),
        ] else
          ListTile(leading: Icon(Icons.flag_outlined, color: p.liveText), title: Text(ctx.tr('report')), onTap: () => Navigator.pop(ctx, 'report')),
        const SizedBox(height: Space.m),
      ]),
    );
    if (!mounted || choice == null) return;
    final social = context.sync.social;
    try {
      if (choice == 'joins') {
        await showAppSheet<void>(context, (ctx) => _Joins(post: post));
      } else if (choice == 'delete') {
        await social.deletePost(post.id);
        widget.onRemoved();
      } else if (choice == 'report') {
        if (!context.sync.loggedIn) {
          _snack(context, context.tr('login_needed'));
          return;
        }
        await social.report('post', post.id);
        if (mounted) _snack(context, context.tr('reported'));
      }
    } catch (e) {
      if (mounted) _snack(context, onlineError(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final post = widget.post;
    final x = post.extra;
    final meta = [
      if (post.place.isNotEmpty) '📍 ${post.place}',
      if ((x['when'] ?? '').toString().isNotEmpty) '🕒 ${x['when']}',
    ].join('   ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 18, backgroundColor: teamColorFor(post.author), child: Text(initials(post.author), style: Tx.label(Colors.white, w: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w800)),
              Text(agoText(context, post.created), style: Tx.label(p.text2, w: FontWeight.w600)),
            ]),
          ),
          Tag(context.tr('kind_${post.kind}'), color: p.goldText),
          IconButton(tooltip: context.tr('more'), icon: Icon(Icons.more_vert_rounded, size: 20, color: p.text2), onPressed: _menu),
        ]),
        const SizedBox(height: Space.s),
        Text(post.body, style: Tx.body(p.text, w: FontWeight.w600).copyWith(height: 1.45)),
        if (meta.isNotEmpty) ...[const SizedBox(height: 6), Text(meta, style: Tx.small(p.text2, w: FontWeight.w600))],
        if (post.kind == 'players' && (x['need'] ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(context.tr('need_n_players', {'n': x['need']}), style: Tx.small(p.goldText, w: FontWeight.w800)),
        ],
        if (post.kind == 'poll') ..._poll(context),
        if (post.kind == 'tournament') ..._tournament(context),
        if (post.kind != 'poll') ...[
          const SizedBox(height: Space.m),
          Row(children: [
            if (!post.mine)
              Expanded(
                child: post.joined
                    ? OutlineBtn(label: context.tr(post.kind == 'tournament' ? 'registered' : 'joined'), icon: Icons.check_rounded, height: 42, onPressed: _busy ? null : _join)
                    : GoldButton(label: context.tr(post.kind == 'tournament' ? 'register_team' : post.kind == 'opponent' ? 'accept_challenge' : 'im_in'), height: 42, onPressed: _busy ? null : _join),
              )
            else
              Expanded(child: Text(context.tr('joined_n', {'n': post.joins}), style: Tx.small(p.text2, w: FontWeight.w700))),
            if (post.contact != null && !post.mine) ...[
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlineBtn(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  height: 42,
                  onPressed: () => openLink(context, 'https://wa.me/${post.contact!.replaceAll(RegExp(r'\D'), '')}?text=${Uri.encodeComponent(context.tr('wa_hello'))}'),
                ),
              ),
            ],
          ]),
          if (!post.joined && !post.mine && post.hasContact)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.tr('wa_after_join'), style: Tx.label(p.text2, w: FontWeight.w600))),
        ],
      ]),
    );
  }

  List<Widget> _poll(BuildContext context) {
    final p = Palette.of(context);
    final post = widget.post;
    final votes = post.votes;
    final total = votes.fold<int>(0, (a, b) => a + b);
    final voted = post.myVote != null;
    return [
      const SizedBox(height: Space.s),
      for (var i = 0; i < post.options.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: p.raised,
            borderRadius: BorderRadius.circular(11),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : () => _do(() => context.sync.social.vote(post.id, i)),
              child: Stack(children: [
                if (voted && total > 0)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (i < votes.length ? votes[i] : 0) / total,
                      child: Container(color: p.gold.withValues(alpha: 0.22)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    if (post.myVote == i) ...[Icon(Icons.check_circle_rounded, size: 16, color: p.goldText), const SizedBox(width: 6)],
                    Expanded(child: Text(post.options[i], style: Tx.small(p.text, w: FontWeight.w700))),
                    if (voted) Text(total == 0 ? '0%' : '${((i < votes.length ? votes[i] : 0) * 100 / total).round()}%', style: Tx.small(p.text, w: FontWeight.w800)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 6),
      Text(voted ? context.tr('votes_n', {'n': total}) : context.tr('tap_to_vote'), style: Tx.label(p.text2, w: FontWeight.w600)),
    ];
  }

  List<Widget> _tournament(BuildContext context) {
    final p = Palette.of(context);
    final post = widget.post;
    final x = post.extra;
    final fee = (x['fee'] as num?)?.toInt() ?? 0;
    final upi = '${x['upi'] ?? ''}';
    return [
      const SizedBox(height: Space.s),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (fee > 0) Tag(context.tr('entry_fee_n', {'n': fee}), color: p.goldText),
        if ((x['teams'] ?? 0) > 0) Tag(context.tr('teams_joined', {'n': post.joins, 'm': x['teams']})),
        if ('${x['lastDate'] ?? ''}'.isNotEmpty) Tag(context.tr('last_date', {'d': x['lastDate']})),
        if ('${x['prize'] ?? ''}'.isNotEmpty) Tag('🏆 ${x['prize']}'),
      ]),
      if (post.joined && fee > 0 && upi.isNotEmpty) ...[
        const SizedBox(height: Space.m),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(post.paid ? context.tr('fee_confirmed') : context.tr('pay_fee_to', {'n': fee}),
                style: Tx.small(post.paid ? p.win : p.text, w: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: SelectableText(upi, style: Tx.body(p.goldText, w: FontWeight.w800))),
              IconButton(
                tooltip: context.tr('copy'),
                icon: Icon(Icons.copy_rounded, size: 18, color: p.text2),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: upi));
                  _snack(context, context.tr('copied'));
                },
              ),
            ]),
            if (!post.paid)
              OutlineBtn(
                label: context.tr('pay_with_upi'),
                icon: Icons.currency_rupee_rounded,
                height: 42,
                onPressed: () => openLink(
                  context,
                  'upi://pay?pa=${Uri.encodeComponent(upi)}&pn=${Uri.encodeComponent(post.author)}&am=$fee&cu=INR&tn=${Uri.encodeComponent(context.tr('entry_fee_note'))}',
                ),
              ),
            const SizedBox(height: 4),
            Text(context.tr('fee_note'), style: Tx.label(p.text2, w: FontWeight.w600)),
          ]),
        ),
      ],
    ];
  }
}

class _Joins extends StatefulWidget {
  const _Joins({required this.post});
  final Post post;

  @override
  State<_Joins> createState() => _JoinsState();
}

class _JoinsState extends State<_Joins> {
  List<JoinRow>? _rows;

  @override
  void initState() {
    super.initState();
    context.sync.social.joins(widget.post.id).then((r) {
      if (mounted) setState(() => _rows = r);
    }, onError: (e) {
      if (mounted) setState(() => _rows = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tournament = widget.post.kind == 'tournament';
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('who_joined'), subtitle: tournament ? context.tr('tick_paid') : null),
        Flexible(
          child: _rows == null
              ? const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
              : _rows!.isEmpty
                  ? Padding(padding: const EdgeInsets.all(Space.xl), child: Text(context.tr('nobody_yet'), textAlign: TextAlign.center, style: Tx.small(p.text2)))
                  : ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: Space.l), children: [
                      for (final r in _rows!)
                        ListTile(
                          title: Text(r.note.isNotEmpty ? r.note : r.name, style: Tx.body(p.text, w: FontWeight.w700)),
                          subtitle: Text(r.note.isNotEmpty ? '${r.name} · ${r.email}' : r.email, style: Tx.small(p.text2)),
                          trailing: tournament
                              ? FilterChip(
                                  label: Text(context.tr(r.paid ? 'paid' : 'not_paid')),
                                  selected: r.paid,
                                  onSelected: (v) async {
                                    setState(() => r.paid = v);
                                    try {
                                      await context.sync.social.setPaid(widget.post.id, r.userId, v);
                                    } catch (_) {
                                      if (mounted) setState(() => r.paid = !v);
                                    }
                                  },
                                )
                              : null,
                        ),
                    ]),
        ),
      ]),
    );
  }
}

class _Compose extends StatefulWidget {
  const _Compose({required this.initialKind});
  final String initialKind;

  @override
  State<_Compose> createState() => _ComposeState();
}

class _ComposeState extends State<_Compose> {
  late String _kind = widget.initialKind;
  final _body = TextEditingController();
  final _place = TextEditingController();
  final _when = TextEditingController();
  final _contact = TextEditingController();
  final _fee = TextEditingController();
  final _upi = TextEditingController();
  final _teams = TextEditingController();
  final _lastDate = TextEditingController();
  final _prize = TextEditingController();
  final _options = [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()];
  int _need = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_body, _place, _when, _contact, _fee, _upi, _teams, _lastDate, _prize, ..._options]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _post() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _error = context.tr('write_something'));
      return;
    }
    final opts = [for (final o in _options) if (o.text.trim().isNotEmpty) o.text.trim()];
    if (_kind == 'poll' && opts.length < 2) {
      setState(() => _error = context.tr('two_options'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final p = await context.sync.social.createPost({
        'kind': _kind,
        'body': body,
        'place': _place.text.trim(),
        'when': _when.text.trim(),
        if (_kind != 'poll') 'contact': _contact.text.trim(),
        if (_kind == 'players') 'need': _need,
        if (_kind == 'poll') 'options': opts,
        if (_kind == 'tournament') ...{
          'fee': int.tryParse(_fee.text.trim()) ?? 0,
          'upi': _upi.text.trim(),
          'teams': int.tryParse(_teams.text.trim()) ?? 0,
          'lastDate': _lastDate.text.trim(),
          'prize': _prize.text.trim(),
        },
      });
      nav.pop(p);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = onlineError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget field(TextEditingController c, String hint, {TextInputType? type, int lines = 1, IconData? icon}) => Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: TextField(
            controller: c,
            keyboardType: type,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 2,
            textCapitalization: type == null ? TextCapitalization.sentences : TextCapitalization.none,
            decoration: InputDecoration(hintText: hint, prefixIcon: icon == null ? null : Icon(icon, size: 20)),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('new_post')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in _kinds) ChoiceChipX(label: context.tr('kind_$k'), icon: _kindIcons[k], selected: _kind == k, onTap: () => setState(() => _kind = k)),
        ]),
        field(_body, context.tr('hint_$_kind'), lines: 3),
        if (_kind == 'players')
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Row(children: [
              Expanded(child: Text(context.tr('how_many_players'), style: Tx.small(p.text2, w: FontWeight.w700))),
              IconBtn(icon: Icons.remove_rounded, tooltip: '-', onPressed: _need > 1 ? () => setState(() => _need--) : null),
              SizedBox(width: 40, child: Text('$_need', textAlign: TextAlign.center, style: Tx.score(22, p.text, w: FontWeight.w800))),
              IconBtn(icon: Icons.add_rounded, tooltip: '+', onPressed: _need < 11 ? () => setState(() => _need++) : null),
            ]),
          ),
        if (_kind == 'poll')
          for (var i = 0; i < _options.length; i++) field(_options[i], context.tr('option_n', {'n': i + 1})),
        if (_kind == 'tournament') ...[
          field(_fee, context.tr('entry_fee_hint'), type: TextInputType.number, icon: Icons.currency_rupee_rounded),
          field(_upi, context.tr('upi_hint'), type: TextInputType.emailAddress, icon: Icons.account_balance_wallet_outlined),
          field(_teams, context.tr('max_teams_hint'), type: TextInputType.number, icon: Icons.groups_outlined),
          field(_lastDate, context.tr('last_date_hint'), icon: Icons.event_outlined),
          field(_prize, context.tr('prize_hint'), icon: Icons.emoji_events_outlined),
        ],
        field(_place, context.tr('place_hint'), icon: Icons.place_outlined),
        field(_when, context.tr('when_hint'), icon: Icons.schedule_rounded),
        if (_kind != 'poll') ...[
          field(_contact, context.tr('whatsapp_hint'), type: TextInputType.phone, icon: Icons.chat_outlined),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(context.tr('whatsapp_note'), style: Tx.label(p.text2, w: FontWeight.w600))),
        ],
        if (_error != null) ...[const SizedBox(height: Space.s), Text(_error!, style: Tx.small(p.liveText, w: FontWeight.w700))],
        const SizedBox(height: Space.m),
        GoldButton(label: context.tr('post'), icon: Icons.send_rounded, onPressed: _busy ? null : _post),
        const SizedBox(height: Space.s),
        Text(context.tr('post_rules'), textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
      ]),
    );
  }
}
