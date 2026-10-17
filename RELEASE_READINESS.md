# CalcAI release readiness — October 17, 2026

**Not ready for public submission. No App Review submission or public release has been made.** This current checklist replaces earlier chronological checklists. Automated checks are evidence, not a guarantee of security or App Review acceptance.

## October 17 Windows-to-Mac source transfer

The owner requested the latest app source on the Mac. Branch
`codex/ios-source-sync-20261017` packages the post-1101 Fast funding and BLE
fixes below, their regression tests, and these handoff documents. Earlier
"local" / "uncommitted" notes describe the implementation checkpoints before
this source snapshot. Git transfer does not build, install, upload, or release
the app. Physical verification of these changes remains pending. The unrelated
`tool/website_screenshots.dart` working file is excluded from this snapshot.

## October 17 Wi-Fi authentication race fix (local, after 1101)

The exact 1100 code and current local code released the authentication guard
before the Wi-Fi-mode command completed and did not bind the cloud proof to the
connection that requested it. These are confirmed source risks, not proof of the
cause of the physical disconnect reported by the testing coordinator.

The local Wi-Fi editor now keeps a single attempt guard through nonce, cloud
proof, ownership hello, saved-list refresh, Wi-Fi-mode acknowledgement and
completion. It checks attempt identity, connection generation, peripheral ID,
account session, and screen lifetime after each await. Old replies cannot send
hello to a replacement link, clear a newer guard, or disconnect a newer link.
Skip/retry on the same connection starts a fresh attempt. Hiding the screen
cancels its authentication attempt. The BLE service also fences ownership
completion, Wi-Fi teardown, portal-close completion and delayed native
disconnect cleanup against generation changes. Existing ownership requirements
and the 4-second reconnect, 10-second scan, 12-second screen fallback and
20-second cloud deadlines were not changed.

**227 Flutter tests passed**, including 13 new authentication/teardown race
cases. Fatal-info analysis, all 14 release preflight checks and diff whitespace
checks pass. Tests use delayed fixture responses and fake Bluetooth handles;
this has not been tested on physical hardware. The initial new test fixture had
a `BluetoothDevice.id` type mismatch; it was corrected before the passing runs.
No failed test was omitted. Source changes remain uncommitted/local, with no
upload, installation, firmware edit or account/device mutation. Detailed scope
and remaining legacy reply limitations are in [BLE_WIFI_REPLY_HANDOFF.md](BLE_WIFI_REPLY_HANDOFF.md).

## October 17 allowance-funded Fast mode (local, after 1101)

The owner authorized allowance-funded Fast and optional personal keys in Backend
& AI, then requested cross-chat coordination here. The app now uses the private
model response's `fastModeCapability` and sends explicit `fastModeFunding` when
the user enables Fast. Public catalog support alone never grants allowance
access. Missing/malformed capability, a failed refresh, or a funding mismatch
cannot silently approve a more expensive payer. A successful response must
confirm the requested mode and scope; legacy personal-key Fast remains supported.

Home displays effective Fast state and the authenticated current payer. Settings
labels each provider from a successful complete key listing, respects disabled
keys, displays only validated last-four metadata, and shows unknown/retry states
instead of inventing an allowance payer. Key changes refresh metadata and model
capability. Returning to Home or resuming the app refreshes the AI settings.
Fast stays unboxed and unsupported models keep it hidden.

**214 Flutter tests passed**, fatal-info analysis found no issues, all **14
preflight checks passed**, and diff whitespace checks passed. New coverage
includes explicit allowance opt-in, malformed/missing/legacy capability,
unavailable routes, stale model reads, payer changes, 409 conflicts, key metadata
failure, logout fencing, and narrow-screen/large-text funding labels.

These app changes are **local only**, not in build 1101. Backend & AI owns the
server implementation/deployment and Cloudflare payment/route verification.
The confirmed contract distinguishes effective `fastMode` from stored
`fastModeRequested`/`fastModeFunding`; payer changes require fresh opt-in. The
backend owner also fixed swallowed provider-metadata read failures so a
503 cannot masquerade as an absent key. Backend & AI reports version
`05d67991-84c7-4276-bf7a-8bf40a7559ef` deployed at 1:06:52 PM EDT on October 17.
The deployed candidate source matches the client contract. Platform Fast
allowlists remain off (`platform_fast_unavailable`), and the Cloudflare funding
switch remains off after a failed payment; ordinary platform requests retain
the existing provider funding.

