// Log in / Sign up: shown after the intro until the person has an account.
// Email + password or Google. Google log in only works after signing up.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../data/cloud.dart';
import '../../data/google_auth.dart';
import '../../data/places_in.dart';
import '../../data/social.dart';
import '../widgets/online_cards.dart';
import 'info_screens.dart';

const _ink = Color(0xFF0B1220);
const _goldA = Color(0xFFF4C247);
const _goldB = Color(0xFFFFE7A3);
const _green = Color(0xFF2BD38A);
const _red = Color(0xFFFF4D4D);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false});
  final bool startOnSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late bool _signUp = widget.startOnSignUp;
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _busy = false;
  String? _error; // shown above the buttons
  bool _noGoogleAccount = false; // "No account for this Gmail" card

  // log in
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;

  // sign up
  final _form = SignUpForm();
  final _name = TextEditingController();
  final _sEmail = TextEditingController();
  final _phone = TextEditingController();
  final _sPass = TextEditingController();
  final _sPass2 = TextEditingController();
  final _stateText = TextEditingController();
  final _cityText = TextEditingController();
  Country _country = countries.first;
  bool _showSPass = false;
  bool _tried = false; // show what is missing after the first try

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _enter.value = 1;
    } else if (_enter.value == 0 && !_enter.isAnimating) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _pass, _name, _sEmail, _phone, _sPass, _sPass2, _stateText, _cityText]) {
      c.dispose();
    }
    _enter.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _switch(bool signUp) {
    if (signUp == _signUp) return;
    setState(() {
      _signUp = signUp;
      _error = null;
      _noGoogleAccount = false;
    });
    if (!context.reduceMotion) _enter.forward(from: 0.35);
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    HapticFeedback.mediumImpact();
    if (!context.reduceMotion) _shake.forward(from: 0);
  }

  String _msg(Object e) {
    if (e is CloudError) {
      if (e.status == 401) return context.tr('auth_wrong_password');
      if (e.status == 404) return context.tr('auth_not_signed_up');
      if (e.status == 409 && e.message.contains('google')) return context.tr('auth_use_google');
      if (e.status == 409) return context.tr('auth_email_taken');
      if (e.status == 429) return context.tr('auth_too_many');
    }
    if (e is GoogleLoginError) return e.message;
    return onlineError(context, e);
  }

  // ------------------------------------------------------------ actions

  Future<void> _logIn() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) || _pass.text.isEmpty) {
      return _fail(context.tr('auth_fill_login'));
    }
    await _run(() => context.sync.logInEmail(_email.text, _pass.text));
  }

  Future<void> _googleLogIn() async {
    setState(() => _noGoogleAccount = false);
    try {
      setState(() => _busy = true);
      await context.sync.logInGoogle();
    } on GoogleLoginError catch (e) {
      if (!e.cancelled && mounted) _fail(_msg(e));
    } on CloudError catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        setState(() => _noGoogleAccount = true);
        HapticFeedback.heavyImpact();
        if (!context.reduceMotion) _shake.forward(from: 0);
      } else {
        _fail(_msg(e));
      }
    } catch (e) {
      if (mounted) _fail(_msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillForm() {
    _form
      ..name = _name.text
      ..email = _sEmail.text
      ..password = _sPass.text
      ..countryCode = _country.code
      ..phone = _phone.text
      ..state = _country.code == '+91' ? _form.state : _stateText.text
      ..city = _country.code == '+91' ? _form.city : _cityText.text;
  }

  /// What is still missing for sign up (null when everything is fine).
  String? _missing({bool google = false}) {
    _fillForm();
    final f = _form;
    if (!google && f.name.trim().length < 2) return context.tr('auth_need_name');
    final digits = f.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6 || (f.countryCode == '+91' && digits.length != 10)) return context.tr('auth_need_phone');
    if (!google) {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(f.email.trim())) return context.tr('auth_need_email');
      if (passwordScore(f.password) < 1) return context.tr('auth_need_password');
      if (_sPass2.text != f.password) return context.tr('auth_password_mismatch');
    }
    if (f.state.trim().isEmpty || f.city.trim().isEmpty) return context.tr('auth_need_place');
    if (!f.agree) return context.tr('auth_need_agree');
    return null;
  }

  Future<void> _signUpNow({bool google = false}) async {
    setState(() => _tried = true);
    final m = _missing(google: google);
    if (m != null) return _fail(m);
    await _run(() => context.sync.signUp(_form, google: google));
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on GoogleLoginError catch (e) {
      if (!e.cancelled && mounted) _fail(_msg(e));
    } catch (e) {
      if (mounted) _fail(_msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('auth_forgot_title')),
          content: Text(ctx.tr('auth_forgot_body')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
        ),
      );

  // ------------------------------------------------------------ pickers

  Future<void> _pickCountry() async {
    final c = await _searchSheet<Country>(
      title: context.tr('auth_country_code'),
      hint: context.tr('auth_search_country'),
      items: countries,
      label: (c) => '${c.flag}  ${c.name}',
      trailing: (c) => c.code,
      selected: _country,
      matches: (c, q) => c.name.toLowerCase().contains(q) || c.code.contains(q),
    );
    if (c != null) setState(() => _country = c);
  }

  Future<void> _pickState() async {
    final s = await _searchSheet<String>(
      title: context.tr('auth_choose_state'),
      hint: context.tr('auth_search_state'),
      items: indiaPlaces.keys.toList(),
      label: (s) => s,
      selected: _form.state.isEmpty ? null : _form.state,
      matches: (s, q) => s.toLowerCase().contains(q),
    );
    if (s != null) {
      setState(() {
        if (_form.state != s) _form.city = '';
        _form.state = s;
      });
    }
  }

  Future<void> _pickCity() async {
    if (_form.state.isEmpty) return _pickState();
    final other = context.tr('auth_other_city');
    final c = await _searchSheet<String>(
      title: context.tr('auth_choose_city'),
      hint: context.tr('auth_search_city'),
      items: [...indiaPlaces[_form.state] ?? const <String>[], other],
      label: (s) => s,
      selected: _form.city.isEmpty ? null : _form.city,
      matches: (s, q) => s == other || s.toLowerCase().contains(q),
    );
    if (c == null || !mounted) return;
    if (c == other) {
      final typed = await _askCity();
      if (typed != null && typed.trim().isNotEmpty) setState(() => _form.city = typed.trim());
      return;
    }
    setState(() => _form.city = c);
  }

  Future<String?> _askCity() async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('auth_type_city')),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    ctrl.dispose();
    return v;
  }

  Future<T?> _searchSheet<T>({
    required String title,
    required String hint,
    required List<T> items,
    required String Function(T) label,
    String Function(T)? trailing,
    T? selected,
    required bool Function(T, String) matches,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1626),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => _SearchList<T>(title: title, hint: hint, items: items, label: label, trailing: trailing, selected: selected, matches: matches),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF03060D),
      resizeToAvoidBottomInset: true,
      body: AnimatedBuilder(
        animation: Listenable.merge([_enter, _shake]),
        builder: (context, _) {
          final t = _enter.value;
          double iv(double a, double b) => Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          final shake = math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value);
          return Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -1.1), radius: 1.4, colors: [Color(0xFF3A0B4F), Color(0xFF140A2A), Color(0xFF03060D)], stops: [0, 0.4, 0.8]),
            ),
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 0, height: size.height * 0.45, child: CustomPaint(painter: _Beams())),
              SafeArea(
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), gradient: const LinearGradient(colors: [_goldB, _goldA])),
                          child: const Icon(Icons.sports_cricket_rounded, size: 18, color: _ink),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('GullyScore', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                        _Lang(lang: s.lang, onChanged: s.setLang),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                      child: Opacity(
                        opacity: iv(0.0, 0.4),
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - iv(0.0, 0.4))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(context.tr(_signUp ? 'auth_join_a' : 'auth_welcome_a').toUpperCase(), style: _display(40)),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFB8862B), _goldB, _goldA, Color(0xFFFFF3C9), Color(0xFFC9952F)]).createShader(r),
                                child: Text(context.tr(_signUp ? 'auth_join_b' : 'auth_welcome_b').toUpperCase(), style: _display(40)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(context.tr(_signUp ? 'auth_join_sub' : 'auth_welcome_sub'), style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Transform.translate(
                      offset: Offset(0, 80 * (1 - iv(0.15, 0.7))),
                      child: Opacity(
                        opacity: iv(0.15, 0.6),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF12182A).withValues(alpha: 0.96), const Color(0xFF080C18)]),
                            border: const Border(top: BorderSide(color: Color(0x1FFFFFFF))),
                            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, -10))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _Tabs(signUp: _signUp, onChanged: _switch, login: context.tr('auth_login'), signup: context.tr('auth_signup')),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              child: _noGoogleAccount ? Padding(padding: const EdgeInsets.only(top: 14), child: _NoAccountCard(onSignUp: () => _switch(true))) : const SizedBox(width: double.infinity),
                            ),
                            Transform.translate(
                              offset: Offset(shake, 0),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: c)),
                                child: _signUp ? KeyedSubtree(key: const ValueKey('su'), child: _signUpForm()) : KeyedSubtree(key: const ValueKey('li'), child: _logInForm()),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _errorLine() => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8080), size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8080), fontWeight: FontWeight.w700, fontSize: 12.5))),
                ]),
              ),
      );

  Widget _logInForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      _Field(controller: _email, label: context.tr('auth_email'), icon: Icons.mail_outline_rounded, keyboard: TextInputType.emailAddress, autofill: const [AutofillHints.email]),
      _Field(
        controller: _pass,
        label: context.tr('auth_password'),
        icon: Icons.lock_outline_rounded,
        obscure: !_showPass,
        suffix: IconButton(
          tooltip: context.tr('auth_show_password'),
          onPressed: () => setState(() => _showPass = !_showPass),
          icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white60, size: 20),
        ),
        onSubmitted: (_) => _logIn(),
        autofill: const [AutofillHints.password],
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _forgot,
          style: TextButton.styleFrom(foregroundColor: _goldB, minimumSize: const Size(44, 40)),
          child: Text(context.tr('auth_forgot'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ),
      _errorLine(),
      const SizedBox(height: 10),
      _PrimaryButton(label: _busy ? context.tr('auth_please_wait') : context.tr('auth_login_btn'), onTap: _busy ? null : _logIn),
      _Or(text: context.tr('auth_or')),
      _GoogleButton(label: context.tr('auth_google_login'), onTap: _busy ? null : _googleLogIn, warn: _noGoogleAccount),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(context.tr('auth_new_here'), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600, fontSize: 13)),
        TextButton(
          onPressed: () => _switch(true),
          style: TextButton.styleFrom(foregroundColor: _goldB, minimumSize: const Size(44, 40)),
          child: Text(context.tr('auth_create_account'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ]),
    ]);
  }

  Widget _signUpForm() {
    final score = passwordScore(_sPass.text);
    final strength = _sPass.text.isEmpty ? -1 : (score == 0 ? 0 : (score == 1 ? 1 : 2));
    final match = _sPass2.text.isNotEmpty && _sPass2.text == _sPass.text;
    final india = _country.code == '+91';
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final phoneOk = india ? phoneDigits.length == 10 : phoneDigits.length >= 6;
    final emailOk = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_sEmail.text.trim());
    final ready = _missing() == null;
    Color? stateColor(bool ok, bool empty) => ok ? _green : (_tried && empty ? _red : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      _Field(controller: _name, label: context.tr('auth_full_name'), icon: Icons.person_outline_rounded, caps: TextCapitalization.words, ok: _name.text.trim().length >= 2, error: _tried && _name.text.trim().length < 2, onChanged: (_) => setState(() {}), autofill: const [AutofillHints.name]),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Semantics(
            button: true,
            label: '${context.tr('auth_country_code')} ${_country.name} ${_country.code}',
            child: GestureDetector(
              onTap: _pickCountry,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: _box(null),
                child: ExcludeSemantics(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_country.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(_country.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    const Icon(Icons.arrow_drop_down_rounded, color: Colors.white60),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Field(
            controller: _phone,
            label: context.tr('auth_mobile'),
            keyboard: TextInputType.phone,
            ok: phoneOk,
            error: _tried && !phoneOk,
            onChanged: (_) => setState(() {}),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(16)],
            autofill: const [AutofillHints.telephoneNumberNational],
          ),
        ),
      ]),
      _Field(controller: _sEmail, label: context.tr('auth_email'), icon: Icons.mail_outline_rounded, keyboard: TextInputType.emailAddress, ok: emailOk, error: _tried && !emailOk, onChanged: (_) => setState(() {}), autofill: const [AutofillHints.email]),
      _Field(
        controller: _sPass,
        label: context.tr('auth_password'),
        icon: Icons.lock_outline_rounded,
        obscure: !_showSPass,
        error: _tried && score < 1,
        onChanged: (_) => setState(() {}),
        suffix: IconButton(
          tooltip: context.tr('auth_show_password'),
          onPressed: () => setState(() => _showSPass = !_showSPass),
          icon: Icon(_showSPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white60, size: 20),
        ),
        autofill: const [AutofillHints.newPassword],
      ),
      if (strength >= 0) _Meter(level: strength, labels: [context.tr('auth_weak'), context.tr('auth_medium'), context.tr('auth_strong')], hints: [context.tr('auth_weak_hint'), context.tr('auth_medium_hint'), context.tr('auth_strong_hint')]),
      _Field(
        controller: _sPass2,
        label: context.tr('auth_password_again'),
        icon: Icons.lock_reset_rounded,
        obscure: !_showSPass,
        ok: match,
        error: _sPass2.text.isNotEmpty && !match,
        onChanged: (_) => setState(() {}),
        trailingText: _sPass2.text.isEmpty ? null : (match ? '✓ ${context.tr('auth_match')}' : '✕ ${context.tr('auth_no_match')}'),
      ),
      if (india)
        Row(children: [
          Expanded(child: _PickBox(label: context.tr('auth_state'), value: _form.state, icon: Icons.map_outlined, onTap: _pickState, color: stateColor(_form.state.isNotEmpty, _form.state.isEmpty))),
          const SizedBox(width: 8),
          Expanded(child: _PickBox(label: context.tr('auth_city'), value: _form.city, icon: Icons.place_outlined, onTap: _pickCity, color: stateColor(_form.city.isNotEmpty, _form.city.isEmpty))),
        ])
      else
        Row(children: [
          Expanded(child: _Field(controller: _stateText, label: context.tr('auth_state_province'), caps: TextCapitalization.words, ok: _stateText.text.trim().isNotEmpty, onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: _Field(controller: _cityText, label: context.tr('auth_city'), caps: TextCapitalization.words, ok: _cityText.text.trim().isNotEmpty, onChanged: (_) => setState(() {}))),
        ]),
      const SizedBox(height: 12),
      _Terms(
        agreed: _form.agree,
        warn: _tried && !_form.agree,
        onChanged: (v) => setState(() => _form.agree = v),
        pre: context.tr('auth_agree_pre'),
        terms: context.tr('terms'),
        and: context.tr('auth_agree_and'),
        privacy: context.tr('privacy_policy'),
        post: context.tr('auth_agree_post'),
      ),
      if (_tried && !_form.agree)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('☝️ ${context.tr('auth_need_agree')}', style: const TextStyle(color: Color(0xFFFF8080), fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      _errorLine(),
      const SizedBox(height: 12),
      _PrimaryButton(label: _busy ? context.tr('auth_please_wait') : context.tr('auth_create_btn'), onTap: _busy ? null : () => _signUpNow(), dim: !ready),
      _Or(text: context.tr('auth_or')),
      _GoogleButton(label: context.tr('auth_google_signup'), onTap: _busy ? null : () => _signUpNow(google: true)),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(context.tr('auth_google_signup_note'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 11.5)),
      ),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(context.tr('auth_have_account'), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600, fontSize: 13)),
        TextButton(
          onPressed: () => _switch(false),
          style: TextButton.styleFrom(foregroundColor: _goldB, minimumSize: const Size(44, 40)),
          child: Text(context.tr('auth_login'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ]),
    ]);
  }
}

