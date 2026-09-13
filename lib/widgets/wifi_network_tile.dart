import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wifi_network.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

/// A premium list tile for displaying a discovered WiFi network.
///
/// Shows the SSID, a neutral Wi-Fi icon with a protection badge, and
/// authentication mode label, all inside a [GlassCard].
class WifiNetworkTile extends StatelessWidget {
  /// Creates a [WifiNetworkTile].
  const WifiNetworkTile({
    super.key,
    required this.network,
    required this.onTap,
    this.isConnecting = false,
    this.isSelected = false,
    this.expandedChild,
  });

  /// The WiFi network to display.
  final WifiNetwork network;

  /// Tap callback.
  final VoidCallback onTap;

  /// Whether a connection attempt to this specific network is ongoing.
  final bool isConnecting;
  final bool isSelected;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: isSelected ? const Color(0xFFB9BEC9) : null,
      borderWidth: isSelected ? 1.25 : 0.5,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      gradient: isSelected
          ? const LinearGradient(
              colors: [Color(0xFF303035), Color(0xFF202024)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            selected: isSelected,
            child: InkWell(
              onTap: isConnecting ? null : onTap,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  // ── Signal Icon ────────────────────────────────────────────
                  Semantics(
                    label: network.isSecured
                        ? 'Protected network'
                        : 'Open network',
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.wifi_rounded,
                              color: AppColors.textSecondary, size: 27),
                          if (network.isSecured)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.shield_outlined,
                                    color: AppColors.textPrimary, size: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // ── SSID & Info ────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          network.ssid,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          network.isSecured ? network.authMode.label : 'Open',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),

                  // ── Connecting indicator ──────────────────────────────────
                  if (isConnecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.electricBlue),
                      ),
                    )
                  else
                    Semantics(
                      label:
                          'Signal strength: ${network.signalLevel} of 4 bars',
                      child: SizedBox(
                        width: 25,
                        height: 22,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(
                              4,
                              (index) => Container(
                                    width: 4,
                                    height: 7.0 + index * 5,
                                    decoration: BoxDecoration(
                                      color: index < network.signalLevel
                                          ? AppColors.textPrimary
                                          : AppColors.surfaceHighlight,
                                      borderRadius: BorderRadius.circular(1.5),
                                    ),
                                  )),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expandedChild ?? const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
