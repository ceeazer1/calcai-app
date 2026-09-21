# CalcAI App Store readiness — September 21, 2026

**Prepared for review; not yet ready to submit. Nothing has been submitted to App Review.**

## Completed and verified

- App Store record: **CalcAI Link**, Apple ID `6780132992`, bundle `com.calcai.calcaiApp`.
- Existing TestFlight build **1094**, source `8c5a4c1`, uploaded successfully on September 20. The owner confirmed on September 21 that pairing, Wi-Fi, AI sharing and leaving Wi-Fi mode work on iPhone with firmware **1.3.1**. This is owner-reported hardware validation, not an automated hardware test.
- September 21 cleanup replaces the template white launch screen and 1-pixel placeholder assets with existing CalcAI artwork on the app's dark background. Removes the obsolete Fast mode preview. Keeps the actively used setup regression preview outside production. The existing untracked website screenshot tool is preserved.
- 117 Flutter tests passed; analysis has no issues; all 14 source/asset preflight checks passed. The cleanup needs its new signed iOS build before selecting the release candidate.
- Production imports are checked to exclude tool/test fixtures. CI targets `lib/main.dart`, validates signing and privacy manifests, and now exports an inventory of the actual archived app/SDK privacy manifests.
- App Store Connect draft saved: subtitle, Utilities category, promotional text, description, keywords, Support URL, Marketing URL, copyright and setup review notes. Existing store name retained. Release changed to **manual**.
- Public `https://calcai.cc/help` loads in Chrome and includes support contacts. Its setup instructions still describe the older configuration portal and should be updated for the iOS Bluetooth flow.

## Items to finish before Add for Review

| Item | Current evidence | Next action |
| --- | --- | --- |
| Pro purchase model | Owner confirmed a 30-day grace period, then Free or paid Pro, with optional personal API keys. Purchase location is undecided. No StoreKit purchasing flow exists in the app. | Decide and implement how Pro is bought/renewed. Verify grace-period eligibility, start/end and server enforcement. Add the final business-model explanation to review notes. Do not describe this as an Apple auto-renewing trial unless that is actually implemented. |
| Public privacy policy | A fresh live HTTPS response on September 21 still claims CalcAI does not receive full personal API keys. The app sends them to its backend. Local website drafts already correct this, but remain unpublished pending retention/provider review. | Finish the existing privacy release review and publish the accurate policy. See `../website/content/privacy.js` and `../outputs/privacy-audit/RELEASE-REVIEW.md`. Do not deploy the whole dirty website checkout from this app cleanup. |
| App Privacy questionnaire | App Store Connect currently lists only Name and Email Address, both with setup incomplete. | Reconcile against the archived SDK report and actual backend/provider behavior. At minimum assess account/device IDs, prompts/notes/instructions/answers, photos and usage interactions. Complete purpose/linkage/tracking answers accurately. Name is local in the app; verify SDK/backend retention before keeping or removing it. |
| Account deletion / retention | UI, Apple reauthorization/revocation handling and session cleanup exist and have automated coverage. A live deletion of a disposable Apple-linked account was not performed in this audit. | Verify deletion and Apple revocation with a disposable account, plus retained photos/history/keys. Follow the existing coordinated privacy release document for any unresolved storage gaps. |
| Review access | Review account, contact details and physical-access arrangements are blank. | Supply a dedicated functioning account securely in App Store Connect, reviewer contact details, and a way to exercise the hardware features. A walkthrough can supplement access. Do not use a hidden reviewer-only bypass. |
| Screenshots | No screenshots uploaded in the inspected iPhone slot; iPad is supported. | Capture the final native build without customer data or a demo banner; upload Home, Wi-Fi management and Notes/History, plus the required iPad set. Use Media Manager's accepted device dimensions. |
| Age rating / rights | Age rating and content-rights setup are incomplete. | Answer for the actual AI content and moderation capabilities. Do not claim a Kids category, parental controls or content filtering that does not exist. |
| Availability / business details | Pricing and territories have not been verified. App Information currently shows non-trader status. | Confirm price/territories and whether the existing trader declaration is accurate for this commercial product. The owner must supply any legally required business details or agreements. |
| Cleanup candidate | Launch-screen change needs a new signed candidate. | Verify the new TestFlight launch appearance, attach the final processed build, then resolve all remaining App Store checks. |

## Evidence and scope

The app's runtime and protocol remain unchanged by this cleanup; the shipping change is the native launch screen. Backend and firmware files were not modified. Tests simulate services and do not establish live account deletion, processor retention, legal compliance, or App Review acceptance.

Existing app version is `1.0.0`; App Store Connect displays the release as `1.0`. CI obtains a fresh build number from Apple. iOS 15 minimum; iPhone and iPad remain enabled. The encrypted-transport declaration and existing Apple/Google sign-in configuration remain unchanged.

Apple references checked September 21:
- [Review guidelines: reviewer access, purchases, AI sharing and account deletion](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

For Pro, evaluate the actual distribution and feature model against 3.1.1, 3.1.3(f) and 3.1.4. Hardware or companion-app exceptions are not blanket approval for any subscription design; no eligibility claim was made in this preparation.
