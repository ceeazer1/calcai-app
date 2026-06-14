import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// Authentication screen — Sign in with Apple/Google.
///
/// This is the first screen new users see. Clean, minimal,
/// with prominent sign-in buttons.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 1200),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
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

    try {
      final auth = context.read<AuthService>();
      bool success;
      if (provider == 'apple') {
        success = await auth.signInWithApple();
      } else {
        success = await auth.signInWithGoogle();
      }
      if (!success && mounted) {
        setState(() => _error = auth.error ?? 'Sign in failed.');
      }
      // _AppGate will react to AuthService state change automatically
    } catch (e) {
      setState(() {
        _error = 'Sign in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ── Logo & Branding ──────────────────────────
                FadeTransition(
                  opacity: _fadeIn,
                  child: Column(
                    children: [
                      // Glow effect behind logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.electricBlue.withOpacity(0.15),
                              Colors.transparent,
                            ],
                            radius: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceLight,
                              border: Border.all(
                                color: AppColors.glassBorder,
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.calculate_rounded,
                              color: AppColors.textPrimary,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.accentGradient.createShader(bounds),
                        child: Text(
                          'CalcAI',
                          style: GoogleFonts.outfit(
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your calculator, supercharged',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── Sign-in buttons ──────────────────────────
                SlideTransition(
                  position: _slideUp,
                  child: FadeTransition(
                    opacity: _fadeIn,
                    child: Column(
                      children: [
                        // Error message
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Sign in with Apple
                        _SignInButton(
                          icon: Icons.apple_rounded,
                          label: 'Sign in with Apple',
                          onTap: _isLoading
                              ? null
                              : () => _handleSignIn('apple'),
                          isPrimary: true,
                        ),
                        const SizedBox(height: 12),

                        // Sign in with Google
                        _SignInButton(
                          icon: Icons.g_mobiledata_rounded,
                          label: 'Sign in with Google',
                          onTap: _isLoading
                              ? null
                              : () => _handleSignIn('google'),
                          isPrimary: false,
                        ),

                        const SizedBox(height: 24),

                        // Loading indicator
                        if (_isLoading)
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // ── Footer ────────────────────────────────────
                FadeTransition(
                  opacity: _fadeIn,
                  child: Text(
                    'By continuing, you agree to our Terms of Service',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom sign-in button with glass effect.
class _SignInButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _SignInButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: isPrimary
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.textOnAccent, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textOnAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              onTap: onTap,
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: AppColors.textPrimary, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
