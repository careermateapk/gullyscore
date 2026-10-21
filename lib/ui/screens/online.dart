// Online pieces: follow a match by link, invite a player, "This is me",
// and the "My matches" list for a linked player.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/cloud.dart';
import '../../data/models.dart';
import '../../data/sync.dart';
import '../widgets/common.dart';
import 'match_centre_screen.dart';

Future<String?> _askText(BuildContext context, {required String title, required String hint, String? body, bool caps = false}) {
  final ctrl = TextEditingController();
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
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('ok'))),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

String _cloudMessage(BuildContext context, Object e) {
  if (e is CloudError && e.offline) return context.tr('needs_internet');
  if (e is CloudError && e.status == 404) return context.tr('not_found_online');
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

/// Makes an invite code for a player and opens the share sheet.
Future<void> invitePlayer(BuildContext context, Player p) async {
  final sync = context.sync;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await sync.invite(p);
    if (!context.mounted) return;
    final text = context.tr('invite_text', {'name': p.name, 'link': r.link, 'code': r.code});
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(_cloudMessage(context, e))));
  }
}

/// "This is me": link this phone to a player profile.
Future<void> linkMyProfile(BuildContext context) async {
  final code = await _askText(context, title: context.tr('this_is_me'), hint: 'ABCD2345', body: context.tr('this_is_me_body'), caps: true);
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  final sync = context.sync;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final inv = await sync.linkProfile(code);
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(context.tr('linked_as', {'name': inv.name}))));
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(_cloudMessage(context, e))));
  }
}

/// List of the linked player's matches (on Home).
class MyMatchesSection extends StatefulWidget {
  const MyMatchesSection({super.key});

  @override
  State<MyMatchesSection> createState() => _MyMatchesSectionState();
}

class _MyMatchesSectionState extends State<MyMatchesSection> {
  Future<List<MatchListItem>>? _future;
  String? _for;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final me = sync.linkedPlayerId;
        if (!sync.enabled || me == null) return const SizedBox.shrink();
        if (_for != me) {
          _for = me;
          _future = sync.myMatches();
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(context.tr('my_matches_name', {'name': sync.linkedName ?? ''}), action: context.tr('refresh'), onAction: () => setState(() => _future = sync.myMatches())),
          FutureBuilder<List<MatchListItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.edge),
                  child: Shimmer(child: SkeletonBox(height: 72, radius: Corners.card)),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                  child: AppCard(
                    onTap: () => setState(() => _future = sync.myMatches()),
                    child: Row(children: [
                      Icon(Icons.cloud_off_rounded, color: p.text2),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text(_cloudMessage(context, snap.error!), style: Tx.small(p.text2))),
                      Text(context.tr('try_again'), style: Tx.small(p.goldText, w: FontWeight.w800)),
                    ]),
                  ),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.edge),
                  child: AppCard(child: Text(context.tr('no_my_matches'), style: Tx.small(p.text2))),
                );
              }
              return Column(children: [
                for (final m in list.take(5))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.s),
                    child: AppCard(
                      onTap: () => openFollowed(context, m.id),
                      child: Row(children: [
                        if (!m.finished) ...[LiveBadge(label: context.tr('live')), const SizedBox(width: Space.m)],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${m.summary['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800)),
                            Text('${m.summary['status'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.small(m.finished ? p.win : p.goldText, w: FontWeight.w700)),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: p.text2),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ]);
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
