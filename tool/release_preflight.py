"""Local source/asset checks; does not certify native behavior or App Review."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import struct
import xml.etree.ElementTree as ET

APP = Path(__file__).resolve().parents[1]
LIB = APP / "lib"
errors = []


def check(condition, message):
    print(("PASS: " if condition else "FAIL: ") + message)
    if not condition:
        errors.append(message)


seen = set()


def visit(path):
    path = path.resolve()
    if path in seen or not path.is_file():
        return
    seen.add(path)
    # Follow every platform branch of conditional imports/exports as well.
    directives = re.findall(r"^\s*(?:import|export|part)\s+[^;]+;",
                            path.read_text(), re.MULTILINE)
    for uri in [uri for directive in directives
                for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive)]:
        if uri.startswith("package:calcai_app/"):
            visit(LIB / uri.split("/", 1)[1])
        elif ":" not in uri:
            visit(path.parent / uri)


visit(LIB / "main.dart")
unreachable = set(p.resolve() for p in LIB.rglob("*.dart")) - seen
check(not unreachable, "All shipping Dart files are reachable from main.dart" +
      (": " + ", ".join(str(p.relative_to(APP)) for p in unreachable) if unreachable else ""))
source = "\n".join(p.read_text() for p in seen)
check(all(p.is_relative_to(LIB.resolve()) for p in seen),
      "Shipping imports stay inside lib; no tool or test fixtures")
check(not re.search(r"class\s+(?:Preview|SetupDemo|Fake\w*Service)|void main\(\).*demo", source),
      "No preview/test services in shipping source")
check(not re.search(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----|badCertificateCallback\s*=", source),
      "No embedded private-key blocks or TLS-verification bypasses in Dart")

with (APP / "ios/Runner/Info.plist").open("rb") as f:
    info = plistlib.load(f)
check(all(info.get(k) for k in ["NSBluetoothAlwaysUsageDescription",
      "NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"]),
      "Bluetooth and photo usage descriptions present")
check(not info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads", False),
      "iOS arbitrary HTTP loads are disabled")
with (APP / "ios/Runner/PrivacyInfo.xcprivacy").open("rb") as f:
    privacy = plistlib.load(f)
check(privacy.get("NSPrivacyTracking") is False and
      privacy.get("NSPrivacyAccessedAPITypes"), "Privacy manifest parses and declares required-reason APIs")
project = (APP / "ios/Runner.xcodeproj/project.pbxproj").read_text()
check("PrivacyInfo.xcprivacy in Resources" in project and
      "com.calcai.calcaiApp" in project, "Bundle ID and privacy manifest wired into Xcode")

icon_dir = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
icons = json.loads((icon_dir / "Contents.json").read_text())["images"]
bad_icons = []
for icon in icons:
    p = icon_dir / icon.get("filename", "missing")
    if not p.is_file():
        bad_icons.append(p.name)
        continue
    data = p.read_bytes()
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    target = round(float(icon["size"].split("x")[0]) * float(icon["scale"].rstrip("x")))
    if width != target or height != target or color in (4, 6) or b"tRNS" in data:
        bad_icons.append(p.name)
check(not bad_icons, "All declared iOS icons have correct dimensions and no alpha" +
      (": " + ", ".join(bad_icons) if bad_icons else ""))
launch = ET.parse(APP / "ios/Runner/Base.lproj/LaunchScreen.storyboard")
launch_dir = APP / "ios/Runner/Assets.xcassets/LaunchMark.imageset"
launch_asset = launch_dir / "LaunchMark.png"
check(launch.find('.//imageView[@image="LaunchMark"]') is not None and
      launch.find('.//userDefinedRuntimeAttributes') is None and
      launch_asset.is_file() and
      launch_asset.read_bytes() == (APP / "assets/icon/app_icon.png").read_bytes(),
      "Native launch screen uses the current CalcAI artwork, not a template")
workflow = (APP / "codemagic.yaml").read_text()
check("--target lib/main.dart" in workflow and
      not re.search(r"--target\s+(?:tool|test)/", workflow) and
      "submit_to_app_store: false" in workflow,
      "CI builds the production app and keeps public submission manual")
font_dir = APP / "assets/fonts"
fonts = json.loads((font_dir / "sources.json").read_text())
check(bool(fonts) and all(hashlib.sha256((font_dir / f["file"]).read_bytes()).hexdigest() ==
      f["sha256"] for f in fonts), "Bundled font hashes match their source records")
check(all((font_dir / (name + "-OFL.txt")).is_file() for name in ["inter", "outfit", "robotomono"]),
      "Font redistribution licenses included")
check("GoogleFonts.config.allowRuntimeFetching = false" in source,
      "Runtime font downloads disabled")
print(f"\n{len(errors)} source/asset check(s) failed. Native/device review remains required.")
raise SystemExit(bool(errors))
