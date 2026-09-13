# CalcAI companion app

Flutter iOS app for CalcAI device pairing, Wi-Fi management, notes, history,
photos, and AI settings. Use Flutter 3.44.2 / Dart 3.12.2, matching CI.

```sh
flutter pub get --enforce-lockfile
python tool/release_preflight.py
flutter analyze --no-pub
flutter test --no-pub
flutter run --target lib/main.dart
```

Bluetooth, Apple/Google sign-in, Keychain, Photos, and sharing require testing on
a physical iPhone. Pairing/Wi-Fi require CalcAI hardware. The web target is for
layout checks and does not validate native iOS behavior.

Production starts at `lib/main.dart`. Standalone previews have been removed.
Test fixtures live only in `test/support`; regression tests use the real screens.
Fonts/licenses are bundled. Regenerate icons with `dart run flutter_launcher_icons`.

Read [RELEASE_READINESS.md](RELEASE_READINESS.md) before upload. Listing copy and
review notes are drafted in [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md).

The app has its own Git repository (`ceeazer1/calcai-app`). Its root
`codemagic.yaml` defines `ios-check` (analysis, tests, source/asset checks, unsigned
iOS compile) and `ios-testflight` (manual signed TestFlight candidate, never public
App Review). Run and commit changes from this app directory.
