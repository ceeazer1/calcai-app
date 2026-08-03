import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/calcai_wordmark.dart';
import 'reset_password_screen.dart';
import 'verify_email_screen.dart';

/// Sign-in screen.
///
/// Follows the product mock: a light band carrying the logo, a large dark
/// rounded panel with a Login / Sign up switch and email + password fields,
/// and a cream primary button. Apple and Google sit below as alternatives.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const _muted = Color(0xFF9A9AA2);

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isSignUp = false;
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openReset() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(initialEmail: _emailCtrl.text.trim()),
      ),
    );
  }

  void _switchMode(bool signUp) {
    if (_isSignUp == signUp) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSignUp = signUp;
      _error = null; // A login error doesn't apply to sign-up, or vice versa.
    });
  }

  /// Validates locally first so an obviously-bad form never costs a round trip
  /// (and never burns a rate-limit slot).
  String? _validate() {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (password.isEmpty) return 'Enter your password.';
    // Only enforced on sign-up; an existing account may predate the rule.
    if (_isSignUp && password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  Future<void> _submitEmail() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final outcome = _isSignUp
        ? await auth.signUpWithEmail(email, password)
        : await auth.signInWithEmail(email, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (outcome) {
      case EmailAuthOutcome.success:
        // The app gate watches AuthService and swaps this screen out itself.
        setState(() => _error = null);
      case EmailAuthOutcome.verificationRequired:
        // Sign-up mails a code instead of returning a session; logging in to
        // an unconfirmed account lands here too.
        setState(() => _error = null);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(email: email),
          ),
        );
      case EmailAuthOutcome.failed:
        setState(() => _error = auth.error ?? 'Something went wrong.');
    }
  }

  Future<void> _handleSocial(String provider) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    String? errorDetail;
    try {
      final auth = context.read<AuthService>();
      if (provider == 'apple') {
        errorDetail = await auth.signInWithApple();
      } else {
        final success = await auth.signInWithGoogle();
        if (!success) errorDetail = auth.error ?? 'Google sign-in failed';
      }
    } catch (_) {
      errorDetail = 'Sign in failed. Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = errorDetail;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SlideTransition(
          position: _slideUp,
          child: FadeTransition(
            opacity: _fadeIn,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                28,
                0,
                28,
                MediaQuery.of(context).viewInsets.bottom + 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Everything sits lower on the screen than it used to.
                  // The full lockup replaces both the square mark and the
                  // heading that used to sit under it.
                  const SizedBox(height: 96),
                  const Center(child: CalcAiWordmark(width: 200)),
                  const SizedBox(height: 52),

                  _Field(
                    label: 'Email',
                    controller: _emailCtrl,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 26),
                  _Field(
                    label: 'Password',
                    controller: _passwordCtrl,
                    focusNode: _passwordFocus,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      _isSignUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: (_) => _submitEmail(),
                    trailing: GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
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

                  if (!_isSignUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _openReset,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Forgot password?',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _muted,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                  // Fixed slot so the button never jumps as messages appear.
                  SizedBox(
                    height: 34,
                    child: Center(
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.3,
                                color: AppColors.error,
                              ),
                            ),
                    ),
                  ),

                  _PrimaryButton(
                    label: _isSignUp ? 'Sign up' : 'Login',
                    loading: _isLoading,
                    onTap: _isLoading ? null : _submitEmail,
                  ),

                  // Replaces the Login / Sign up toggle: one mode is shown at
                  // a time, and this line switches between them.
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => _switchMode(!_isSignUp),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _muted,
                            ),
                            children: [
                              TextSpan(
                                text: _isSignUp
                                    ? 'Already have an account? '
                                    : 'Need an account? ',
                              ),
                              TextSpan(
                                text: _isSignUp ? 'Login' : 'Sign up',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Social options sit well below the primary action.
                  const SizedBox(height: 56),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF2A2A30))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style:
                              GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2A2A30))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SocialButton(
                    icon: Icons.apple_rounded,
                    label: 'Continue with Apple',
                    onTap: _isLoading ? null : () => _handleSocial('apple'),
                  ),
                  const SizedBox(height: 12),
                  _SocialButton(
                    icon: Icons.g_mobiledata_rounded,
                    label: 'Continue with Google',
                    onTap: _isLoading ? null : () => _handleSocial('google'),
                  ),

                  const SizedBox(height: 30),
                  Text(
                    'By continuing, you agree to our Terms of Service',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled underline field, as drawn in the mock.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

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
        // The show/hide control is a suffixIcon rather than a sibling in a
        // Row. As a sibling it stole horizontal space, so the password
        // underline stopped short of the email one; inside the decoration the
        // bar runs the full width and both fields line up.
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          onSubmitted: onSubmitted,
          autocorrect: false,
          enableSuggestions: !obscure,
          style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8),
            suffixIcon: trailing,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 24,
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF3A3A42)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFBFBFC6)),
            ),
          ),
        ),
      ],
    );
  }
}

const _cream = Color(0xFFF6EFEA);

/// Cream, full-width primary action.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cream,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 52,
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF16161A)),
                    ),
                  )
                : Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF16161A),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Outlined alternative sign-in.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3A40)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 21),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
