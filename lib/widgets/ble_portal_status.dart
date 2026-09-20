import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ble_service.dart';
import '../theme/app_colors.dart';

/// Live Bluetooth link status, independent of saved pairing or cloud status.
class BlePortalStatus extends StatelessWidget {
  const BlePortalStatus({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    return Selector<BleService, bool>(
      selector: (_, ble) => ble.connectionState.isConnected,
      builder: (_, active, _) {
        if (!active) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  AppColors.electricBlue.withValues(alpha: 0.13),
                  Colors.white.withValues(alpha: 0.035),
                  Colors.transparent,
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.bluetooth_connected_rounded,
                  size: 17,
                  color: AppColors.electricBlue,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Bluetooth portal active',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
