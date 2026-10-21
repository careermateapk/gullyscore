// Privacy policy, terms & conditions and about us (in the app, works
// offline), plus helpers that open the blog, social pages and WhatsApp.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/content.dart';
import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';

/// Opens a web page or app link outside GullyScore. Shows a message if it can't.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.tr('could_not_open');
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
}

void comingSoon(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('coming_soon'))));

Future<void> openSocial(BuildContext context, String key) async {
  final c = await AppContent.load();
  if (!context.mounted) return;
  final url = c.social(key);
  if (url.isEmpty) {
    comingSoon(context);
  } else {
    await openLink(context, url);
  }
}

Future<void> openBlog(BuildContext context) async {
  final sync = context.sync;
  if (!sync.enabled) {
    comingSoon(context);
    return;
  }
  await openLink(context, '${sync.cloud.baseUrl}/blog');
}

void openInfo(BuildContext context, String kind) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => InfoScreen(kind: kind)));

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, required this.kind});
  final String kind; // privacy, terms, about

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lang = AppScope.of(context).settings.lang;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: FutureBuilder<AppContent>(
          future: AppContent.load(),
          builder: (context, snap) {
            final c = snap.data;
            final page = c?.page(kind, lang);
            return ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl), children: [
              Row(children: [
                IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
                const SizedBox(width: Space.m),
                Expanded(child: Semantics(header: true, child: Text(page?.title ?? '', style: Tx.title(p.text).copyWith(fontSize: 20)))),
              ]),
              if (page == null)
                const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
              else ...[
                const SizedBox(height: Space.m),
                if (kind != 'about') Text(context.tr('last_updated', {'d': c!.updated}), style: Tx.label(p.text2, w: FontWeight.w600)),
                const SizedBox(height: Space.m),
                HeroCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr(kind == 'about' ? 'about_short' : 'in_short'), style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
                    for (final s in page.short)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s + 2),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_rounded, size: 18, color: p.win)),
                          const SizedBox(width: Space.s + 2),
                          Expanded(child: Text(s, style: Tx.body(p.text, w: FontWeight.w600).copyWith(height: 1.45))),
                        ]),
                      ),
                  ]),
                ),
                for (var i = 0; i < page.sections.length; i++) ...[
                  const SizedBox(height: Space.l),
                  Text(kind == 'about' ? page.sections[i].$1 : '${i + 1}. ${page.sections[i].$1}', style: Tx.body(p.text, w: FontWeight.w800).copyWith(fontSize: 16)),
                  for (final line in page.sections[i].$2)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (page.sections[i].$2.length > 1)
                          Padding(padding: const EdgeInsets.fromLTRB(2, 9, 10, 0), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: p.text2, shape: BoxShape.circle))),
                        Expanded(child: Text(line, style: Tx.body(p.text2).copyWith(height: 1.55))),
                      ]),
                    ),
                ],
                if (c!.contact.isNotEmpty) ...[
                  const SizedBox(height: Space.l),
                  Text(context.tr('contact_us', {'e': c.contact}), style: Tx.body(p.text2)),
                ],
              ],
            ]);
          },
        ),
      ),
    );
  }
}
