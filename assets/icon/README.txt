Put your app icon here as:  app_icon.png

Requirements:
- 1024 x 1024 pixels, PNG
- Square (no rounded corners — iOS rounds it automatically)
- Keep important content away from the very edges (iOS crops slightly)

Then run from the calcai_app folder:
    dart run flutter_launcher_icons

That regenerates all the iOS app-icon sizes from your image.
If your logo has a transparent background, it'll be filled with the
background_color_ios set in pubspec.yaml (currently white).
