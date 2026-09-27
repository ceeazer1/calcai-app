# CalcAI release readiness — September 27, 2026

**Not ready for public submission. No App Review submission or public release has been made.** This current checklist replaces earlier chronological checklists. Automated checks are evidence, not a guarantee of security or App Review acceptance.

## Launch decisions

- CalcAI Link, Apple ID `6780132992`, bundle `com.calcai.calcaiApp`, version `1.0.0` (store draft `1.0`).
- Free download, United States only, iPhone/iPad, iOS 15 minimum. Mac and Vision Pro distribution disabled. Manual release.
- First verified calculator link starts one 30-day welcome allowance at the finite Pro daily AI limit. Free afterward; no payment, renewal or paid Pro checkout in this release. Personal API keys remain optional.
- Owner intends the app for under-18 students and wants Gemini retained. Google's sales reply is not authorization; the owner sent a focused follow-up.
- Owner chose to retain saved questions, answers and photos until the user clears them or deletes the account. The corrected policy was published September 27; backup/provider retention remains separately qualified. Owner will provide the physical setup video later.

## September 26 app fixes and verification

- Ignore device-list responses from a signed-out or replaced session. Notify consumers immediately on logout, serialize persisted auth writes/cleanup and invalidate the restore marker before Keychain deletion.
- Bound device lookup to 15 seconds and complete cloud responses (including stalled response bodies) to 20 seconds. Never automatically replay a timed-out mutation.
- Load History, Notes and Settings only on first visit; retain their state afterward. Suspend animation tickers in hidden tabs. This removes unnecessary initial requests; physical-device launch-time and battery improvements have not been measured.
- Restrict remote photo URLs to HTTPS on the expected host, port and image-view route, without URL credentials.
- **126 Flutter tests passed**, analysis found no issues, all **14 source/asset preflight checks passed**. Regression cases include stale logout responses, delayed storage writes, failed Keychain deletion, request deadlines, lazy tab requests and unsafe image URLs.
- September 27 backend follow-up: **280 tests passed**. Fixed recent-history pagination and bounded body reads, then removed the photo prompt's unconditional “never refuse” instruction while preserving calculator formatting. Both changes are deployed; no firmware changes were made. Prompt wording is not a verified moderation system.
- OSV queried for **118 locked Dart Pub dependencies**: no advisories returned. This does not cover native Pods, the Flutter engine, undisclosed vulnerabilities or runtime configuration. Evidence: workspace `outputs/app-release-audit/2026-09-26/dependency-advisories.json`.
- Source review confirmed native HTTPS transport, no arbitrary HTTP loads, Keychain session storage, scoped image authorization, session invalidation, AI consent gates and finite allowance handling. This was not an independent penetration test.

## Build and App Store evidence

