# CalcAI release readiness — September 13, 2026

**Local cleanup/preparation complete. Not cleared for App Store submission.**

This audit inspected source, assets, configuration, and automated UI behavior.
It did not create a signed iOS archive, test physical hardware, delete a real
account, or submit to Apple. The follow-up implemented app/backend privacy fixes
and updated dashboard Apple sign-in locally. Nothing was deployed. See
[the coordinated release procedure](../edge-worker/PRIVACY_RELEASE.md) for
credentials, migration, processor retention, and native verification still needed.

## Completed

- Follow-up privacy work adds versioned AI consent and Settings withdrawal,
  authenticated/expiring photo access, Apple-code exchange and token revocation,
  retry-safe server deletion, clearer API-key entry, iPad sharing anchoring,
  and hostname-first native connections. AI Gateway payload logs/caching are
  disabled for new requests. These changes are local and require the coordinated
  release and live checks described in `../edge-worker/PRIVACY_RELEASE.md`.

- Removed standalone setup/screenshot entry points and two sample photos.
  Moved useful fixtures from production services into `test/support` and renamed
  setup/Wi-Fi regression tests. All remaining shipping Dart files are reachable
  from `main.dart`; original runtime dependencies are all used.
- Removed an unused BLE preview service and the unused success-screen SSID field.
- Fixed setup completion/skipped-Wi-Fi routing so the authentication gate remains
  active and sign-out returns to Login after setup.
- Fixed the deletion progress route surviving disposal of Settings. Back cannot
  dismiss it during deletion. Reset cloud, BLE network, and image-cache state
  when ending a session. Discard delayed responses from an old cloud session.
- Fixed provider-key metadata surviving reset, closed the cloud client on
  disposal, and ensured failed TLS requests release their sockets.
- Added working Terms/Privacy links before login, contact support, and licenses
  in Settings. Fixed social-button overflow with large text on small phones;
  authentication error messages can grow without clipping.
- Bundled Inter, Outfit, and Roboto Mono with licenses and hashes; runtime font
  fetching disabled. Included Cupertino glyphs used by Flutter's iOS controls.
- Added User ID and Product Interaction declarations to the privacy manifest.
  Replaced template web branding/icons and the empty native example test.
- Added source/asset preflight checks. Kept Codemagic in the independent app repository root, pinned the tested Flutter version, added tests/analysis before builds,
  checked the SDK version and archived privacy manifest, and separated unsigned
  validation from manual TestFlight publishing. Certificates are reused rather
  than created on every build; no temporary plaintext private-key file is used.

## Blocking findings

| Finding | Evidence | Required resolution |
| --- | --- | --- |
| AI consent deployment pending | Versioned app consent, Settings withdrawal, and server enforcement are implemented and tested locally. | Deploy the coordinated worker/app update and test a real calculator while the phone app is closed. Existing accounts start with AI off until explicitly allowed. |
| Apple deletion live validation pending | Code exchange, bound encrypted refresh tokens, revocation, old-account reauthorization, and retry-safe cleanup are implemented and tested with mocks. | Configure the Apple Sign in with Apple key, key ID, team ID and encryption secret; test login/deletion on a real iPhone and verify revocation at Apple. |
| Privacy policy contradicts API-key handling | The live policy says full customer API keys do not reach CalcAI; `CloudService.saveApiKey` sends the full key to `ai.calcai.cc/ai/apikey/save`. | Align the architecture and public disclosure; verify key access, encryption, retention, deletion, and provider usage. Also verify the policy's six-month inactivity-deletion claim against the production job. The public policy was not edited. |
| Private photo rollout pending | Ownership checks, expiring capabilities, authenticated app downloads, legacy history migration, and indexed photo deletion are implemented and tested locally. | Configure IMAGE_SIGNING_SECRET, deploy, and test app/dashboard/device access. Inventory legacy orphan uploads and purge any historical CDN/gateway caches. Previously downloaded copies cannot be recalled. |
| Native release unverified | This machine is Windows; no Xcode archive or hardware results. | Run `ios-check`, then a signed TestFlight candidate, and the device checks below. Inspect the archive's combined privacy report and validation results. |
| Reviewer access incomplete | Core features require an account and physical CalcAI hardware. Previews were removed as requested. | Provide a dedicated working review account and compatible hardware/access instructions. Keep the backend live. A video can supplement access. |

