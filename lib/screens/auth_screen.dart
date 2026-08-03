import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/calcai_mark.dart';

/// Sign-in screen.
///
/// Layout follows the product mock: a light band carrying the logo, then a
/// large dark rounded panel holding the sign-in actions, and a light footer.
///
/// The mock drew email + password fields and a Login/Sign up switch. CalcAI is
/// Sign in with Apple / Google only and registration is closed, so those are
/// not rebuilt here — a segmented control with one option, or a password field
/// with no password behind it, would be decoration pretending to be function.
/// The shape, spacing and cream primary button are kept.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const _panel = Color(0xFF1B1B1D);
  static const _page = Color(0xFFF7F7F5);
  static const _cream = Color(0xFFF6EFEA);

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
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
    super.dispose();
  }

  Future<void> _handleSignIn(String provider) async {
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
        if (!success) {
          errorDetail = auth.error ?? 'Google sign-in failed';
        }
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
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Logo band ─────────────────────────────────────
            FadeTransition(
              opacity: _fadeIn,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CalcAiMark(size: 54),
              ),
            ),

            // ── Dark panel ────────────────────────────────────
            Expanded(
              child: SlideTransition(
                position: _slideUp,
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(38),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome',
                            style: GoogleFonts.outfit(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your calculator, reimagined with AI.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              height: 1.4,
                              color: const Color(0xFF9A9AA2),
                            ),
                          ),
                          const SizedBox(height: 40),

                          _AuthButton(
                            icon: Icons.apple_rounded,
                            label: 'Continue with Apple',
                            background: _cream,
                            foreground: const Color(0xFF16161A),
                            onTap:
                                _isLoading ? null : () => _handleSignIn('apple'),
                          ),
                          const SizedBox(height: 14),
                          _AuthButton(
                            icon: Icons.g_mobiledata_rounded,
                            label: 'Continue with Google',
                            background: Colors.transparent,
                            foreground: Colors.white,
                            border: const Color(0xFF3A3A40),
                            onTap: _isLoading
                                ? null
                                : () => _handleSignIn('google'),
                          ),

                          const SizedBox(height: 22),
                          // Fixed-height slot so the buttons don't jump when a
                          // spinner or an error appears.
                          SizedBox(
                            height: 24,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Color(0xFF9A9AA2),
                                        ),
                                      ),
                                    )
                                  : (_error != null
                                      ? Text(
                                          _error!,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.error,
                                          ),
                                        )
                                      : const SizedBox.shrink()),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────
            Container(
              color: _page,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
              child: Text(
                'By continuing, you agree to our Terms of Service',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF8A8A90),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width pill button, matching the mock's primary action.
class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  border == null ? null : Border.all(color: border!, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: foreground,
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
