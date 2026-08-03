import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/calcai_mark.dart';

/// Confirms the six-digit code emailed after sign-up.
///
/// Signing up no longer hands back a session — the backend mails a code and
/// withholds the token until the address is proven — so this screen stands
/// between sign-up and the rest of the app.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _panel = Color(0xFF1B1B1D);
  static const _page = Color(0xFFF7F7F5);
  static const _cream = Color(0xFFF6EFEA);
  static const _muted = Color(0xFF9A9AA2);

  /// Long enough that mashing Resend can't be used to spam someone's inbox.
  static const _resendCooldown = 45;

  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _isLoading = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _notice = null;
    });

    final auth = context.read<AuthService>();
    final ok = await auth.verifyEmailCode(widget.email, code);
    if (!mounted) return;

    if (ok) {
      // The app gate watches AuthService, so it swaps this screen out itself.
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _isLoading = false;
      _error = auth.error ?? 'Could not confirm the code.';
    });
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _isLoading) return;
    setState(() {
      _error = null;
      _notice = null;
    });
    await context.read<AuthService>().resendVerificationCode(widget.email);
    if (!mounted) return;
    setState(() => _notice = 'Sent. Check your inbox — and your spam folder.');
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Color(0xFF44444A)),
                  tooltip: 'Back',
                ),
                const Spacer(),
                const CalcAiMark(size: 40),
                const Spacer(),
                const SizedBox(width: 48), // balances the back button
              ],
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
                ),
                padding: const EdgeInsets.fromLTRB(26, 34, 26, 0),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Check your email',
                        style: GoogleFonts.outfit(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'We sent a 6-digit code to ${widget.email}. '
                        'It expires in 15 minutes.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.45,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 30),

                      TextField(
                        controller: _codeCtrl,
                        focusNode: _codeFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (v) {
                          // Submit as soon as the sixth digit lands, so the
                          // SMS/email autofill path needs no extra tap.
                          if (v.length == 6 && !_isLoading) _verify();
                        },
                        onSubmitted: (_) => _verify(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.robotoMono(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 10,
                          color: Colors.white,
                        ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '------',
                          hintStyle: TextStyle(
                            color: Color(0xFF44444C),
                            letterSpacing: 10,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF3A3A42)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFBFBFC6)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        height: 34,
                        child: Center(
                          child: _error != null
                              ? Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: AppColors.error,
                                  ),
                                )
                              : (_notice != null
                                  ? Text(
                                      _notice!,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        height: 1.3,
                                        color: _muted,
                                      ),
                                    )
                                  : const SizedBox.shrink()),
                        ),
                      ),

                      Material(
                        color: _cream,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _isLoading ? null : _verify,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFF16161A),
                                        ),
                                      ),
                                    )
                                  : Text(
                                      'Confirm',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF16161A),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),
                      Center(
                        child: TextButton(
                          onPressed: _cooldown > 0 ? null : _resend,
                          child: Text(
                            _cooldown > 0
                                ? 'Resend code in ${_cooldown}s'
                                : 'Resend code',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _cooldown > 0
                                  ? const Color(0xFF5A5A62)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
