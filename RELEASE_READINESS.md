# CalcAI App Store readiness — September 21, 2026

**Prepared for review; not yet ready to submit. Nothing has been submitted to App Review.**

## September 21 launch preparation update

- Owner chose a free download, United States only, with paid Pro deferred. Price and territory are saved in App Store Connect; future territories were not enabled.
- Owner approved the first verified calculator link as the start of a one-time 30-day welcome allowance, using the finite Pro daily budget. No payment or auto-renewal. Personal keys remain separate; Free applies afterward.
- Backend welcome enforcement deployed as `b98d3953-8a3f-45c7-a582-3ff37b0f8327`. All 226 backend tests passed. Downloaded deployment exactly matches the reviewed compiled bundle; unauthenticated claim/status probes returned 401. No customer's account was altered for testing. Existing photo-funding optimization is preserved.
- App commit `d962ccd` shows Welcome and the local expiry date in Settings, and refreshes usage at welcome expiry before the normal daily reset. All 119 app tests, analysis and 14 preflight checks pass. Signed build 95 completed and uploaded **1.0.0 (1096)** successfully, delivery `b981b9be-97a4-45fd-bc05-d3e8a9daef19`. It was not yet listed in the App Store build picker at the final check; no older build was selected.
- Store description and reviewer business-model explanation now reflect the welcome allowance. Reviewer contact was supplied by the owner and saved privately in App Store Connect; do not put their phone number in this repository.
- Eight screenshot drafts were generated from the real Flutter widgets at iPhone 1242×2688 and iPad 2048×2732, using isolated sample data. Visual checks passed. These are not native device captures and are not uploaded. Reproducible opt-in harness: `tool/store_screenshots_test.dart`. Capture Settings version/native status bars from the final native build before using a final set.
- Deployed production code was rechecked: explicit AI permission enforcement, scoped expiring photo links, photo cleanup and Apple revocation exist. Older September 13 audit statements describing them as undeployed are superseded. Both unpublished policy drafts now reflect this. Provider agreements, legacy orphan files, backup retention and live disposable-account deletion remain unverified.
- Owner prefers an alternative to supplying hardware. Prepare a physical iPhone/calculator walkthrough video plus a real reviewer account; Apple's guidance allows video for hard-to-replicate hardware features but does not guarantee hardware will never be requested. See `APP_REVIEW_WALKTHROUGH.md`.

- Build 1096's 18 archived privacy manifests were reviewed in the CI log. Google Sign-In adds Name, Phone Number, Coarse Location, Other Usage Data and Other Data declarations beyond the app manifest. All 18 declare no tracking; provider practices still need reconciliation. See the updated privacy worksheet in `APP_STORE_SUBMISSION.md`.
- **Provider eligibility is unresolved:** owner confirmed under-18 users and wants Gemini retained. Both Gemini API age requirements and Google Cloud service terms 20(d) restrict this audience. No provider was silently removed and no false 18+ declaration was made. Written Google permission/applicable agreement or a provider decision is needed before public launch.

Build 1096: https://codemagic.io/app/6a2e41d4ebda7ed4a91bd2e7/build/6ab0c3ad1b49999129f21b17

## Earlier cleanup verified

- App Store record: **CalcAI Link**, Apple ID `6780132992`, bundle `com.calcai.calcaiApp`.
- Existing TestFlight build **1094**, source `8c5a4c1`, uploaded successfully on September 20. The owner confirmed on September 21 that pairing, Wi-Fi, AI sharing and leaving Wi-Fi mode work on iPhone with firmware **1.3.1**. This is owner-reported hardware validation, not an automated hardware test.
- September 21 cleanup replaces the template white launch screen and 1-pixel placeholder assets with existing CalcAI artwork on the app's dark background. Removes the obsolete Fast mode preview. Keeps the actively used setup regression preview outside production. The existing untracked website screenshot tool is preserved.
- 117 Flutter tests passed; analysis has no issues; all 14 source/asset preflight checks passed. Signed cleanup candidate **1.0.0 (1095)** built from `55b8822` and uploaded to Apple successfully on September 21. It was not yet available in the App Store build picker at the last check, and has not been selected or submitted.
- Production imports are checked to exclude tool/test fixtures. CI targets `lib/main.dart`, validates signing and privacy manifests, and now exports an inventory of the actual archived app/SDK privacy manifests. Build 1095 recorded **18 manifests**. The full report still needs review; Chrome blocked the artifact download, so only successful report generation was verified from CI logs.
- App Store Connect draft saved: subtitle, Utilities category, promotional text, description, keywords, Support URL, Marketing URL, copyright and setup review notes. Existing store name retained. Release changed to **manual**.
- Public `https://calcai.cc/help` loads in Chrome and includes support contacts. Its setup instructions still describe the older configuration portal and should be updated for the iOS Bluetooth flow.

