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
  Widget build(BuildContext context) => _ready
      ? widget.child
      : AiConsentScreen(onComplete: () => setState(() => _ready = true));
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
    } catch (_) {
      if (mounted) _error = 'Could not load your choice. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(bool allowed) async {
    final token = context.read<AuthService>().token;
    if (token == null || _saving) return;
    setState(() {
      _saving = true;
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
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your choice was not saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: widget.onComplete == null,
      title: const Text('AI sharing'),
      actions: widget.onComplete == null
          ? null
          : [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => context.read<AuthService>().signOut(),
                child: const Text('Sign out'),
              ),
            ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 48),
                const SizedBox(height: 24),
                Text(
                  'Choose how you use AI',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                const Text(
                  'When you ask your calculator for AI help, CalcAI sends your question, photos, and relevant custom instructions to the provider for your selected model: OpenAI, Google (Gemini), or Anthropic.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'They process this content to generate answers. CalcAI stores your activity history and usage with your account and device. Provider data handling follows their own policies.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'This choice applies to all calculators on your account, including when this app is closed. You can turn AI sharing off in Settings. New AI requests will stop; content already sent cannot be recalled.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'You can continue without AI and still set up your device, manage Wi-Fi, and use non-AI features.',
                ),
                TextButton(
                  onPressed: () => openPublicLink(context, privacyPolicyUrl),
                  child: const Text('Read Privacy Policy'),
                ),
                if (widget.onComplete == null)
                  Text(
                    'Current choice: ${_allowed ? 'AI sharing on' : 'AI sharing off'}',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, semanticsLabel: _error),
                  TextButton(
                    onPressed: _saving ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : () => _save(true),
                  child: const Text('Allow AI sharing'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _saving ? null : () => _save(false),
                  child: Text(
                    widget.onComplete == null
                        ? 'Turn off AI sharing'
                        : 'Continue without AI',
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    ),
  );
}
