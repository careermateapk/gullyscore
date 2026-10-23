// The ☰ side menu: create, tournaments, leaderboard, help, policies, blog
// and social links.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../widgets/app_tour.dart';
import '../widgets/common.dart';
import 'booking_screens.dart';
import 'grounds_screen.dart';
import 'help.dart';
import 'live_info_screen.dart';
import 'info_screens.dart';
import 'leaderboard_screen.dart';
import 'new_match_screen.dart';
import 'news_screen.dart';
import 'online.dart';
import 'series_screen.dart';
import 'tournament_screens.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _run(BuildContext context, void Function(BuildContext) f) {
    final nav = Navigator.of(context);
    final ctx = nav.context;
    nav.pop();
    f(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(IconData icon, Color c, String label, VoidCallback onTap, {String? badge, bool highlight = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          child: Material(
            color: highlight ? p.gold.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                    child: Icon(icon, size: 20, color: c),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(label, style: Tx.body(highlight ? p.goldText : p.text, w: FontWeight.w700))),
                  if (badge != null) Tag(badge, color: p.goldText, background: p.gold.withValues(alpha: 0.14)),
                ]),
              ),
            ),
          ),
        );
    Widget social(IconData icon, String label, String key) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: p.text,
              side: BorderSide(color: p.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => openSocial(context, key),
            icon: Icon(icon, size: 18),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: Tx.small(p.text, w: FontWeight.w800))),
          ),
        );

    return Drawer(
      backgroundColor: p.surface,
      width: MediaQuery.of(context).size.width.clamp(0, 340) * 0.86,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: Space.l), children: [
          const _DrawerHeader(),
          const SizedBox(height: Space.s),
          item(Icons.add_circle_outline_rounded, p.goldText, context.tr('create_match'), () => _push(context, const NewMatchScreen()), highlight: true),
          item(Icons.emoji_events_outlined, const Color(0xFFA855F7), context.tr('add_tournament'), () => _push(context, const CreateTournamentScreen())),
          item(Icons.table_chart_outlined, const Color(0xFFA855F7), context.tr('tournaments_table'), () => _push(context, const SeriesScreen(pushed: true))),
          item(Icons.videocam_outlined, p.liveText, context.tr('live_streaming'), () => _push(context, const LiveInfoScreen()), badge: context.tr('new_badge')),
          item(Icons.leaderboard_outlined, p.win, context.tr('leaderboard'), () => _push(context, const LeaderboardScreen())),
          item(Icons.place_outlined, p.liveText, context.tr('grounds_near_you'), () => _push(context, const GroundsScreen())),
          item(Icons.event_available_outlined, p.goldText, context.tr('my_bookings'), () => _push(context, const BookingsScreen())),
          item(Icons.article_outlined, const Color(0xFF5B9BFF), context.tr('nav_news'), () => _push(context, const NewsScreen(pushed: true))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Space.s), child: Divider(color: p.line, height: 1)),
          item(Icons.help_outline_rounded, const Color(0xFF5B9BFF), context.tr('help_and_faq'), () => _push(context, const FaqScreen())),
          item(Icons.tour_outlined, p.goldText, context.tr('app_tour'), () => _run(context, (_) => tourRequest.value++)),
          item(Icons.lock_outline_rounded, p.win, context.tr('privacy_policy'), () => _push(context, const InfoScreen(kind: 'privacy'))),
          item(Icons.description_outlined, p.text2, context.tr('terms'), () => _push(context, const InfoScreen(kind: 'terms'))),
          item(Icons.info_outline_rounded, const Color(0xFFFF8A3D), context.tr('about_us'), () => _push(context, const InfoScreen(kind: 'about'))),
          item(Icons.menu_book_outlined, const Color(0xFF5B9BFF), context.tr('blog'), () => _run(context, openBlog)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, Space.l, 18, Space.s),
            child: Text(context.tr('follow_us').toUpperCase(), style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 0.6)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(children: [
              Row(children: [social(Icons.photo_camera_outlined, 'Instagram', 'instagram'), const SizedBox(width: Space.s), social(Icons.facebook_outlined, 'Facebook', 'facebook')]),
              const SizedBox(height: Space.s),
              Row(children: [social(Icons.smart_display_outlined, 'YouTube', 'youtube'), const SizedBox(width: Space.s), social(Icons.alternate_email_rounded, 'X', 'x')]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: Text('GullyScore 0.8 · Made in India 🇮🇳', textAlign: TextAlign.center, style: Tx.label(p.text2, w: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final me = sync.me;
        return Container(
          margin: const EdgeInsets.fromLTRB(10, Space.s, 10, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corners.hero),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.hero1, p.hero2]),
            border: Border.all(color: p.heroLine),
          ),
          child: me != null
              ? Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF2563EB),
                    child: Text(initials(me.name.isEmpty ? me.email : me.name), style: Tx.body(Colors.white, w: FontWeight.w800)),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(me.name.isEmpty ? context.tr('player') : me.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
                      Text(me.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.small(p.text2)),
                    ]),
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('GullyScore', style: Tx.score(24, p.text, w: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(context.tr('are_you_player_body'), style: Tx.small(p.text2)),
                  if (sync.loginAvailable) ...[
                    const SizedBox(height: Space.m),
                    GoldButton(
                      label: context.tr('login_google'),
                      icon: Icons.login_rounded,
                      height: 44,
                      onPressed: () {
                        final nav = Navigator.of(context);
                        final ctx = nav.context;
                        nav.pop();
                        loginAsPlayer(ctx);
                      },
                    ),
                  ],
                ]),
        );
      },
    );
  }
}