Apple requires prior permission and clear disclosure for sharing personal data
with third-party AI, and access to account/hardware-dependent features for review:
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
For deleted Apple-login accounts, see [account-deletion requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
and [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).
The disclosure mismatch was checked against the [live CalcAI privacy policy](https://calcai.cc/privacy).

## Verification and limitations

**76 Flutter tests and 60 backend tests passed; analysis found no issues; all 11 preflight checks passed.**
The production JavaScript web build, worker dry-run bundle, and focused dashboard
source lint also passed. Follow-up logs are in `../outputs/app-release-audit/`.
Mocked services do not establish live provider, Apple or Cloudflare behavior.
Tests exercise setup/code entry/back confirmation, network selection and saved
network editing, notes, proof/revocation parsing, safe image URLs, text conversion,
session isolation, deletion routing, and sign-in layouts. Layout checks use
320×568, 393×852, and 1024×1366 at 1.6× text scale.

Preflight checks reachability, absent demo services, limited private-key/TLS-bypass
patterns, permission strings, plist parsing, Xcode manifest inclusion, all declared
icon dimensions/alpha, font hashes/licenses, and disabled font downloads. This is
not a penetration test or a guarantee of App Review acceptance.

JavaScript web compilation is an additional check, not iOS validation. The existing
secure-storage web dependency does not support WebAssembly; the follow-up builds
the JavaScript target explicitly. Many dependencies have newer major
versions; those were not upgraded without native regression testing. No assertion
of zero dependency vulnerabilities is made.

## iOS configuration

- Bundle ID `com.calcai.calcaiApp`, display name CalcAI, version `1.0.0`, local
  build `149`. Confirm the marketing version against App Store Connect. CI obtains
  a fresh build number from Apple and the project counter. Run one upload at a
  time to avoid concurrent-number races.
- Deployment target iOS 15.0. Both iPhone/iPad are enabled. Main requests portrait;
  verify iPad rotation, multitasking, keyboard, and safe areas. iPad support was
  not silently removed and requires its own store assets/testing.
- Bluetooth and Photos descriptions present; no arbitrary HTTP-load exception.
  Photos access creates/saves to the CalcAI album. Apple entitlement and Google
  reverse-client URL scheme are present; validate the exact team/bundle IDs and
  email-relay configuration in the provider consoles.
- Privacy manifest is included; UserDefaults reason `CA92.1` declared. Inspect
  all SDK manifests in the native archive and reconcile the App Store privacy
  questionnaire with actual backend/SDK behavior.
- Swift Package Manager is configured. The locked secure-storage plugin still
  uses CocoaPods; Flutter 3.44.2 generates its fallback Podfile during native build.
  A missing checked-in Podfile is not itself a failure. Preserve native dependency
  lockfiles from the first successful Mac build.
- `ITSAppUsesNonExemptEncryption` is false. The owner must confirm that answer for
  the actual HTTPS/HMAC implementation and any export documentation required.
- The empty XCTest was replaced with bundle-resource checks; XCTest was not run
  here. Flutter tests do not replace native tests.

Apple requires iOS/iPadOS 26 SDK or newer for uploads; CI checks this:
[SDK requirement](https://developer.apple.com/news/?id=ueeok6yw).

## Your Apple/Codemagic steps

1. Confirm active Apple Developer membership, the correct team, and accepted
   agreements. Create/verify the CalcAI App Store record with the bundle ID above.
   Its numeric Apple ID is needed for CI.
2. Commit the app source, lockfile, and `codemagic.yaml` from the independent
   `calcai_app` repository (`ceeazer1/calcai-app`). Changes are uncommitted.
   Nothing was staged, committed, pushed, or deployed; unrelated changes were preserved.
3. Configure Codemagic's App Store integration named `CalcAI`. Put the numeric
   `APP_STORE_APP_ID` in `app_store_credentials`. Configure the matching Apple
   Distribution certificate/private key and App Store profile under Code signing
   identities. Keep private keys out of chat and Git.
4. Run `ios-check`, resolve native compiler/plugin/entitlement issues, then run
   `ios-testflight` manually for internal testing. This never submits to public
   App Review. See [Codemagic signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
   and [build-number tooling](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/app-store-connect/get-latest-testflight-build-number.md).
5. Finish the blocking fixes and hardware checks. Fill the submission draft with
   real screenshots, review credentials/access, privacy answers, age rating,
   export answers, support URL, pricing, and territories.
6. Select the tested build and submit it for review. Choose manual public release
   in App Store Connect if you want to control launch after approval.

## Physical-device acceptance checks

- [ ] Fresh install/offline launch; Bluetooth denied/off/on; slow service.
- [ ] Apple/Google/email login, verification/reset, cancellation, expired session,
      Hide My Email/relay, sign-out, account deletion, and reinstall.
- [ ] Real pairing/code paste/backspace, invalid code, leave confirmation,
      wrong-owner/device-proof rejection, and disconnect during setup.
- [ ] Secured/open/hidden Wi-Fi, wrong password, timeout/retry, hotspot, network
      editing/removal, and phone/calculator restart persistence.
- [ ] IPv6-only/DNS64/NAT64 and ordinary Wi-Fi/cellular. Connections now try the
      native hostname first; DoH is a connection-only fallback. Real iOS network
      testing is still required.
- [ ] Notes/history/model/context success and failure; account switching with
      requests pending; no previous-account content.
- [ ] Private photo access/retention, photo saving with permission granted/denied,
      sharing, iPad popover behavior.
- [ ] Deletion removes content, keys, sessions and mappings; Apple authorization
      is revoked; offline calculator releases its former owner on reconnection.
- [ ] VoiceOver, large text, Reduce Motion, keyboard avoidance, iPad multitasking,
      back gestures, background/resume, and BLE battery behavior.
- [ ] Review account/hardware, real screenshots, support page, accurate privacy
      answers, AI consent, and business-model review completed.

## Recovery

Backup made before cleanup:
`../outputs/app-release-audit/source-before-cleanup-20260913-012438.zip`.
It contains source/configuration, not generated build caches. Restore individual
files only so newer work is not overwritten.