- Latest selected store build: **1.0.0 (1097)** from `2548a7c`, saved September 27. Apple processing is Complete, and the build is assigned to the existing internal TestFlight group. The owner tested 1096 and account deletion; targeted iPhone regression testing of 1097 is still required.
- [Build 1096](https://codemagic.io/app/6a2e41d4ebda7ed4a91bd2e7/build/6ab0c3ad1b49999129f21b17) passed signed archive checks and uploaded; delivery `b981b9be-97a4-45fd-bc05-d3e8a9daef19`.
- [Build 1097](https://codemagic.io/app/6a2e41d4ebda7ed4a91bd2e7/build/6ab85295aff05f520f46a326) compiled with Xcode 26.6, passed signing/archive checks, and uploaded successfully in 5m 5s. Apple delivery `d317f286-f924-4700-9578-e003fb59ff32`. No App Review submission.
- All 18 archived app/SDK privacy manifests in 1097 were reviewed; none declares tracking. Provider contractual practices remain a separate check.
- Store copy, subtitle, category, URLs, price, territory and reviewer contact are saved. Private contact information and review credentials must never be committed here.
- Six screenshots uploaded: Home, Notes and Wi-Fi for iPhone 1242×2688 and iPad 2048×2732. They render real Flutter widgets using isolated sample data, not physical-device captures.
- Thirteen App Privacy categories have complete saved draft answers. All linked; no tracking. User ID, Device ID and Other Data include functionality/analytics; Other Usage Data is analytics; remaining categories functionality. **Privacy label is not published.**

## Remaining release gates

| Gate | Missing evidence or action |
| --- | --- |
| Gemini eligibility | Applicable written Google authorization/agreement for the intended under-18 audience, or an explicit provider decision. Do not assume a Vertex migration solves this. |
| Public privacy policy | **Published September 27:** personal-key processing, AI sharing, photo access/deletion, owner-selected saved-content retention, and setup/support instructions. Privacy, Terms, FAQ and Help were deployed in isolation; other published routes were preserved byte-for-byte in the release artifact. Provider and backup details remain explicitly qualified. |
| Retention and processors | Verify the owner's retention choice against actual logs, backups, legacy orphan photos, provider retention/billing tiers and historical Cloudflare AI Gateway records. Gateway settings and deployed request overrides were verified September 27; see below. Account-deletion UI testing alone does not establish that all processors/backups erase everything immediately. |
| History at scale | **Fixed and deployed September 27.** All R2 metadata pages are examined, newest entries selected, and bodies read in batches of 16 with early stopping. Tests include 2,501 records, configuration-only pages, malformed/missing entries and auth/ownership gates. Metadata scans remain linear in history size; a persistent activity index is a future scaling improvement. |
| Review access | Dedicated functioning review account plus a real iPhone/calculator setup walkthrough. Owner will record it; see `APP_REVIEW_WALKTHROUGH.md`. Apple may still request hardware or additional access. |
| Age rating and content rights | Complete factual declarations once eligibility and content behavior are assessed. The unconditional-answer prompt was removed September 27; age-appropriate content behavior still needs assessment. Do not claim verified child-safe moderation, parental controls or age assurance. |
| New native candidate | Build 1097 uploaded and archive privacy report verified; test sign-in/out, relaunch, Home/tab navigation, slow/offline recovery, consent, pairing and Wi-Fi on iPhone. Previous 1096 testing is not testing of these changes. |
| Physical accessibility/performance | VoiceOver, large text, Reduce Motion and representative iPhone/iPad profiling still need native checks; unit tests do not measure these. |

## Scope and operational limits

Source/asset checks exclude preview/test fixtures from the shipping entry point, validate native icons/launch artwork/privacy declarations and prohibit embedded private keys or TLS bypasses. These checks cannot certify all runtime behavior. Photo export creates app-temporary files; copies deliberately saved/shared outside CalcAI are outside account deletion. Confirm app-cache cleanup and disclose retention accurately. The September 26 R2 lifecycle check found only a seven-day abort rule for incomplete multipart uploads; no completed-object expiry. The Wrangler OAuth token could not read AI Gateway settings, but authenticated dashboard review on September 27 succeeded. Gateway defaults retain up to 100,000 logs with oldest-first eviction and no fixed age shown; the deployed provider paths override payload logging off and caching off. Metered calls preserve metadata for billing and set one gateway attempt. Existing tests verify the privacy headers; historical logs and provider-side retention were not inspected or purged. Gateway authentication is enabled, log export is not enabled, and the unified-billing Zero Data Retention toggle is off (not proof of BYOK provider terms). Current API version is `f18b327e-9db7-4e0c-8e9a-d282f47cb4dc`; website deployment is `e3b035ea-1b1b-401e-b4af-4232a063a91a`. The live policy is dated September 27 and corrects the old full-key and six-month-purge claims. Deployment source, preserved bindings/runtime settings, staging manifest and public-page checks are recorded in workspace `outputs/app-release-audit/2026-09-27/`.

Provider permission, final policy, review access, age/rights declarations and new-candidate validation must be resolved before Add for Review. Do not silently change the launch audience, remove a requested provider, claim unsupported moderation, or deploy the entire dirty website checkout.

Official sources rechecked September 26:
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Gemini API terms](https://ai.google.dev/gemini-api/terms)
- [Google Cloud service terms](https://cloud.google.com/terms/service-terms)
- [OSV API scope](https://google.github.io/osv.dev/api/)
