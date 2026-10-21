// Online pieces: follow a match by link, player login (Google + mobile
// number), the "My matches" list, and the scorer's yes/no questions.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/google_auth.dart';
import '../../data/models.dart';
import '../../data/sync.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'match_centre_screen.dart';

Future<String?> _askText(BuildContext context,
    {required String title, required String hint, String? body, bool caps = false, bool phone = false, String initial = '', String? okLabel}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (body != null) ...[Text(body, style: Tx.small(Palette.of(ctx).text2)), const SizedBox(height: Space.m)],
        TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
          keyboardType: phone ? TextInputType.phone : null,
          inputFormatters: phone ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]'))] : null,
          decoration: InputDecoration(hintText: hint, prefixIcon: phone ? const Icon(Icons.phone_android_rounded) : null),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(okLabel ?? ctx.tr('ok'))),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

String _cloudMessage(BuildContext context, Object e) {
  if (e is CloudError && e.offline) return context.tr('needs_internet');
  if (e is CloudError && e.status == 404) return context.tr('not_found_online');
  if (e is CloudError && e.status == 503) return context.tr('login_not_ready');
  if (e is CloudError && e.status == 400) return context.tr('phone_invalid');
  if (e is GoogleLoginError) return context.tr('login_failed');
  return context.tr('online_failed');
}

/// Paste a live link (or code) and open that match.
Future<void> followMatchByLink(BuildContext context) async {
  final text = await _askText(context, title: context.tr('follow_a_match'), hint: context.tr('paste_link'), body: context.tr('follow_body'));
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await openFollowed(context, text);
}

Future<void> openFollowed(BuildContext context, String linkOrId) async {
  final sync = context.sync;
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final id = await sync.follow(linkOrId);
    nav.push(MaterialPageRoute(builder: (_) => MatchCentreScreen(matchId: id)));
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(_cloudMessage(context, e))));
  }
}

void _snack(ScaffoldMessengerState m, String text) => m.showSnackBar(SnackBar(content: Text(text)));

/// Scorer types (or removes) a player's mobile number.
Future<void> editPlayerPhone(BuildContext context, Player pl) async {
  final text = await _askText(
    context,
    title: context.tr('player_mobile_title', {'name': pl.name}),
    hint: '98765 43210',
    body: context.tr('player_mobile_body'),
    phone: true,
    initial: pl.phone,
    okLabel: context.tr('save'),
  );
  if (text == null || !context.mounted) return;
  final clean = cleanPhone(text);
  if (text.trim().isNotEmpty && clean.isEmpty) {
    _snack(ScaffoldMessenger.of(context), context.tr('phone_invalid'));
    return;
  }
  context.repo.updatePlayer(pl, phone: clean);
}

/// "Login with Google", then the player's own mobile number.
Future<void> loginAsPlayer(BuildContext context) async {
  final sync = context.sync;
  final messenger = ScaffoldMessenger.of(context);
  if (!sync.loginAvailable) {
    _snack(messenger, context.tr('login_not_ready'));
    return;
  }
  try {
    await sync.login();
  } on GoogleLoginError catch (e) {
    if (!e.cancelled && context.mounted) _snack(messenger, _cloudMessage(context, e));
    return;
  } catch (e) {
    if (context.mounted) _snack(messenger, _cloudMessage(context, e));
    return;
  }
  if (!context.mounted) return;
  _snack(messenger, context.tr('logged_in_as', {'email': sync.me?.email ?? ''}));
  if (sync.me?.hasPhone != true) await askMyPhone(context);
}

Future<void> askMyPhone(BuildContext context) async {
  final sync = context.sync;
  final text = await _askText(
    context,
    title: context.tr('my_mobile_title'),
    hint: '98765 43210',
    body: context.tr('my_mobile_body'),
    phone: true,
    initial: sync.myPhone,
    okLabel: context.tr('save'),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (cleanPhone(text).isEmpty) {
    _snack(messenger, context.tr('phone_invalid'));
    return;
  }
  try {
    await sync.setMyPhone(text);
  } catch (e) {
    if (context.mounted) _snack(messenger, _cloudMessage(context, e));
  }
}

Future<void> logoutPlayer(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('logout_q')),
      content: Text(ctx.tr('logout_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('logout'))),
      ],
    ),
  );
  if (ok == true && context.mounted) await context.sync.logout();
}

/// "Are you a player?" card, or the logged-in player's matches (on Home).
class MyMatchesSection extends StatefulWidget {
  const MyMatchesSection({super.key});

  @override
  State<MyMatchesSection> createState() => _MyMatchesSectionState();
}

class _MyMatchesSectionState extends State<MyMatchesSection> {
  Future<MeInfo?>? _future;
  bool _busy = false;

