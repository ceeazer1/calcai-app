import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/code_input.dart';
import '../widgets/glass_card.dart';

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
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter all six digits.');
      return;
    }
    final auth = context.read<AuthService>();
    final ble = context.read<BleService>();
    final owner = auth.username;
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

  @override
  Widget build(BuildContext context) {
    final name = context.watch<BleService>().connectedDevice?.name ??
        'your calculator';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pair calculator',
          style: GoogleFonts.outfit(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the code',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "It's on your calculator's screen.",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected_rounded,
                        color: AppColors.electricBlue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

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
                    disabledBackgroundColor: AppColors.surfaceLight,
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
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.background),
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
      ),
    );
  }
}