TextStyle _display(double size) => TextStyle(fontFamily: 'Saira', fontFamilyFallback: const ['NotoDeva'], fontWeight: FontWeight.w800, fontSize: size, height: 1.08, color: Colors.white);

BoxDecoration _box(Color? border, {bool focus = false}) => BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withValues(alpha: focus ? 0.07 : 0.05),
      border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.12), width: 1.5),
    );

class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboard,
    this.obscure = false,
    this.suffix,
    this.ok = false,
    this.error = false,
    this.onChanged,
    this.onSubmitted,
    this.caps = TextCapitalization.none,
    this.formatters,
    this.trailingText,
    this.autofill,
  });
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffix;
  final bool ok;
  final bool error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization caps;
  final List<TextInputFormatter>? formatters;
  final String? trailingText;
  final Iterable<String>? autofill;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focus = _focus.hasFocus;
    final border = widget.error ? _red : (focus ? _goldA : (widget.ok ? _green.withValues(alpha: 0.6) : null));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(top: 10),
      decoration: _box(border, focus: focus).copyWith(boxShadow: focus ? [BoxShadow(color: _goldA.withValues(alpha: 0.16), spreadRadius: 3)] : null),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: widget.keyboard,
        obscureText: widget.obscure,
        textCapitalization: widget.caps,
        inputFormatters: widget.formatters,
        autofillHints: widget.autofill,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        cursorColor: _goldA,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
          floatingLabelStyle: TextStyle(color: widget.error ? const Color(0xFFFF8080) : _goldB, fontWeight: FontWeight.w800),
          prefixIcon: widget.icon == null ? null : Icon(widget.icon, color: Colors.white60, size: 20),
          suffixIcon: widget.suffix ??
              (widget.trailingText != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(widthFactor: 1, child: Text(widget.trailingText!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.ok ? _green : const Color(0xFFFF8080), fontWeight: FontWeight.w800, fontSize: 12))),
                    )
                  : (widget.ok ? const Icon(Icons.check_rounded, color: _green, size: 20) : null)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
    );
  }
}