**Live owner-authenticated GET verification remains unverified.** The backend
bundle checks used a synthetic fixture session, and the admin model endpoint
does not expose the capability. Main confirmed that no existing owner bearer
fixture or capture is available; its access is limited to the signed-in phone UI
and admin reads. Do not intercept/export the phone's Keychain or create an owner
fixture to fill this evidence gap. The backend owner verified live unauthenticated
401 boundaries and post-deploy admin reads, which do not verify the owner's
private capability response. `tool/fast_mode_live_smoke_test.dart` is an opt-in
check accepting an existing private task-scoped session file; it permits only
GET `/ai/model/get` and `/ai/apikey/list`, checks private/no-store responses, and
exercises the actual Dart client. It creates no session, makes no account/model
changes, and performs no inference. Do not run it with invented credentials or
describe it as passed until a live authorized session is available.

Supported paid routes and a subsequent native build/device check remain pending.
No new Fast-mode release is implied by another chat's readiness message. No hardware,
backend source, or unrelated screenshot-tool changes were included in this work.

## October 17 post-1101 local Wi-Fi reply fixes

Build **1.0.0 (1101)** from `ce3d21b12ab02f7497fd78fef7dadbab2863885f`
finished Codemagic in 5m 12s and Apple confirmed upload success at the log
timestamp `2026-10-17 16:24:34.834`, delivery
`af70c3ef-d03f-43d3-9482-a243167d3bee`. Apple processing completion is not
verified; App Store Connect's browser session was signed out. No physical
phone installation or public App Review submission was performed.

**1101 still has the legacy Wi-Fi scan/list race.** A subsequent local patch
serializes scans with other commands, preserves cached networks on ambiguous
or failed replies, rejects mismatched result shapes, and adds visible refresh
errors/retry. Connection generations prevent late/queued work from crossing a
disconnect. All **67 targeted tests**, fatal-info analysis, all **14 preflight
checks** and diff whitespace checks pass. No extra push/build/installation or
firmware changes were performed for this patch.

Legacy firmware cannot distinguish a completed empty list from queued `[]`;
the client conservatively reports an unconfirmed result. Protocol limits,
source-only envelope proposal, test scope and the unchanged permission/timeouts
for builds 1100/1101 are in [BLE_WIFI_REPLY_HANDOFF.md](BLE_WIFI_REPLY_HANDOFF.md).

## October 17 TestFlight candidate

The owner requested a new signed Codemagic/TestFlight build with the fixes below.
Before pushing, all **184 Flutter tests passed**, analysis with fatal infos found
no issues, all **14 release source/asset checks passed**, and `git diff --check`
passed. The manual TestFlight workflow repeats these checks and assigns the next
available Apple build number. Native archive and Apple upload results are still
pending at this source snapshot. No public App Review submission or installation
over the physical coordinator's existing build 1100 is included.

## October 17 History refresh diagnosis

The physical test coordinator reported a successful calculator `render` solve
with settled usage, while build 1100 still displayed empty History and Home
activity. In a subsequent physical retest, the coordinator visually located and
tapped the top-right refresh icon in installed build 1100. History immediately
displayed the current account's `SOLVE2X+3=11` answer `x=4` with the model label.
This confirms successful manual retrieval in that retest and supports stale
client state as the cause of the earlier empty view. The actual HTTP status/body
was not captured; the visible result must not be reported as an observed HTTP 200.

Compared source against build 1100 commit `a313ff8052cecf6c4747c59bf2942a57277e7028`:

- The top-right circular-arrow button beside Clear history already exists in
  build 1100 and directly calls the History loader. It lacks a tooltip/label,
  explaining why the accessibility tree cannot find a named Refresh button.
  This is the supported manual refresh path; a cold launch is not required.
- The empty History view bypasses its pull-to-refresh control. Changing a time
  filter, returning to the retained tab, or resuming that tab does not reload
  History in build 1100. Home's usage refresh is independent of activity.
- Home displays an empty activity message even when the history read failed.

