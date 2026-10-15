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
          child: _PortalSurface(
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
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
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

/// Only mounted while the iOS link is active. Repaint the small surface, not Home.
class _PortalSurface extends StatefulWidget {
  const _PortalSurface({required this.child});
  final Widget child;

  @override
  State<_PortalSurface> createState() => _PortalSurfaceState();
}

class _PortalSurfaceState extends State<_PortalSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _reduceMotion = true;
  bool _tickerEnabled = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _tickerEnabled = TickerMode.of(context);
    _updateAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateAnimation();
  }

  void _updateAnimation() {
    if (_foreground && _tickerEnabled && !_reduceMotion) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x24F4F6FF),
                    Color(0x12FFFFFF),
                    Color(0x0AE8ECF5),
                  ],
                ),
                border: Border.all(color: const Color(0x29FFFFFF)),
              ),
            ),
          ),
          if (!_reduceMotion)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (_, _) {
                    final offset = -3 + 6 * _shimmer.value;
                    return DecoratedBox(
                      key: const ValueKey('ble-portal-shimmer'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(offset - 1, -0.3),
                          end: Alignment(offset + 1, 0.3),
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0x14FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          widget.child,
        ],
      ),
    ),
  );
}