class _PickBox extends StatelessWidget {
  const _PickBox({required this.label, required this.value, required this.icon, required this.onTap, this.color});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label ${value.isEmpty ? '' : value}',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: _box(color == null ? null : (color == _green ? _green.withValues(alpha: 0.6) : color)),
            child: ExcludeSemantics(
              child: Row(children: [
                Icon(icon, color: Colors.white60, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 10.5)),
                    Text(value.isEmpty ? '—' : value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ]),
                ),
                const Icon(Icons.arrow_drop_down_rounded, color: Colors.white60),
              ]),
            ),
          ),
        ),
      );
}

class _Meter extends StatelessWidget {
  const _Meter({required this.level, required this.labels, required this.hints});
  final int level; // 0 weak, 1 medium, 2 strong
  final List<String> labels;
  final List<String> hints;
  @override
  Widget build(BuildContext context) {
    const colors = [_red, _goldA, _green];
    final c = colors[level];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: i <= level ? c : Colors.white12,
                  boxShadow: i <= level && level == 2 ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)] : null,
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 5),
          ],
        ]),
        const SizedBox(height: 5),
        Text('${['😟', '🙂', '💪'][level]} ${labels[level]} · ${hints[level]}', style: TextStyle(color: level == 0 ? const Color(0xFFFF8080) : (level == 1 ? _goldB : _green), fontWeight: FontWeight.w800, fontSize: 11.5)),
      ]),
    );
  }
}