Local fixes now refresh activity when returning to Home or History and when
resuming the active page. Empty and filtered History views support pull-to-refresh,
and the header action is named "Refresh history". Home and History display
retryable errors; failed refreshes preserve previously loaded activity. History
loading is independent of other cloud calls. Malformed success responses cannot
be interpreted as empty history. Older concurrent responses, resets and completed
history deletion cannot restore stale history or errors. Home refreshes retain
the larger History fetch limit after the full tab has been opened.

Validation: **36 targeted tests passed**, covering History/Home recovery, empty
pull-to-refresh, render answers, tab/filter preservation, active-only resume,
malformed data, stale-response/deletion races, account isolation and usage refresh.
Analysis with fatal infos found no issues and all **14 source/asset checks passed**.
All HTTP responses in these tests are local fixtures. No live history was cleared,
no device/account/pairing/backend state was changed, and no build was uploaded or
installed during that test pass. These fixes are included in the new candidate.

Manual-refresh retrieval is now verified by the physical test coordinator. Search,
range filters and controlled deletion checks are still in progress, not passed.
Verify automatic refresh, empty pull-to-refresh and new error/retry behavior in a
future coordinated test build without overwriting the ongoing installed-build
test session. Build 1100 does not contain these local fixes.

## October 17 focused iOS source fixes

The installed production/TestFlight app remains **1.0.0 (1100)**. The following
changes are included in the new candidate. No native app was built, installed or
uploaded during the source-fix pass, and no physical phone, calculator, pairing
or account was changed.

- Note deletion, calculator-preview Previous/Next and Wi-Fi setup/management
  Back buttons now use Material-localized tooltips/accessibility text. Delete
  identifies the note. Flutter semantics checks verify button roles, tap actions
  and paging boundaries; native VoiceOver/XCTest labels still need verification
  in a future approved build.
- Notes say "Saved to your account" after cloud success, and explain opening
  Notes on the calculator over Wi-Fi. The app no longer claims confirmed device
  delivery. The reported calculator `SERVER ERROR` belongs to Backend & AI and
  the physical test owner; these wording changes do not resolve that error.
- Custom instructions now enforce the server's actual 2,000 UTF-16-unit bound
  for typing/pasting and example insertion, without splitting a grapheme. The
  counter agrees with the server. An over-limit keyboard composition cannot be
  saved until it is committed and bounded. Existing content is retained if an
  example will not fit.
- Validation: **19 focused tests passed** (notes, paging, Wi-Fi recovery/setup,
  and instruction boundaries) plus **40 model/Fast mode/consent/usage tests**.
  Analysis with fatal infos found no issues; all **14 source/asset checks**
  passed. These use local fixtures, not real BLE, device delivery or AI solves.
- A read-only public catalog request at `2026-10-17T05:32:07Z` returned schema 1
  and 19 entries across OpenAI, Google and Anthropic. This verifies advertised
  metadata, not successful provider inference or billing.

Remaining physical evidence for MACBOOK/IOS and TI84/PCB TESTING:

1. In a future test build, use VoiceOver/XCTest to identify and activate Delete,
   Previous page, Next page and Back, including disabled first/last paging and
   the Wi-Fi disconnected/error screen. Preserve build 1100 until coordinated.
2. Verify custom instructions at 1,999/2,000/2,001 ASCII characters, pasted emoji
   and combining characters, example insertion near the cap, native composing
   keyboards, save/reopen persistence, failed-save retry and discard behavior.
3. Test Bluetooth permission denied separately from radio off, then restore and
   retry without re-pairing. Current Wi-Fi UI combines both into "Bluetooth
   disconnected"; native permission-state behavior is not established here.
4. Verify live provider/model selection with the account's plan and own-key
   settings, failed/malformed catalog fallback, and unsupported Fast mode hidden.
   A successful picker selection is not an inference-availability test.
5. Verify saved AI-sharing refusal blocks an actual calculator AI request,
   withdrawal/re-enable and network-failed consent retry. Local gate tests pass;
   actual provider-call suppression requires backend/device evidence.
