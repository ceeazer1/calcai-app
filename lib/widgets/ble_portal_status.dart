import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ble_service.dart';
import '../theme/app_colors.dart';

/// Live Bluetooth link status, independent of saved pairing or cloud status.
class BlePortalStatus extends StatefulWidget {
  const BlePortalStatus({super.key});

  @override
  State<BlePortalStatus> createState() => _BlePortalStatusState();
}

class _BlePortalStatusState extends State<BlePortalStatus> {
  bool _closing = false;
  bool _showingOptions = false;

  Future<void> _showOptions() async {
    if (_closing || _showingOptions) return;
    final ble = context.read<BleService>();
    _showingOptions = true;
    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close Bluetooth portal?'),
        content: const Text('You can reopen it on your calculator.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep open'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close portal'),
          ),
        ],
      ),
    );
    _showingOptions = false;
    if (!mounted || close != true || !ble.connectionState.isConnected) return;
    setState(() => _closing = true);
    var closed = false;
    try {
      closed = await ble.closeBlePortal();
    } catch (_) {
      // Keep the live indicator if the calculator did not confirm closure.
    }
    if (!mounted) return;
    setState(() => _closing = false);
    if (!closed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not close the portal. Check Bluetooth and try again.',
          ),
        ),
      );
    }
  }

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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: InkWell(
                onTap: _closing ? null : _showOptions,
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.electricBlue.withValues(alpha: 0.055),
                        Colors.white.withValues(alpha: 0.018),
                        Colors.transparent,
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_closing)
                        const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      else
                        const Icon(
                          Icons.bluetooth_connected_rounded,
                          size: 17,
                          color: AppColors.electricBlue,
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _closing
                              ? 'Closing portal…'
                              : 'Bluetooth portal active',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
