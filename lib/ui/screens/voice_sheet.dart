// Voice scoring: hold the phone, tap the mic and say the ball.
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../scoring/commentary.dart';
import '../../scoring/engine.dart';
import '../../scoring/voice.dart';
import '../widgets/common.dart';
import 'scoring_sheets.dart';

final SpeechToText _stt = SpeechToText();
bool _sttReady = false;

/// Listens once and returns what to score, or null when cancelled.
Future<VoiceCall?> listenForBall(BuildContext context, {required String striker, required String bowler}) {
  return showAppSheet<VoiceCall>(context, (ctx) => _VoiceSheet(striker: striker, bowler: bowler));
}

String voiceCallText(BuildContext context, VoiceCall c) {
  final lang = context.settings.lang;
  if (c.needsWicketDetails) return context.tr('voice_wicket_ask');
  if (c.out != null) return '${context.tr('wicket')} · ${context.tr('out_${c.out!.replaceAll(' ', '_')}')}';
  final parts = <String>[];
  switch (c.kind) {
    case BallKind.wide:
      parts.add(context.tr('wide'));
    case BallKind.noBall:
      parts.add(context.tr('no_ball'));
    case BallKind.bye:
      parts.add(context.tr('bye'));
    case BallKind.legBye:
      parts.add(context.tr('leg_bye'));
  }
  if (c.kind == BallKind.normal || c.runs > 0) {
    parts.add(c.runs == 4
        ? context.tr('four')
        : c.runs == 6
            ? context.tr('six')
            : c.runs == 0
                ? context.tr('dot_ball')
                : context.tr('runs_n', {'n': c.runs}));
  }
  if (c.zone != null) parts.add(Zone.name(c.zone!, lang));
  if (c.shot != null) parts.add(Shot.name(c.shot!, lang));
  return parts.join(' · ');
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({required this.striker, required this.bowler});
  final String striker;
  final String bowler;

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  String _heard = '';
  VoiceCall? _call;
  bool _listening = false;
  bool _failed = false;
  String _error = '';
  double _level = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (_stt.isListening) _stt.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final lang = context.settings.lang;
    final noMic = context.tr('voice_no_mic');
    setState(() {
      _heard = '';
      _call = null;
      _failed = false;
      _error = '';
    });
    try {
      if (!_sttReady) {
        _sttReady = await _stt.initialize(
          onError: (e) {
            if (mounted) setState(() => _listening = false);
          },
          onStatus: (s) {
            if (mounted && (s == 'done' || s == 'notListening')) setState(() => _listening = false);
          },
        );
      }
      if (!_sttReady) {
        setState(() {
          _failed = true;
          _error = noMic;
        });
        return;
      }
      setState(() => _listening = true);
      await _stt.listen(
        onResult: _onResult,
        localeId: lang == 'hi' ? 'hi_IN' : 'en_IN',
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        onSoundLevelChange: (l) {
          if (mounted) setState(() => _level = l);
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _failed = true;
          _error = noMic;
        });
      }
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    final words = r.recognizedWords;
    // Try every guess the phone made, best first.
    VoiceCall? call = parseVoice(words);
    if (call == null && r.finalResult) {
      for (final a in r.alternates) {
        call = parseVoice(a.recognizedWords);
        if (call != null) break;
      }
    }
    setState(() {
      _heard = words;
      _call = call ?? _call;
      if (r.finalResult) {
        _listening = false;
        if (_call == null) _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final call = _call;
    final bars = List.generate(17, (i) {
      final wave = (i % 5 + 1) / 5;
      final lvl = _listening ? ((_level + 2).clamp(0, 12) / 12) : 0.05;
      return 6 + 44 * wave * lvl;
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.edge, 0, Space.edge, Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(context.tr('voice_scoring'), subtitle: '${widget.striker} · ${widget.bowler}'),
        const SizedBox(height: Space.s),
        Text(
          _listening ? context.tr('voice_listening').toUpperCase() : (_failed ? context.tr('voice_not_heard') : context.tr('voice_heard')).toUpperCase(),
          textAlign: TextAlign.center,
          style: Tx.label(p.text2, w: FontWeight.w800).copyWith(letterSpacing: 2),
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 56,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final h in bars)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 4,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE7A3), Color(0xFFF97316)]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: Space.s),
        Text(
          _heard.isEmpty ? (_failed ? _error : context.tr('voice_examples')) : '“$_heard”',
          textAlign: TextAlign.center,
          style: _heard.isEmpty ? Tx.small(p.text2) : Tx.title(p.text).copyWith(fontSize: 22),
        ),
        const SizedBox(height: Space.m),
        if (call != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.win.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: p.win.withValues(alpha: 0.4))),
            child: Row(children: [
              Icon(call.isWicket ? Icons.sports_cricket_rounded : Icons.check_circle_rounded, color: p.win),
              const SizedBox(width: 10),
              Expanded(child: Text(voiceCallText(context, call), style: Tx.body(p.text, w: FontWeight.w800))),
            ]),
          ),
        const SizedBox(height: Space.m),
        Row(children: [
          Expanded(
            child: OutlineBtn(
              label: context.tr('voice_again'),
              icon: Icons.mic_rounded,
              height: 50,
              onPressed: _listening ? null : _start,
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: GoldButton(
              label: call?.needsWicketDetails == true ? context.tr('next') : context.tr('save'),
              icon: Icons.check_rounded,
              height: 50,
              onPressed: call == null ? null : () => Navigator.pop(context, call),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Round mic button for the scoring screen.
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('voice_scoring'),
      child: Pressable(
        onTap: onPressed,
        semanticLabel: context.tr('voice_scoring'),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7A3), Color(0xFFF4C247), Color(0xFFE9A21A)]),
            boxShadow: [BoxShadow(color: Color(0x55FFC94A), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.mic_rounded, color: Color(0xFF0B1220)),
        ),
      ),
    );
  }
}