  void _reload() => setState(() => _future = context.sync.refreshMe());

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s), child: child);

  Widget _promptCard(BuildContext context, {required IconData icon, required String title, required String body, required String button, required VoidCallback onTap}) {
    final p = Palette.of(context);
    return _pad(AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: p.goldText),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Tx.body(p.text, w: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body, style: Tx.small(p.text2)),
            ]),
          ),
        ]),
        const SizedBox(height: Space.m),
        OutlineBtn(label: button, icon: icon, height: 44, onPressed: _busy ? null : onTap),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (!sync.enabled) return const SizedBox.shrink();
        if (!sync.loggedIn) {
          if (!sync.loginAvailable) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.tr('my_matches')),
            _promptCard(context,
                icon: Icons.login_rounded,
                title: context.tr('are_you_player'),
                body: context.tr('are_you_player_body'),
                button: context.tr('login_google'),
                onTap: () => _run(() => loginAsPlayer(context))),
          ]);
        }
        final me = sync.me;
        if (me == null || !me.hasPhone) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.tr('my_matches')),
            _promptCard(context,
                icon: Icons.phone_android_rounded,
                title: context.tr('add_my_mobile'),
                body: context.tr('add_my_mobile_body'),
                button: context.tr('add_my_mobile'),
                onTap: () => _run(() => askMyPhone(context))),
          ]);
        }
        _future ??= sync.refreshMe();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(context.tr('my_matches'), action: context.tr('refresh'), onAction: _reload),
          FutureBuilder<MeInfo?>(
            future: _future,
            builder: (context, snap) {
              final info = sync.me ?? me;
              if (snap.connectionState != ConnectionState.done && info.profiles.isEmpty && info.matches.isEmpty) {
                return _pad(const Shimmer(child: SkeletonBox(height: 72, radius: Corners.card)));
              }
              final children = <Widget>[];
              if (snap.hasError && info.matches.isEmpty) {
                children.add(_pad(AppCard(
                  onTap: _reload,
                  child: Row(children: [
                    Icon(Icons.cloud_off_rounded, color: p.text2),
                    const SizedBox(width: Space.m),
                    Expanded(child: Text(_cloudMessage(context, snap.error!), style: Tx.small(p.text2))),
                    Text(context.tr('try_again'), style: Tx.small(p.goldText, w: FontWeight.w800)),
                  ]),
                )));
              }
              final waiting = info.profiles.where((x) => x.waiting).toList();
              if (info.profiles.isEmpty && !snap.hasError) {
                children.add(_pad(AppCard(child: Text(context.tr('no_profile_for_number'), style: Tx.small(p.text2)))));
              }
              for (final w in waiting) {
                children.add(_pad(AppCard(
                  child: Row(children: [
                    Icon(Icons.hourglass_top_rounded, color: p.goldText, size: 20),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Text(context.tr('waiting_for_scorer', {'name': w.team.isEmpty ? w.name : '${w.name} · ${w.team}'}),
                          style: Tx.small(p.text2, w: FontWeight.w600)),
                    ),
                  ]),
                )));
              }
              if (info.profiles.any((x) => x.approved) && info.matches.isEmpty) {
                children.add(_pad(AppCard(child: Text(context.tr('no_my_matches'), style: Tx.small(p.text2)))));
              }
              for (final m in info.matches.take(5)) {
                children.add(_pad(AppCard(
                  onTap: () => openFollowed(context, m.id),
                  child: Row(children: [
                    if (!m.finished) ...[LiveBadge(label: context.tr('live')), const SizedBox(width: Space.m)],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${m.summary['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                        Text('${m.summary['status'] ?? ''}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(m.finished ? p.win : p.goldText, w: FontWeight.w700)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.text2),
                  ]),
                )));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
            },
          ),
        ]);
      },
    );
  }
}

/// On a player's profile: Google accounts that logged in with this
/// player's mobile number. The scorer can remove one.
class LinkedAccounts extends StatefulWidget {
  const LinkedAccounts({super.key, required this.playerId});
  final String playerId;

  @override
  State<LinkedAccounts> createState() => _LinkedAccountsState();
}

class _LinkedAccountsState extends State<LinkedAccounts> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.sync.checkClaims();
    });
  }

  Future<void> _remove(Claim c) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('online_failed');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('remove_access_q')),
        content: Text(ctx.tr('remove_access_body', {'email': c.email})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('unlink'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.sync.answerClaim(c, false);
    } catch (_) {
      _snack(messenger, failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final list = sync.claims.where((c) => c.playerId == widget.playerId).toList();
        if (!sync.enabled || list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.tr('linked_accounts'), style: Tx.small(p.text2, w: FontWeight.w700)),
              for (final c in list)
                Row(children: [
                  Icon(Icons.verified_user_outlined, size: 18, color: p.win),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(c.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text, w: FontWeight.w700))),
                  TextButton(onPressed: () => _remove(c), child: Text(context.tr('unlink'))),
                ]),
            ]),
          ),
        );
      },
    );
  }
}

/// Small line that says whether this phone's matches are online.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final (icon, color, text) = switch (sync.state) {
          _ when !sync.shareOnline => (Icons.cloud_off_rounded, p.text2, context.tr('sync_paused')),
          _ when sync.pending.isNotEmpty && sync.state != SyncState.working =>
            (Icons.cloud_upload_outlined, p.goldText, context.tr('sync_waiting', {'n': sync.pending.length})),
          SyncState.working => (Icons.cloud_sync_rounded, p.goldText, context.tr('sync_working')),
          SyncState.offline => (Icons.cloud_off_rounded, p.goldText, context.tr('sync_offline')),
          SyncState.error => (Icons.error_outline_rounded, p.liveText, context.tr('sync_error')),
          _ => (Icons.cloud_done_rounded, p.win, sync.lastOk == null ? context.tr('sync_ready') : context.tr('sync_ok', {'t': agoText(context, sync.lastOk!)})),
        };
        return Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: Tx.small(color, w: FontWeight.w700))),
        ]);
      },
    );
  }
}
