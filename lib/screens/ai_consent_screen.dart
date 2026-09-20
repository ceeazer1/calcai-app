import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../utils/public_links.dart';

/// Session-keyed gate: only an explicit saved choice advances onboarding.
class AiConsentGate extends StatefulWidget {
  const AiConsentGate({super.key, required this.child});
  final Widget child;

  @override
  State<AiConsentGate> createState() => _AiConsentGateState();
}

class _AiConsentGateState extends State<AiConsentGate> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _ready,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !_ready,
          child: ExcludeSemantics(
            excluding: !_ready,
            child: IgnorePointer(ignoring: !_ready, child: widget.child),
          ),
        ),
        if (!_ready) ...[
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: const ModalBarrier(
                dismissible: false,
                color: Color(0x55000000),
              ),
            ),
          ),
          AiConsentScreen(onComplete: () => setState(() => _ready = true)),
        ],
      ],
    ),
  );
}

class AiConsentScreen extends StatefulWidget {
  const AiConsentScreen({super.key, this.onComplete});
  final VoidCallback? onComplete;

  @override
  State<AiConsentScreen> createState() => _AiConsentScreenState();
}

class _AiConsentScreenState extends State<AiConsentScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _allowed = false;
  String? _error;
  bool? _pendingChoice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthService>().token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (token == null) throw StateError('No session');
      final data = await context.read<CloudService>().readAiConsent(token);
      if (!mounted || context.read<AuthService>().token != token) return;
      if (data['version'] != CloudService.aiConsentVersion) {
        throw const FormatException('App update required');
      }
      _allowed = data['allowed'] == true;
      if (data['reviewed'] == true && widget.onComplete != null) {
        widget.onComplete!();
        return;
      }
    } catch (error) {
      if (mounted) {
        _error = error is AiConsentException
            ? error.message
            : 'Could not load your choice. Please try again.';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(bool allowed) async {
    final token = context.read<AuthService>().token;
    if (token == null || _saving) return;
    setState(() {
      _saving = true;
      _pendingChoice = allowed;
      _error = null;
    });
    try {
      await context.read<CloudService>().saveAiConsent(token, allowed);
      if (!mounted || context.read<AuthService>().token != token) return;
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AiConsentException
              ? error.message
              : 'Your choice was not saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAiOff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI features will be off'),
        content: const Text(
          'Your calculator will not answer AI questions or solve photos. '
          'Pairing and Wi-Fi still work. Turn AI sharing on anytime in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keep AI off'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save(false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onComplete != null) {
      return Dialog(
        key: const ValueKey('ai-consent-popup'),
        backgroundColor: const Color(0xF21A1A20),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                child: Row(
                  children: [
                    const Expanded(child: Text('AI sharing')),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => context.read<AuthService>().signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
              Flexible(child: _buildContent(context)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AI sharing')),
      body: SafeArea(child: Center(child: _buildContent(context))),
    );
  }

  Widget _buildContent(BuildContext context) => _loading
      ? const Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        )
      : ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.auto_awesome_outlined, size: 30),
                ),
                const SizedBox(height: 20),
                Text(
                  'AI, your choice',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 14),
                const Text(
                  'To answer your questions, CalcAI shares your prompts, photos and relevant custom instructions with OpenAI, Google (Gemini), or Anthropic, depending on your selected model.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI sharing is needed for AI answers and photo solving. You can change your choice in Settings.',
                  style: TextStyle(height: 1.5, color: Color(0xFF8E8E96)),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: const Text(
                    'Learn more',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    const Text(
                      'Your choice covers every calculator on your account, even while this app is closed. CalcAI stores activity history and usage with your account and device. Providers process the content under their own policies. Turning sharing off stops new AI requests; content already sent cannot be recalled.',
                      style: TextStyle(height: 1.5, color: Color(0xFF8E8E96)),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            openPublicLink(context, privacyPolicyUrl),
                        child: const Text('Read Privacy Policy'),
                      ),
                    ),
                  ],
                ),
                if (widget.onComplete == null)
                  Text(
                    'Current choice: ${_allowed ? 'AI sharing on' : 'AI sharing off'}',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_error!)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                              final choice = _pendingChoice;
                              if (choice == null) {
                                _load();
                              } else {
                                _save(choice);
                              }
                            },
                      child: const Text('Retry'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : () => _save(true),
                  child: const Text('Allow AI sharing'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving ? null : _confirmAiOff,
                  child: Text(
                    widget.onComplete == null
                        ? 'Turn off AI sharing'
                        : 'Continue with AI off',
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
}
