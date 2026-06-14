import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/wifi_network.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

/// A premium list tile for displaying a discovered WiFi network.
///
/// Shows the SSID, signal strength bar-icon, lock indicator, and
/// authentication mode label, all inside a [GlassCard].
class WifiNetworkTile extends StatelessWidget {
  /// Creates a [WifiNetworkTile].
  const WifiNetworkTile({
    super.key,
    required this.network,
    required this.onTap,
    this.isConnecting = false,
  });

  /// The WiFi network to display.
  final WifiNetwork network;

  /// Tap callback.
  final VoidCallback onTap;

  /// Whether a connection attempt to this specific network is ongoing.
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: isConnecting ? null : onTap,
      child: Row(
        children: [
          // ── Signal Icon ────────────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: network.signalColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              network.signalIcon,
              color: network.signalColor,
              size: 22,
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
                Row(
                  children: [
                    Text(
                      network.signalLabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      network.authMode.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Lock / Connecting indicator ────────────────────────────
          if (isConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.electricBlue),
              ),
            )
          else if (network.isSecured)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: AppColors.warning,
                size: 16,
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_open_rounded,
                color: AppColors.success,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}