class _Terms extends StatelessWidget {
  const _Terms({required this.agreed, required this.warn, required this.onChanged, required this.pre, required this.terms, required this.and, required this.privacy, required this.post});
  final bool agreed;
  final bool warn;
  final ValueChanged<bool> onChanged;
  final String pre, terms, and, privacy, post;
  @override
  Widget build(BuildContext context) {
    const link = TextStyle(color: _goldB, fontWeight: FontWeight.w800);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: warn ? _red.withValues(alpha: 0.08) : Colors.transparent,
        border: Border.all(color: warn ? _red.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Row(children: [
        Checkbox(
          value: agreed,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: _goldA,
          checkColor: _ink,
          side: BorderSide(color: warn ? _red : Colors.white54, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        Expanded(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('$pre ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoScreen(kind: 'terms'))), child: Text(terms, style: link.copyWith(fontSize: 12.5))),
            Text(' $and ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoScreen(kind: 'privacy'))), child: Text(privacy, style: link.copyWith(fontSize: 12.5))),
            if (post.isNotEmpty) Text(post, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.signUp, required this.onChanged, required this.login, required this.signup});
  final bool signUp;
  final ValueChanged<bool> onChanged;
  final String login, signup;
  @override
  Widget build(BuildContext context) {
    Widget tab(bool v, String label) => Expanded(
          child: Semantics(
            button: true,
            selected: signUp == v,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(v),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: signUp == v ? _ink : Colors.white60, fontFamily: 'Hanken', fontFamilyFallback: const ['NotoDeva']),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white.withValues(alpha: 0.06), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutBack,
          alignment: signUp ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [_goldA, _goldB, _goldA]),
                boxShadow: const [BoxShadow(color: Color(0x59F4C247), blurRadius: 16, offset: Offset(0, 6))],
              ),
            ),
          ),
        ),
        Row(children: [tab(false, login), tab(true, signup)]),
      ]),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, this.dim = false});
  final String label;
  final VoidCallback? onTap;
  final bool dim;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: dim ? null : const LinearGradient(colors: [_goldA, _goldB, _goldA]),
              color: dim ? Colors.white.withValues(alpha: 0.08) : null,
              boxShadow: dim ? null : const [BoxShadow(color: Color(0x4DF4C247), blurRadius: 24, offset: Offset(0, 10))],
            ),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim ? Colors.white38 : _ink, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ),
        ),
      );
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onTap, this.warn = false});
  final String label;
  final VoidCallback? onTap;
  final bool warn;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: Colors.white,
              border: Border.all(color: warn ? _red : Colors.white, width: 2.5),
            ),
            child: ExcludeSemantics(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const _GLogo(),
                const SizedBox(width: 10),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.w800, fontSize: 15))),
              ]),
            ),
          ),
        ),
      );
}

