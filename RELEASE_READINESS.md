# CalcAI release readiness — November 15, 2026 successor

Not ready for submission. This is an isolated source successor to the frozen production candidate, implementing Chris's first-release Gemini exclusion and response-style UI request. Original candidate, editable dirty checkout and tested1115 artifacts remain preserved.

## Changes

- Central initial-release provider policy permits OpenAI and Anthropic, including supported gpt5 aliases and custom model IDs. Gemini is absent from offline/live catalogs and the picker, and cannot be added through supported-provider custom dialogs.
- Current and legacy saved Gemini configurations are preserved but unavailable. The app does not replace them or expose Fast funding as available. Style/effort updates omit model, preserving the actual server selection and leaving Custom Instructions accessible. A supported model must be explicitly selected before AI use.
- Backend 409 `provider_unavailable` and 200 `modelAvailability.available=false` are recognized. Server enforcement of all actual inference/default/fallback/BYOK routes is a separate candidate and release gate.
- Google account sign-in is retained. New Google key save/enable/verification is blocked; old masked key metadata is retained for safe removal, with service-level disable support.
- Custom model changes only show success after a newly confirmed accepted save for the same account/device; rejected input and network/server failures retain an error in the dialog.
- Response-style choices show titles and relative usage dots. Answers only: 1/3; Brief explanation: 2/3; Detailed explanation: 3/3. Custom instructions: variable/unfilled. No exact spend is promised. Thinking and unrelated settings descriptions are retained.

## Validation status

Successor validation: full production suite passed 502 tests with two expected bench-only skips; final analysis found no issues; all 17 static source/asset checks passed. All four response-style widget tests passed, including saved-Gemini preference editing, 393-point width, 320-point width and 1.7 text scaling. Normal/small/large-text PNGs were visually reviewed. Earlier repair attempts failed on test SemanticsHandle cleanup; those failures are resolved in the latest source and passing full suite. Final formatting changed whitespace only in two test files after that full run.

The successor's evidence directory records exact command results, timestamps, source hashes and unsigned build/artifact audit. The parent's 482 passes and unsigned build predate these changes and are not reused as successor validation. Widget previews do not establish native phone acceptance. No physical phone install or access is authorized here. Heavy checks pause whenever Master reserves a quiet window for Bench.

The distribution compile must explicitly use `CALCAI_BENCH_C62E=false`, `lib/main.dart`, release mode, correct bundle identifier and current Apple build numbering. Unsigned validation 1.0.0(0) is never uploadable. Reuse the recorded Codemagic CalcAI distribution integration; do not blindly create a signing identity. No local ASC API CLI/credential configuration was found in the documented route; no credentials were exposed or created.

## Release gates

- Retain the successor evidence and verified frozen-source hashes; an unsigned validation build does not establish distribution signing, Apple processing or native acceptance.
- Backend's matching provider exclusion must pass tests and be explicitly approved/deployed before an app release. Confirm Google saved-state preservation and no dispatch through direct/custom/default/fallback/BYOK/admin routes. No silent paid-model substitution.
- Bench's production-profile iPhone/calculator acceptance, Photos save/share/permissions, account/re-pair/fresh-customer checks, actual BLE/power and relevant accessibility/performance evidence remain independently required.
- Current authenticated ASC version/build/review/membership/agreements require a fresh supported session read. Chris reported re-enabling Local browser use after the last disabled inventory. The next capability/session result is recorded separately in evidence; do not treat historical October status as current.
- Verify existing Codemagic distribution signing/export and a unique current build number; inspect the signed archive/IPA and Apple processing. No upload/submission/release without the concrete result and final authorization.
- Provide working reviewer credentials privately in ASC, actual hardware walkthrough/access, truthful content-rights and age declarations, reconciled/published privacy labels, final matching screenshots and reporting/retention/processor evidence.
- Marketing/customer-hub/public policy consistency is handled by their respective owners. Gemini exclusion does not change the intended audience, Google sign-in, SDK privacy declarations or erase historical provider data.
