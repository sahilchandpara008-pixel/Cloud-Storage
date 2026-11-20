import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'policy_screen.dart';

/// Login choice: Google or email, with the policy links below.
/// Pops `true` once the user is logged in (no longer a guest).
class LoginScreen extends StatefulWidget {
  final String? reason;
  const LoginScreen({super.key, this.reason});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  StreamSubscription<AuthState>? _sub;
  bool _googleBusy = false;
  bool _closed = false;

  /// Email login and the auth listener can both report success: close once.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  @override
  void initState() {
    super.initState();
    // Google login finishes in the browser and comes back through a deep
    // link; close this screen as soon as a real (non-guest) session arrives.
    _sub = sb.auth.onAuthStateChange.listen((s) async {
      final user = s.session?.user;
      if (s.event == AuthChangeEvent.signedIn &&
          user != null &&
          !user.isAnonymous) {
        if (_closed || !mounted) return;
        // Email login is finished by EmailLoginScreen (it already logged
        // the attribution); Google login is finished here.
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          await app.afterExternalLogin();
          _close();
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      await app.signInWithGoogle();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _email() async {
    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EmailLoginScreen()));
    if (ok == true) _close();
  }

  void _policy(String key) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PolicyScreen(policyKey: key)));

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: AppColors.primary,
      decoration: TextDecoration.underline,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF7A2E06),
                    Color(0xFF3A1A0A),
                    Color(0xFF16100C),
                    AppColors.background,
                  ],
                  stops: [0, 0.45, 0.8, 1],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 96,
                          height: 96,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        Config.appName,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        ),
                      ),
                      if (widget.reason != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          widget.reason!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  children: [
                    const Spacer(),
                    _AuthButton(
                      icon: const GoogleLogo(size: 24),
                      label: 'Sign in with google',
                      light: true,
                      busy: _googleBusy,
                      onPressed: _googleBusy ? null : _google,
                    ),
                    const SizedBox(height: 12),
                    _AuthButton(
                      icon: const Icon(Icons.email, size: 26),
                      label: 'Login with email',
                      onPressed: _email,
                    ),
                    const Spacer(flex: 2),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.muted,
                        ),
                        children: [
                          const TextSpan(
                            text:
                                'I understand and agree to the ${Config.appName}\n',
                          ),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: linkStyle,
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => _policy('privacy'),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: linkStyle,
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => _policy('terms'),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool busy;
  final bool light;
  final VoidCallback? onPressed;
  const _AuthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: light ? AppColors.background : AppColors.text,
        backgroundColor: light ? AppColors.text : AppColors.surface,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(
          color: light ? AppColors.text : const Color(0xFF3A3A44),
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: Row(
        children: [
          SizedBox(width: 28, child: icon),
          Expanded(
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

/// Login / create account with email + password. Pops `true` when logged in.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  bool _showPassword = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      if (_create) {
        final done = await app.createAccount(email, _password.text);
        if (!done) {
          if (!mounted) return;
          await _info(
            'Confirm your email',
            'We sent a confirmation link to $email. Open it, then come back and log in.',
          );
          setState(() => _create = false);
          return;
        }
      } else {
        await app.logIn(email, _password.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final msg = friendlyError(e);
      if (mounted) {
        showSnack(
          context,
          msg.contains('already')
              ? 'This email already has an account. Log in instead.'
              : msg,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      showSnack(context, 'Enter your email above first.');
      return;
    }
    try {
      await app.sendPasswordReset(email);
      if (mounted) {
        await _info(
          'Check your email',
          'We sent a password reset link to $email. Open it on this phone to set a new password.',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _info(String title, String text) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  InputDecoration _field(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 16),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Text(
              _create ? 'Create account' : 'Login with email',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 64),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(fontSize: 16),
              decoration: _field('abc@gmail.com'),
              validator: (v) => (v == null || !_emailRe.hasMatch(v.trim()))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: [
                _create ? AutofillHints.newPassword : AutofillHints.password,
              ],
              style: const TextStyle(fontSize: 16),
              decoration: _field(
                'Password',
                suffix: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'At least 6 characters' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _create
                  ? const SizedBox(height: 16)
                  : TextButton(
                      onPressed: _forgot,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _create ? 'Create Account' : 'Login',
                      style: const TextStyle(fontSize: 17),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _create
                      ? 'Already have an account?'
                      : "Don't have an account?",
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AppColors.muted,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _create = !_create),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text(
                    _create ? 'Login' : 'Create Account',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Set a new password after opening the reset link from the email.
Future<void> showNewPasswordDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final password = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Set a new password'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'New password'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (password == null || !context.mounted) return;
  if (password.length < 6) {
    showSnack(context, 'Password must have at least 6 characters.');
    return;
  }
  try {
    await sb.auth.updateUser(UserAttributes(password: password));
    if (context.mounted) showSnack(context, 'Password changed.');
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
  }
}

/// The multi-colour Google "G", drawn so no image file is needed.
class GoogleLogo extends StatelessWidget {
  final double size;
  const GoogleLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = math.pi / 180;
    canvas.drawArc(
      rect,
      -40 * deg,
      -100 * deg,
      false,
      p(const Color(0xFFEA4335)),
    );
    canvas.drawArc(
      rect,
      -140 * deg,
      -80 * deg,
      false,
      p(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      rect,
      140 * deg,
      -95 * deg,
      false,
      p(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      rect,
      45 * deg,
      -45 * deg,
      false,
      p(const Color(0xFF4285F4)),
    );
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke / 4, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
