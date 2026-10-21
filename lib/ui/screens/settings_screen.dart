// Profile tab: appearance, scoring options, teams, help and your data.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'backup_ui.dart';
import 'help.dart';
import 'info_screens.dart';
import 'notifications_screen.dart';
import 'match_centre_screen.dart';
import 'online.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAll(BuildContext context) async {
    final repo = context.repo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_all_q')),
        content: Text(ctx.tr('delete_all_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete_everything'), style: TextStyle(color: Palette.of(ctx).liveText))),
        ],
      ),
    );
    if (ok != true) return;
    await repo.deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('all_deleted'))));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_account_q')),
        content: Text(ctx.tr('delete_account_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'), style: TextStyle(color: Palette.of(ctx).liveText))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('account_deleted');
    final failed = context.tr('online_failed');
    try {
      await context.sync.deleteAccount();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context).settings;
    final repo = context.repo;

    Widget group(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.edge, Space.l, Space.edge, Space.s),
            child: Semantics(header: true, child: Text(title.toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 0.4))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.edge),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.line),
                  children[i],
                ],
              ]),
            ),
          ),
        ]);

    Widget icon(IconData i, Color c) => Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(10)),
          child: Icon(i, size: 18, color: c),
        );

    Widget toggle(IconData i, Color c, String title, String? sub, bool value, ValueChanged<bool> on) => SwitchListTile(
          value: value,
          onChanged: on,
          secondary: icon(i, c),
          title: Text(title, style: Tx.body(p.text, w: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub, style: Tx.label(p.text2, w: FontWeight.w500)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        );

    Widget link(IconData i, Color c, String title, VoidCallback onTap, {Color? textColor, String? trailing}) => ListTile(
          leading: icon(i, c),
          title: Text(title, style: Tx.body(textColor ?? p.text, w: FontWeight.w600)),
          trailing: trailing != null ? Text(trailing, style: Tx.small(p.text2)) : Icon(Icons.chevron_right_rounded, color: p.text2),
          onTap: onTap,
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        );

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
          child: Semantics(header: true, child: Text(context.tr('nav_profile'), style: Tx.title(p.text))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, 0),
          child: AppCard(
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: p.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.sports_cricket_rounded, color: p.goldText),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('scorer'), style: Tx.body(p.text, w: FontWeight.w800)),
                  Text(context.tr('scored_summary', {'m': repo.matches.length, 't': repo.teams.length}), style: Tx.label(p.text2, w: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ),
        group(context.tr('appearance'), [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                icon(Icons.dark_mode_outlined, p.goldText),
                const SizedBox(width: Space.m),
                Expanded(child: Text(context.tr('theme'), style: Tx.body(p.text, w: FontWeight.w600))),
              ]),
              const SizedBox(height: Space.s),
              Segmented<ThemeMode>(
                values: const [ThemeMode.light, ThemeMode.dark, ThemeMode.system],
                labels: [context.tr('light'), context.tr('dark'), context.tr('auto')],
                selected: s.themeMode,
                onChanged: s.setTheme,
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                icon(Icons.translate_rounded, const Color(0xFF5B9BFF)),
                const SizedBox(width: Space.m),
                Expanded(child: Text(context.tr('language'), style: Tx.body(p.text, w: FontWeight.w600))),
              ]),
              const SizedBox(height: Space.s),
              Segmented<String>(values: const ['en', 'hi'], labels: const ['English', 'हिंदी'], selected: s.lang, onChanged: s.setLang),
            ]),
          ),
          toggle(Icons.motion_photos_off_outlined, p.win, context.tr('reduce_motion'), context.tr('reduce_motion_sub'), s.reduceMotion, s.setReduceMotion),
        ]),
        group(context.tr('scoring'), [
          toggle(Icons.my_location_rounded, p.goldText, context.tr('ask_direction'), context.tr('ask_direction_sub'), s.askShotDirection, s.setAskShot),
          toggle(Icons.vibration_rounded, p.six, context.tr('vibration'), context.tr('vibration_sub'), s.haptics, s.setHaptics),
        ]),
        group(context.tr('help'), [
          link(Icons.help_outline_rounded, const Color(0xFF5B9BFF), context.tr('help_and_faq'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqScreen()))),
          link(Icons.lock_outline_rounded, p.win, context.tr('privacy_policy'), () => openInfo(context, 'privacy')),
          link(Icons.description_outlined, p.text2, context.tr('terms'), () => openInfo(context, 'terms')),
          link(Icons.info_outline_rounded, const Color(0xFFFF8A3D), context.tr('about_us'), () => openInfo(context, 'about')),
        ]),
        if (context.sync.enabled)
          ListenableBuilder(
            listenable: context.sync,
            builder: (context, _) {
              final sync = context.sync;
              return group(context.tr('online'), [
                toggle(Icons.public_rounded, p.win, context.tr('share_online'), context.tr('share_online_sub'), sync.shareOnline, sync.setShareOnline),
                Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: const SyncStatusLine()),
                if (sync.loggedIn) ...[
                  link(Icons.account_circle_rounded, p.goldText, sync.me?.email ?? context.tr('logged_in'), () => logoutPlayer(context), trailing: context.tr('logout')),
                  link(Icons.phone_android_rounded, p.goldText, sync.myPhone.isEmpty ? context.tr('add_my_mobile') : context.tr('my_mobile_n', {'n': sync.myPhone}),
                      () => askMyPhone(context)),
                  link(Icons.person_remove_outlined, p.liveText, context.tr('delete_account'), () => _deleteAccount(context), textColor: p.liveText),
                ] else if (sync.loginAvailable)
                  link(Icons.login_rounded, p.goldText, context.tr('login_google'), () => loginAsPlayer(context)),
                link(Icons.link_rounded, const Color(0xFF5B9BFF), context.tr('follow_a_match'), () => followMatchByLink(context)),
                link(Icons.notifications_none_rounded, p.goldText, context.tr('notifications'),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
              ]);
            },
          )
        else
          group(context.tr('online'), [
            Padding(padding: const EdgeInsets.all(14), child: Text(context.tr('online_not_set_up'), style: Tx.small(p.text2))),
          ]),
        group(context.tr('backup'), [
          link(Icons.cloud_upload_outlined, p.goldText, context.tr('make_backup'), () => makeBackup(context),
              trailing: s.lastBackup == null ? context.tr('never') : agoText(context, s.lastBackup!)),
          link(Icons.settings_backup_restore_rounded, const Color(0xFF5B9BFF), context.tr('restore_from_backup'), () => restoreBackup(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(context.tr('backup_note'), style: Tx.label(p.text2, w: FontWeight.w500)),
          ),
        ]),
        group(context.tr('your_data'), [
          link(Icons.phone_android_rounded, p.text2, context.tr('saved_on_phone'), () => showHelp(context, 'settings'), trailing: context.tr('matches_n', {'n': repo.matches.length})),
          link(Icons.delete_outline_rounded, p.liveText, context.tr('delete_all_data'), () => _deleteAll(context), textColor: p.liveText),
        ]),
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Text('GullyScore 0.7', textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
        ),
      ]),
    );
  }
}