## Items to finish before Add for Review

| Item | Current evidence | Next action |
| --- | --- | --- |
| Launch allowance | First verified link starts 30 days at the finite Pro AI limit; backend enforcement deployed. Free afterward, no billing. | Verify the next native candidate's Welcome/date display. Paid Pro deferred; no subscription setup needed for this launch. |
| Public privacy policy | A fresh live HTTPS response on September 21 still claims CalcAI does not receive full personal API keys. The app sends them to its backend. Local website drafts already correct this, but remain unpublished pending retention/provider review. | Finish the existing privacy release review and publish the accurate policy. See `../website/content/privacy.js` and `../outputs/privacy-audit/RELEASE-REVIEW.md`. Do not deploy the whole dirty website checkout from this app cleanup. |
| App Privacy questionnaire | App Store Connect currently lists only Name and Email Address, both with setup incomplete. | Reconcile against the archived SDK report and actual backend/provider behavior. At minimum assess account/device IDs, prompts/notes/instructions/answers, photos and usage interactions. Complete purpose/linkage/tracking answers accurately. Name is local in the app; verify SDK/backend retention before keeping or removing it. |
| Account deletion / retention | UI, Apple reauthorization/revocation handling and session cleanup exist and have automated coverage. A live deletion of a disposable Apple-linked account was not performed in this audit. | Verify deletion and Apple revocation with a disposable account, plus retained photos/history/keys. Follow the existing coordinated privacy release document for any unresolved storage gaps. |
| Review access | Contact saved. No dedicated reviewer login or real hardware walkthrough attached yet; owner prefers video instead of supplying hardware. | Create a working review account and enter its credentials directly in App Store Connect. Record the physical-device walkthrough; Apple may request more access. |
| Screenshots | Eight visually checked drafts from real widgets and local sample data; no uploads. | Capture/verify final native screens before upload. See the September 21 update above. |
| Age rating / rights | Age rating and content-rights setup are incomplete. | Answer for the actual AI content and moderation capabilities. Do not claim a Kids category, parental controls or content filtering that does not exist. |
| Availability / business details | Free price and United States-only availability saved. Mac distribution remains enabled by default but untested; Vision Pro incompatible. | Resolve Mac compatibility/distribution, content rights and required agreements. No EU territories enabled. |
| Current candidate | Build 1096 compiled, passed signing/archive checks and uploaded with no errors. No on-device Welcome/expiry check performed here. | Verify the new TestFlight launch and Welcome display, attach processed 1096, then resolve remaining release checks. |

Build evidence: [Codemagic build 94](https://codemagic.io/app/6a2e41d4ebda7ed4a91bd2e7/build/6ab0bd5ff8bf402a334415f7), completed in 5m 29s; Apple delivery `01edb42c-f4e2-46e9-9d9f-ea4c1d574847`. The existing CocoaPods fallback for flutter_secure_storage emits a future Swift Package Manager compatibility warning; it did not fail this build.

## Evidence and scope

The earlier cleanup changed only the native launch screen. The subsequent approved launch preparation changes backend welcome enforcement and the app's plan/usage presentation. Firmware is unchanged. Tests simulate services and do not establish live account deletion, processor retention, legal compliance, or App Review acceptance.

Existing app version is `1.0.0`; App Store Connect displays the release as `1.0`. CI obtains a fresh build number from Apple. iOS 15 minimum; iPhone and iPad remain enabled. The encrypted-transport declaration and existing Apple/Google sign-in configuration remain unchanged.

Apple references checked September 21:
- [Review guidelines: reviewer access, purchases, AI sharing and account deletion](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

For Pro, evaluate the actual distribution and feature model against 3.1.1, 3.1.3(f) and 3.1.4. Hardware or companion-app exceptions are not blanket approval for any subscription design; no eligibility claim was made in this preparation.
