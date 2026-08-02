import Flutter
import UIKit

/// Hides the UI in the app switcher.
///
/// iOS snapshots the window when the app resigns active, and that snapshot is
/// what shows in the task switcher and is cached on disk. Without this, the
/// user's notes and prompt history sit there in plain view of anyone who
/// opens the switcher.
///
/// A plain opaque cover is used rather than a blur: it is one view added to an
/// existing window, so there is no measurable cost on backgrounding and
/// nothing to unwind if the app is killed while hidden. Both methods are
/// no-ops if the window is missing, and adding is idempotent, so repeated
/// resign/activate cycles cannot stack covers.
class SceneDelegate: FlutterSceneDelegate {

  private static let coverTag = 0x0CA1CA1

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window = self.window ?? (scene as? UIWindowScene)?.windows.first,
          window.viewWithTag(SceneDelegate.coverTag) == nil else { return }

    let cover = UIView(frame: window.bounds)
    cover.tag = SceneDelegate.coverTag
    // Matches AppColors.background so this reads as the app dimming rather
    // than as a glitch.
    cover.backgroundColor = UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1.0)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    let window = self.window ?? (scene as? UIWindowScene)?.windows.first
    window?.viewWithTag(SceneDelegate.coverTag)?.removeFromSuperview()
  }
}