class _GLogo extends StatelessWidget {
  const _GLogo();
  @override
  Widget build(BuildContext context) => SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(2, 2, s.width - 4, s.height - 4);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4;
    canvas.drawArc(r, -0.5, -1.7, false, p..color = const Color(0xFFEA4335));
    canvas.drawArc(r, -2.2, -1.5, false, p..color = const Color(0xFFFBBC05));
    canvas.drawArc(r, -3.7, -1.6, false, p..color = const Color(0xFF34A853));
    canvas.drawArc(r, -5.3, -0.9, false, p..color = const Color(0xFF4285F4));
    canvas.drawLine(Offset(s.width / 2, s.height / 2), Offset(s.width - 2, s.height / 2), p..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
}

class _Or extends StatelessWidget {
  const _Or({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          const Expanded(child: Divider(color: Colors.white12)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(text, style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.4))),
          const Expanded(child: Divider(color: Colors.white12)),
        ]),
      );
}

class _NoAccountCard extends StatelessWidget {
  const _NoAccountCard({required this.onSignUp});
  final VoidCallback onSignUp;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF4A1520), Color(0xFF1C0A10)]),
          border: Border.all(color: _red.withValues(alpha: 0.55)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚠️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('auth_no_google_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 4),
              Text(context.tr('auth_no_google_body'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onSignUp,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: _goldA, borderRadius: BorderRadius.circular(12)),
                  child: Text(context.tr('auth_signup_now'), style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class _Lang extends StatelessWidget {
  const _Lang({required this.lang, required this.onChanged});
  final String lang;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget opt(String code, String label) => Semantics(
          button: true,
          selected: lang == code,
          child: GestureDetector(
            onTap: () => onChanged(code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: lang == code ? _goldA : Colors.transparent),
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: lang == code ? _ink : Colors.white70)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opt('en', 'EN'), opt('hi', 'हिंदी')]),
    );
  }
}

class _Beams extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    for (final (x, dir) in [(s.width * 0.08, -1.0), (s.width * 0.92, 1.0)]) {
      canvas.save();
      canvas.translate(x, -40);
      canvas.rotate(dir * 0.38);
      final r = Rect.fromLTWH(-45, 0, 90, s.height * 1.1);
      canvas.drawRect(
          r,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66FFECAA), Color(0x00FFECAA)]).createShader(r)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.restore();
      canvas.drawCircle(Offset(x, -24), 22, Paint()..color = const Color(0xCCFFF6D8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    final rnd = math.Random(4);
    for (var i = 0; i < 50; i++) {
      canvas.drawCircle(Offset(rnd.nextDouble() * s.width, s.height * (0.35 + rnd.nextDouble() * 0.3)), 1.1, Paint()..color = const Color(0xFFFFE7A3).withValues(alpha: 0.15 + rnd.nextDouble() * 0.6));
    }
  }

  @override
  bool shouldRepaint(_Beams old) => false;
}

class _SearchList<T> extends StatefulWidget {
  const _SearchList({required this.title, required this.hint, required this.items, required this.label, this.trailing, this.selected, required this.matches});
  final String title;
  final String hint;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? trailing;
  final T? selected;
  final bool Function(T, String) matches;

  @override
  State<_SearchList<T>> createState() => _SearchListState<T>();
}

class _SearchListState<T> extends State<_SearchList<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((x) => _q.isEmpty || widget.matches(x, _q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(9)))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 8), child: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              cursorColor: _goldA,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final x = list[i];
                final on = x == widget.selected;
                return ListTile(
                  minTileHeight: 52,
                  tileColor: on ? _goldA.withValues(alpha: 0.12) : null,
                  title: Text(widget.label(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? _goldB : Colors.white, fontWeight: FontWeight.w700)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.trailing != null) Text(widget.trailing!(x), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                    if (on) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.check_rounded, color: _goldB, size: 18)),
                  ]),
                  onTap: () => Navigator.pop(context, x),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
