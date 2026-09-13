import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/code_input.dart';

/// Claims a calculator using the six digits shown on its own screen.
///
/// Reading the code off the calculator is what proves the person setting it up
/// is holding it. Being in Bluetooth range never proved that, which is why an
/// unclaimed device used to take Wi-Fi credentials from whoever connected first.
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({super.key});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  bool _confirmingLeave = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _confirmingLeave) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter all six digits.');
      return;
    }
    final auth = context.read<AuthService>();
    final ble = context.read<BleService>();
    // The email is what the backend stores as the device owner (sess.sub),
    // so the copy in the calculator's flash matches its record.
    final owner = auth.email;
    if (owner == null || owner.isEmpty) {
      setState(() => _error = 'Sign in first.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await ble.submitPairingCode(code, owner);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = err;
      _codeCtrl.clear();
    });
  }

  Future<void> _confirmLeave() async {
    if (_submitting || _confirmingLeave) return;
    _confirmingLeave = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Leave device setup?',
            style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        content: Text(
            'Your device isn’t paired yet. You can start setup again whenever you’re ready.',
            style: GoogleFonts.inter(
                fontSize: 14, height: 1.5, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Leave setup',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep setting up',
                  style: TextStyle(color: AppColors.textPrimary))),
        ],
      ),
    );
    if (!mounted) return;
    if (leave == true) {
      await context.read<BleService>().disconnect();
      if (mounted) Navigator.pop(context, false);
    } else {
      _confirmingLeave = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),
              tooltip: 'Back',
              onPressed: _submitting ? null : _confirmLeave,
            ),
            centerTitle: true,
            title: Text(
              'Device setup',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 72)
                                .clamp(0.0, double.infinity)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Enter code',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Enter the code shown on your calculator.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 32),
                            CodeInput(
                              controller: _codeCtrl,
                              enabled: !_submitting,
                              onCompleted: (_) => _submit(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppColors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _submitting ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.textPrimary,
                                  disabledBackgroundColor:
                                      AppColors.surfaceLight,
                                  foregroundColor: AppColors.background,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                              AppColors.background),
                                        ),
                                      )
                                    : Text(
                                        'Pair',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
          ),
        ));
  }
}