6. After an authorized real text/photo solve, verify nonempty Home activity and
   history, photo/detail access, settled per-account usage, resume/return-to-Home
   refresh, syncing/offline/exhausted states and own-key separation. The app
   refreshes usage after newly fetched history, on resume and on returning Home;
   this is not proof of a live push notification for a solve while Home stays open.
7. Recheck calculator Notes retrieval after the backend error is fixed, plus
   note update/delete/reopen and offline read/save recovery. Cloud save success
   must not be used as evidence that the calculator received the note.

## October 15 Fast mode visibility candidate

- Fast mode and its cost label are hidden when the selected model has no
  supported Fast mode provider. Supported models retain the existing personal
  API key requirement. Visibility follows the backend model catalog.
- Validation: all **166 Flutter tests passed**, analysis found no issues, and
  all **14 release source/asset checks passed**. The owner requested a new
  Codemagic TestFlight upload; its Apple upload must be verified separately.
- The preceding consent, usage and portal changes were uploaded successfully
  as **1.0.0 (1099)** from commit `faf54162df8f63ae35af2600b98bdbf2e6931808`.
  Codemagic build `6ad02b78546ce6236ceeb495` finished and Apple confirmed upload
  at `2026-10-15T01:31:19.279Z`. Native verification below remains pending.

## October 14 consent, usage and portal TestFlight candidate

These changes are **not included in build 1098**. The owner has now requested a
Codemagic TestFlight upload for native verification. The signed candidate repeats
the release checks and allocates the next Apple build number. Upload completion
must be verified separately. This change does not modify the backend or firmware
and does not submit the app for public App Review.

- Reproduced a native transport/server incompatibility: live diagnostic GETs to
  consent and usage return HTTP 400 `invalid body` with `Content-Length: 0`;
  bodyless requests reach authentication and return the expected 401 for the
  deliberately invalid diagnostic Bearer. The installed `cupertino_http` 3.1.0
  sets that header and an empty NSData body for ordinary `http.Request` GETs.
  The native client now adapts empty GET/HEAD requests into bodyless streams with
  no length header. Foundation networking, TLS validation, authorization,
  cancellation, redirects and session guards are preserved. Mutations, explicit
  bodies and streaming requests pass through unchanged and are never replayed.
- Confirmed consent UI defect: the load failure cleared `_loading` but choices
  depended only on `_saving`, so a failed/unknown read still left both buttons
  enabled. Choices now require a successful read. Settings no longer labels an
  unknown choice as off. A valid Retry recovers without submitting consent.
- Consent reads now validate `ok`, the supported version and both boolean
  fields. Saves additionally require `reviewed:true` and the requested choice.
  Unsupported/malformed responses cannot unlock Home. Stale async errors from a
  different login are discarded. Failures distinguish session expiry, access,
  rate limiting, server status, response format and network/timeouts; no raw
  response body or credentials are displayed.
- Usage failures retain safe HTTP status or network diagnostics. Unexpected
  data is reported as a response failure, not an offline connection. Valid
  cached usage stays visibly stale; a missing balance stays unknown. Tests cover
  a real CloudService 503 followed by a successful Retry, without mutations or a
  fabricated balance. Existing null/syncing, finite Pro, reset, account switching
  and refresh rules remain covered.
- The connected iOS portal pill has a translucent pale gradient and a subtle
  six-second shimmer. It remains fixed above Home scrolling and keeps its close
  confirmation/acknowledgement behavior. Decorative animation stops for Reduce
  Motion, accessible navigation, hidden tabs and backgrounding; it is disposed
  when the BLE link disconnects. The small surface has its own repaint boundary.
- Validation: **166 Flutter tests passed**, analysis with fatal infos found no
  issues, all **14 release source/asset checks passed**, and a rendered Home
  preview was visually inspected. The preview uses synthetic account data and
  in-memory BLE, not a native or physical-device test.

**Native verification still required:** the transport defect above is reproduced
against the live service and corrected locally, but the original phone's failing
request was not captured and the corrected Foundation transport cannot execute
on this Windows host. The bounded read-only log capture at approximately
9:04–9:09 PM EDT contained only the synthetic diagnostic requests. No real
session credentials, request headers or response bodies were recorded. Earlier
scoped admin checks found account usage ready with 98.94% remaining; this does
not establish the phone's Bearer session or network path. Before marking the
reported issue resolved, install a new native build and verify that consent
loads and saves, Home displays real usage, and account switching stays isolated.
Build 1098 does not contain these changes. Hardware remains owned by TI-84 &
ESP32 Bench Testing.

