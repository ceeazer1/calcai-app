# Fast mode — September 16, 2026

Implemented locally, not deployed or included in TestFlight build 1084.

The Home screen has a separate, off-by-default Fast mode switch. It does not
change the model, response length or thinking effort. The former Fast thinking
preset is labelled Minimal to distinguish the two settings.

Supported provider routing:
- GPT-5.6 Sol, Terra and Luna: `service_tier: priority` on Responses and Chat
  Completions, including photo requests and streaming.
- Claude Opus 5 and 4.8: `speed: fast` plus
  `anthropic-beta: fast-mode-2026-02-01`. Anthropic must grant the key access.
  Opus 4.8 remains available through the existing custom-model setting.
- Gemini Priority exists, including 3.1 Pro Preview, 3.5 Flash/Flash-Lite and
  3.6 Flash. Its current documentation specifies the Interactions API. CalcAI
  uses generateContent, so its switch is unavailable rather than sending an
  unverified parameter. Migrating Gemini is separate work.

This version requires an enabled personal provider key. Shared CalcAI keys
never receive a paid-speed parameter. Unsupported/custom IDs are not inferred
by prefix. Model changes reset opt-in; style/thinking changes preserve it.
Server ownership, consent and genuine-device checks remain in force.

The setting requests a provider tier; it does not guarantee a response time.
OpenAI can downgrade requests to standard; Claude may reject requests when
access/capacity is unavailable. No automatic paid account upgrade is performed.
Live paid provider calls have not been used to measure performance.

Sources:
- https://developers.openai.com/api/docs/guides/fast-mode
- https://developers.openai.com/api/docs/pricing
- https://platform.claude.com/docs/en/build-with-claude/fast-mode
- https://ai.google.dev/gemini-api/docs/priority-inference

Development preview: `flutter build web --target tool/fast_mode_preview.dart
--output build/fast-mode-preview --no-wasm-dry-run`. This uses the real dashboard
and card with in-memory test services; it is not imported by lib/main.dart.
Serve that output locally. Production CI continues to target lib/main.dart.
