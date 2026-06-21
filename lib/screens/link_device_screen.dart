import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import 'scan_screen.dart';

/// First-time onboarding screen — shown when a user logs in but hasn't
/// linked a CalcAI device yet.
///
/// Frames the Bluetooth step as "linking your device" and makes clear that
/// Bluetooth is only used to deliver WiFi credentials to the device.
class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _getStarted() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ScanScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Logo ──────────────────────────────────────
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.accentGradient.createShader(bounds),
                      child: Text(
                        'CalcAI',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const Spacer(flex: 2),

                    // ── Device icon ────────────────────────────────
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradientSoft,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.calculate_rounded,
                        color: AppColors.textPrimary,
                        size: 44,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Headline ──────────────────────────────────
                    Text(
                      'Link Your CalcAI',
                      style: GoogleFonts.outfit(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.1,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "Let's get your CalcAI device set up. We'll connect once via Bluetooth to send your WiFi credentials — after that everything runs through the cloud.",
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.55,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Steps ─────────────────────────────────────
                    const _Step(
                      number: '1',
                      title: 'Power on your CalcAI',
                      subtitle:
                          'Make sure your TI-84 Plus and CalcAI device are turned on and nearby.',
                    ),
                    const SizedBox(height: 16),
                    const _Step(
                      number: '2',
                      title: 'We find your device',
                      subtitle:
                          'We scan via Bluetooth to locate your CalcAI device.',
                    ),
                    const SizedBox(height: 16),
                    const _Step(
                      number: '3',
                      title: 'Add your WiFi network',
                      subtitle:
                          'Your WiFi credentials are sent to the device so it can reach CalcAI.',
                    ),

                    const Spacer(flex: 3),

                    // ── CTA ───────────────────────────────────────
                    GradientButton(
                      label: 'Get Started',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _getStarted,
                      width: double.infinity,
                    ),

                    const SizedBox(height: 10),

                    Center(
                      child: Text(
                        'Bluetooth is only used during this one-time setup',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _Step({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.electricBlue.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.electricBlue.withOpacity(0.25),
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.electricBlue,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
