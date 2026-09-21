"""Inventory the actual archived app/SDK manifests for App Store preparation.

This report is evidence for the privacy questionnaire, not a replacement for
checking backend collection, retention, and third-party provider practices.
"""
import json
from pathlib import Path
import plistlib
import sys


def main():
    app, output = Path(sys.argv[1]), Path(sys.argv[2])
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    manifests = []
    for path in sorted(app.rglob("*.xcprivacy")):
        with path.open("rb") as stream:
            contents = plistlib.load(stream)
        if not isinstance(contents, dict):
            raise ValueError(f"Invalid privacy manifest: {path.relative_to(app)}")
        manifests.append({"path": str(path.relative_to(app)), "declarations": contents})
    if not any(m["path"] == "PrivacyInfo.xcprivacy" for m in manifests):
        raise ValueError("App privacy manifest missing from native archive")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({
        "bundleId": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "manifests": manifests,
    }, indent=2) + "\n")
    print(f"Recorded {len(manifests)} archived privacy manifests in {output}")


if __name__ == "__main__":
    main()
