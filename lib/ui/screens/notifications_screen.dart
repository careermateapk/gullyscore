// Choose which notifications this phone gets.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../data/push.dart';
import '../widgets/common.dart';

const _icons = {'s': '🏏', 'w': '🔴', 'b': '💥', 'f': '⭐', 'a': '🙋', 'c': '💬'};

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = context.sync;
    final push = sync.push;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: push,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(Space.edge, Space.m, Space.edge, Space.xl), children: [
            Row(children: [
              IconBtn(icon: Icons.arrow_back_rounded, tooltip: context.tr('back'), onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(context.tr('notifications'), style: Tx.title(p.text).copyWith(fontSize: 20))),
            ]),
            const SizedBox(height: Space.m),
            Text(context.tr(PushService.configured ? 'notifications_sub' : 'notifications_off'), style: Tx.small(p.text2, w: FontWeight.w600)),
            if (PushService.configured && !sync.loggedIn) ...[
              const SizedBox(height: Space.s),
              Text(context.tr('notifications_login'), style: Tx.small(p.goldText, w: FontWeight.w700)),
            ],
            const SizedBox(height: Space.m),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final k in pushKinds)
                  SwitchListTile(
                    value: push.on[k] ?? false,
                    onChanged: !PushService.configured
                        ? null
                        : (v) async {
                            await push.setSwitch(k, v);
                            await sync.updatePush();
                          },
                    secondary: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(11)),
                      child: Text(_icons[k]!, style: const TextStyle(fontSize: 18)),
                    ),
                    title: Text(context.tr('push_$k'), style: Tx.body(p.text, w: FontWeight.w700)),
                    subtitle: Text(context.tr('push_${k}_sub'), style: Tx.small(p.text2)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
