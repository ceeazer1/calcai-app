# CalcAI iOS App

Flutter app for connecting to and managing the CalcAI ESP32 via BLE.

## Features
- BLE device scanning & connection
- WiFi provisioning over Bluetooth
- Premium dark theme UI

## Development
```bash
flutter pub get
flutter run -d chrome    # UI preview
flutter run -d <device>  # Android/iOS device
```

## Building for iOS (via Codemagic)
Push to GitHub → Codemagic builds → TestFlight on your iPhone
