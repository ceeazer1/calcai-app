import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// Settings screen — account, device info, and sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _apiKeysExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            // ── Header ──────────────────────────────────
            Text(
              'Settings',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // ── Account Section ─────────────────────────
            _SectionTitle(title: 'Account'),
            const SizedBox(height: 10),
            Consumer<AuthService>(
              builder: (context, auth, _) {
                return GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _SettingsRow(
                        icon: Icons.person_rounded,
                        label: 'Username',
                        value: auth.username ?? 'Not set',
                      ),
                      Divider(
                        color: AppColors.glassBorder,
                        height: 1,
                        indent: 56,
                      ),
                      _SettingsRow(
                        icon: Icons.email_rounded,
                        label: 'Email',
                        value: auth.email ?? 'Not set',
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Device Section ──────────────────────────
            _SectionTitle(title: 'Device'),
            const SizedBox(height: 10),
            Consumer2<AuthService, CloudService>(
              builder: (context, auth, cloud, _) {
                return GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _SettingsRow(
                        icon: Icons.calculate_rounded,
                        label: 'Calculator',
                        value: cloud.deviceName ?? 'TI-84 Plus',
                      ),
                      Divider(
                        color: AppColors.glassBorder,
                        height: 1,
                        indent: 56,
                      ),
                      _MacAddressRow(mac: auth.primaryMac ?? 'N/A'),
                      Divider(
                        color: AppColors.glassBorder,
                        height: 1,
                        indent: 56,
                      ),
                      _SettingsRow(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Plan',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (cloud.planType == 'Pro'
                                    ? AppColors.warning
                                    : AppColors.electricBlue)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            cloud.planType ?? 'Free',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cloud.planType == 'Pro'
                                  ? AppColors.warning
                                  : AppColors.electricBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── API Keys Section (collapsible) ──────────
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Tap to expand/collapse
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _apiKeysExpanded = !_apiKeysExpanded),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.key_rounded,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'API Keys',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Add your own keys for unlimited usage',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _apiKeysExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textTertiary,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Expandable content
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      children: [
                        Divider(color: AppColors.glassBorder, height: 1),
                        _ApiKeyRow(
                          provider: 'OpenAI',
                          icon: Icons.auto_awesome_rounded,
                          onTap: () => _showApiKeyDialog(context, 'OpenAI'),
                        ),
                        Divider(color: AppColors.glassBorder, height: 1, indent: 56),
                        _ApiKeyRow(
                          provider: 'Google',
                          icon: Icons.cloud_rounded,
                          onTap: () => _showApiKeyDialog(context, 'Google'),
                        ),
                        Divider(color: AppColors.glassBorder, height: 1, indent: 56),
                        _ApiKeyRow(
                          provider: 'Anthropic',
                          icon: Icons.psychology_rounded,
                          onTap: () => _showApiKeyDialog(context, 'Anthropic'),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                    crossFadeState: _apiKeysExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 250),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── App Info ────────────────────────────────
            _SectionTitle(title: 'App'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _SettingsRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Version',
                    value: '1.0.0',
                  ),
                  Divider(color: AppColors.glassBorder, height: 1, indent: 56),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        launchUrl(Uri.parse('https://calcai.cc'));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.language_rounded, color: AppColors.textSecondary, size: 20),
                            const SizedBox(width: 14),
                            Text(
                              'calcai.cc',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.open_in_new_rounded,
                              color: AppColors.textTertiary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Sign Out ────────────────────────────────
            GlassCard(
              padding: EdgeInsets.zero,
              onTap: () => _handleSignOut(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Sign Out?',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'You\'ll need to sign in again to access your CalcAI.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthService>().signOut();
              context.read<CloudService>().reset();
            },
            child: Text(
              'Sign Out',
              style: GoogleFonts.inter(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context, String provider) {
    final controller = TextEditingController();
    final cloud = context.read<CloudService>();
    final auth = context.read<AuthService>();
    final hasSaved = cloud.hasApiKey(provider);
    final last4 = cloud.apiKeyLast4(provider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          '$provider API Key',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasSaved) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Active  •••${last4 ?? ''}',
                      style: GoogleFonts.inter(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Replace with a new key or remove the existing one.',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
              ),
            ] else
              Text(
                'Enter your $provider API key for unlimited usage.',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'sk-...',
                hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (hasSaved)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (auth.token != null) {
                  await cloud.deleteApiKey(auth.token!, provider);
                }
              },
              child: Text('Remove', style: GoogleFonts.inter(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) return;
              Navigator.pop(ctx);
              if (auth.token != null) {
                final ok = await cloud.saveApiKey(auth.token!, provider, key);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Invalid API key. Please check and try again.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            trailing!
          else if (value != null)
            Text(
              value!,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _MacAddressRow extends StatefulWidget {
  final String mac;
  const _MacAddressRow({required this.mac});

  @override
  State<_MacAddressRow> createState() => _MacAddressRowState();
}

class _MacAddressRowState extends State<_MacAddressRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.memory_rounded, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 14),
            Text(
              'MAC Address',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _revealed ? widget.mac : '••:••:••:••:••:••',
                key: ValueKey(_revealed),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _revealed
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppColors.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiKeyRow extends StatelessWidget {
  final String provider;
  final IconData icon;
  final VoidCallback onTap;

  const _ApiKeyRow({
    required this.provider,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        final hasSaved = cloud.hasApiKey(provider);
        final last4 = cloud.apiKeyLast4(provider);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      provider,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (hasSaved) ...[
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '•••${last4 ?? ''}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.success,
                      ),
                    ),
                  ] else
                    Text(
                      'Not set',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