## October 13 TestFlight candidate

The owner requested a Codemagic TestFlight upload of the app changes. Before
pushing, all 152 Flutter tests, analysis with fatal infos, and all 14 release
source/asset checks passed. The signed candidate workflow repeats those checks
and allocates the next available Apple build number. No public App Review
submission, backend activation or firmware publication is included in this request.

## October 12 local pairing update

Local Flutter changes add negotiated V2 approval and authenticated completion using
`../edge-worker/src/features/devices/PAIRING_V2.md`, including its October 12
completion update. No native build, upload, deployment or App Review submission
was performed for this work. September build/store evidence below is historical,
not verification of these local changes.

- The code screen verifies the device identity, requests one signed offer, relays
  the actual entered code, submits the device approval with the same Bearer
  session, and waits for the calculator's completion acknowledgement before
  recording ownership or opening Wi-Fi setup.
- Lost responses reuse the saved offer/approval/completion on the same BLE
  connection. Sign-out, changed connections, invalid proofs and terminal server
  errors stop the attempt. A negotiated V2 flow never falls back to legacy claims,
  including after Wi-Fi cleanup disconnects. Older firmware retains legacy setup.
- Current app wire: flat `pairapprove` command with the offer fields plus `code`;
  approval reply echoes `cmd`, `protocol`, `mac`, `challengeId`, `approvalNonce`
  and `approvalResponse`. `paircomplete` sends `protocol`, `mac`, `challengeId`,
  `approvalNonce` and the opaque nested `completion` object. Its acknowledgement
  echoes `cmd`, `protocol`, `mac`, `challengeId` and `ownershipId`, with `ok:true`.
  Signed commands use reliable long writes capped at 512 bytes.
- Validation: 62 focused Flutter tests passed (pairing, ownership/release,
  device verification, stale sessions, Wi-Fi, portal and AI consent), Flutter
  analysis found no issues, and all 14 release source/asset checks passed.
  Tests use synthetic HTTP/BLE fixtures;
  they do not establish native ATT long-write support or hardware correctness.
- Shared-vector follow-up verifies the complete HTTP/BLE
  relay using the backend's `pairing-v2-contract.json`. Offer, approval and
  completion message bytes and HMACs match with the 64-character key treated as
  UTF-8 text, not decoded hex. Both BLE commands fit the 512-byte limit. The
  standalone app test fixture is byte-identical to the backend fixture (SHA-256
  `5c7cc8912f3916e2966afb3f6cf046f4ece22d25f2e63c215d95d6a51fa61e84`).
  This public key is test-only and must never be provisioned or shipped as a
  device credential. The app relays signatures; it does not authenticate them
  using a device key.
- Reconnect follow-up: all 21 V2 tests pass. New regressions cover a committed
  cloud claim whose response or BLE completion is lost, disconnect/cancel,
  fresh code/offer/approval after reconnect, and an `already:true` completion
  that still waits for matching firmware acknowledgement. No proof is reused
  across connections, no legacy claim is sent, and no account-unpair request
  is made. The app no longer suggests removing the device to recover.
- The current firmware JSON parser/handler matches the app's field names,
  nesting, integer timestamps and reply echoes (`pairing_approval_json.h` and
  `pairing_approval_ble.h`). Real transport and hardware behavior remain untested.
- The final backend recovery contract and implementation were compared with the
  app on October 12; no app correction was needed. A fresh reconfirmation time
  and stable ownership UUID are relayed unchanged, including for legacy owners.
- Pending: real iPhone/enrolled-calculator tests and coordinated activation.
  Backend V2 remains disabled by default. Verify
  wrong-code limits, expiry, cancellation/reconnection, lost cloud response,
  lost completion acknowledgement, ownership transfer and Wi-Fi/portal behavior.
  Backend recovery must preserve the existing owner generation and private data
  while requiring fresh local approval; app regressions use synthetic responses.
  Legacy replay risk remains until a separately reviewed
  per-device enforcement cutover.

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
