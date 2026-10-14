import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/cloud_service.dart';
import '../models/pairing_v2.dart';
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
  late final BleService _ble;
  late final AuthService _auth;
  late final String? _sessionToken;
  late final int _connectionGeneration;
  PairingOffer? _offer;
  PairingApproval? _approval;
  PairingCompletion? _completion;
  bool _restartRequired = false;

  @override
  void initState() {
    super.initState();
    _ble = context.read<BleService>();
    _auth = context.read<AuthService>();
    _sessionToken = _auth.token;
    _connectionGeneration = _ble.connectionGeneration;
  }

  void _checkAttempt() {
    if (!mounted ||
        _auth.token != _sessionToken ||
        _sessionToken == null ||
        _ble.connectionGeneration != _connectionGeneration ||
        !_ble.connectionState.isConnected) {
      throw const PairingV2Exception(
        'Your sign-in or Bluetooth connection changed. Leave setup and reconnect.',
        restartRequired: true,
      );
    }
  }

  Future<void> _submitV2(String code, String owner) async {
    final cloud = context.read<CloudService>();
    _checkAttempt();
    if (_offer == null) {
      if (!await _ble.ensureDeviceVerified()) {
        throw const PairingV2Exception(
          'Could not verify this calculator. Reconnect and try again.',
          restartRequired: true,
        );
      }
      _checkAttempt();
      final mac = _ble.verifiedChallenge?.mac ?? _ble.deviceMac;
      if (mac == null || !isValidMacHex(mac)) invalidPairingReply();
      _offer = await cloud.requestPairingOffer(_sessionToken!, mac);
      _checkAttempt();
    }
    // An ambiguous cloud response retries the same approval, even if the
    // offer has since expired: the backend may return its successful receipt.
    if (_approval == null) {
      _approval = await _ble.approvePairing(_offer!, code);
      _checkAttempt();
    }
    _completion ??= await cloud.claimApprovedDevice(
      _sessionToken!,
      _offer!,
      _approval!,
    );
    _checkAttempt();
    await _ble.completePairing(_offer!, _approval!, _completion!, owner);
    _checkAttempt();
    await _ble.setPersistMac(_offer!.mac);
    _checkAttempt();
    // Only the acknowledged signed completion allows local ownership and the
    // existing Wi-Fi route. Keep the app gate from jumping directly to Home.
    await _auth.addDevice(_offer!.mac, announce: false);
    _checkAttempt();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _confirmingLeave || _restartRequired) return;
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
    try {
      _checkAttempt();
      final version = await ble.negotiatePairing();
      _checkAttempt();
      if (version == 2) {
        await _submitV2(code, owner);
      } else {
        final error = await ble.submitPairingCode(code, owner);
        _checkAttempt();
        if (error != null) throw PairingV2Exception(error);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PairingV2Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _restartRequired = error.restartRequired;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error =
              'Pairing timed out. Keep the calculator connected and tap Retry.',
        );
      }
    } on http.ClientException {
      if (mounted) {
        setState(
          () => _error =
              'Could not reach CalcAI. Keep the calculator connected and tap Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmLeave() async {
    if (_submitting || _confirmingLeave) return;
    _confirmingLeave = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Leave device setup?',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          _approval == null
              ? 'Your device isn’t paired yet. You can start setup again whenever you’re ready.'
              : 'Pairing hasn’t been confirmed on the calculator. Leaving closes this attempt. Reconnect to continue setup.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Leave setup',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Keep setting up',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
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
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
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
                  minHeight: (constraints.maxHeight - 72).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
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
                      enabled:
                          !_submitting &&
                          !_restartRequired &&
                          _approval == null,
                      onCompleted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 16,
                          ),
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
                        onPressed: _submitting || _restartRequired
                            ? null
                            : _submit,
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
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColors.background,
                                  ),
                                ),
                              )
                            : Text(
                                _offer != null ? 'Retry' : 'Pair',
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
          ),
        ),
      ),
    );
  }
}
