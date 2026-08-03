import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/calcai_mark.dart';
import '../widgets/code_input.dart';

/// Which part of the reset the user is on.
enum _Step { email, code, password, done }

/// Password reset.
///
/// Four steps: ask for the address, confirm the emailed code, set a new
/// password, then confirm it worked. The code is checked on its own step
/// rather than alongside the new password — being told "that code was wrong"
/// only after typing a password twice is a bad way to find out.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  /// Prefilled from the login form when the user had already typed it.
  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _cream = Color(0xFFF6EFEA);
  static const _muted = Color(0xFF9A9AA2);
  static const _resendCooldown = 45;

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _Step _step = _Step.email;
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _emailLooksValid => RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$')
      .hasMatch(_emailCtrl.text.trim());

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_emailLooksValid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _notice = null;
    });

    await context.read<AuthService>().requestPasswordReset(_emailCtrl.text);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _step = _Step.code;
      // Deliberately unconditional. The backend answers the same way whether
      // or not the address is registered, so promising an email outright would
      // be a lie in one of the two cases.
      _notice = 'If that address has an account, a code is on its way.';
    });
    _startCooldown();
  }

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _notice = null;
    });

    final auth = context.read<AuthService>();
    final ok = await auth.verifyResetCode(_emailCtrl.text, code);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (ok) {
        _step = _Step.password;
      } else {
        _error = auth.error ?? 'That code is not right.';
        // A dead code is worth restarting rather than retyping.
        if (auth.error?.contains('Resend') ?? false) _codeCtrl.clear();
      }
    });
  }

  Future<void> _submitPassword() async {
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    final ok = await auth.resetPassword(
      _emailCtrl.text,
      _codeCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (ok) {
        _step = _Step.done;
      } else {
        _error = auth.error ?? 'Could not reset your password.';
      }
    });
  }

  void _finish() {
    // resetPassword returns a session, so leaving this screen drops the user
    // straight into the app rather than back at sign-in.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String get _title => switch (_step) {
        _Step.email => 'Reset your password',
        _Step.code => 'Check your email',
        _Step.password => 'Set a new password',
        _Step.done => 'Password changed',
      };

  String get _subtitle => switch (_step) {
        _Step.email => "Enter your email and we'll send you a code.",
        _Step.code =>
          'We sent a 6-digit code to ${_emailCtrl.text.trim()}. It expires in '
              '15 minutes.',
        _Step.password => 'Choose a new password for your account.',
        _Step.done =>
          'Your password has been updated and you are signed in.',
      };

  String get _buttonLabel => switch (_step) {
        _Step.email => 'Send code',
        _Step.code => 'Continue',
        _Step.password => 'Save password',
        _Step.done => 'Go to CalcAI',
      };

  VoidCallback? get _buttonAction => switch (_step) {
        _Step.email => _sendCode,
        _Step.code => _checkCode,
        _Step.password => _submitPassword,
        _Step.done => _finish,
      };

  @override
  Widget build(BuildContext context) {
    final done = _step == _Step.done;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                // Nothing to go back to once the password has changed.
                if (!done)
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                    tooltip: 'Back',
                  )
                else
                  const SizedBox(width: 48),
                const Spacer(),
                const CalcAiMark(size: 40),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  28,
                  30,
                  28,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (done) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 68,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Text(
                      _title,
                      textAlign: done ? TextAlign.center : TextAlign.start,
                      style: GoogleFonts.outfit(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _subtitle,
                      textAlign: done ? TextAlign.center : TextAlign.start,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.45,
                        color: _muted,
                      ),
                    ),
                    SizedBox(height: done ? 34 : 30),

                    if (_step == _Step.email)
                      _Labelled(
                        label: 'Email',
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          onSubmitted: (_) => _sendCode(),
                          style: GoogleFonts.inter(
                              fontSize: 15, color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _underline(),
                        ),
                      ),

                    if (_step == _Step.code)
                      CodeInput(
                        controller: _codeCtrl,
                        onCompleted: (_) {
                          if (!_isLoading) _checkCode();
                        },
                      ),

                    if (_step == _Step.password)
                      _Labelled(
                        label: 'New password',
                        child: TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          autofocus: true,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _submitPassword(),
                          style: GoogleFonts.inter(
                              fontSize: 15, color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _underline(
                            suffix: GestureDetector(
                              onTap: () => setState(() => _obscure = !_obscure),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(left: 8, bottom: 6),
                                child: Icon(
                                  _obscure
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 18,
                                  color: _muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (!done) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 38,
                        child: Center(
                          child: _error != null
                              ? Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: AppColors.error,
                                  ),
                                )
                              : (_notice != null
                                  ? Text(
                                      _notice!,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        height: 1.3,
                                        color: _muted,
                                      ),
                                    )
                                  : const SizedBox.shrink()),
                        ),
                      ),
                    ],

                    Material(
                      color: _cream,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _isLoading ? null : _buttonAction,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 52,
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF16161A),
                                      ),
                                    ),
                                  )
                                : Text(
                                    _buttonLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF16161A),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),

                    if (_step == _Step.code) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton(
                          onPressed:
                              _cooldown > 0 || _isLoading ? null : _sendCode,
                          child: Text(
                            _cooldown > 0
                                ? 'Resend code in ${_cooldown}s'
                                : 'Resend code',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _cooldown > 0
                                  ? const Color(0xFF5A5A62)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _underline({Widget? suffix}) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 8),
        suffixIcon: suffix,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 24),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF3A3A42)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFBFBFC6)),
        ),
      );
}

/// Small caption above a field, matching the sign-in screen.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}
