#!/usr/bin/env python3
"""Build the isolated native design app; optionally capture its real simulator UI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "build/unified-native-design"
APP = OUT / "GuYouJiDesign.app"
BUNDLE = "cn.guyouji.design.unified"
PAGES = ["home", "map", "activities", "stories", "story", "appointment", "meetup", "summary",
         "messages", "chat", "contacts", "person", "me", "learning", "settings", "memories"]
RESOURCES = {
    "home.png": "App/Assets.xcassets/home_departure_foyer_3d.imageset/home_departure_foyer_3d.png",
    "park.jpg": "App/Resources/ActivityScene/activity-park-poster.jpg",
    "story-room.jpg": "App/Resources/StoryArt/london_interior.jpg",
    "story-exterior.jpg": "App/Resources/StoryArt/london_exterior.jpg",
    "oliver-manuscript.png": "App/Resources/StoryArt/Departures/dp_oliver_manuscript.png",
    "avatar-oliver.png": "App/Resources/Avatars/avatar_p3r_oliver.png",
    "avatar-ruby.png": "App/Resources/Avatars/avatar_p3r_ruby.png",
    "avatar-marcus.png": "App/Resources/Avatars/avatar_p3r_marcus.png",
    "messages.jpg": "App/Assets.xcassets/messages_london_glass.imageset/messages_london_glass.jpg",
    "contacts.jpg": "App/Assets.xcassets/contacts_london_glass.imageset/contacts_london_glass.jpg",
    "learning.jpg": "App/Assets.xcassets/learning_london_glass.imageset/learning_london_glass.jpg",
    **{name + ".jpg": "docs/design/appointments-2026-10-31/assets/" + name + ".jpg"
       for name in ["little-venice", "primrose-hill", "notting-hill"]},
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    APP.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-parse-as-library",
               "-target", "arm64-apple-ios18.0-simulator", "-sdk", sdk,
               "-module-name", "GuYouJiDesign", "-framework", "SwiftUI", "-framework", "UIKit", "-framework", "MapKit",
               str(HERE / "DesignSystem.swift"), str(HERE / "Screens.swift"), str(HERE / "App.swift"),
               "-o", str(APP / "GuYouJiDesign")]
    run(*command)
    info = {"CFBundleExecutable": "GuYouJiDesign", "CFBundleIdentifier": BUNDLE,
            "CFBundleName": "咕游记界面", "CFBundleDisplayName": "咕游记界面",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "MinimumOSVersion": "18.0", "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1],
            "UILaunchScreen": {}, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
            "UIViewControllerBasedStatusBarAppearance": True,
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}}
    with (APP / "Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    manifest = []
    for name, source in RESOURCES.items():
        original = ROOT / source
        shutil.copy2(original, APP / name)
        manifest.append({"name": name, "source": source, "sha256": digest(original)})
    manifest.extend({"source": str(p.relative_to(ROOT)), "sha256": digest(p)} for p in HERE.glob("*.swift"))
    (OUT / "render-inputs.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    run("codesign", "--force", "--sign", "-", str(APP), stdout=subprocess.DEVNULL)
    print("Built", APP, flush=True)


def capture(device, pages, dark=False, large=False, composer=False):
    run("xcrun", "simctl", "install", device, str(APP))
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, BUNDLE, "data"], text=True).strip())
    captures = OUT / "screenshots"
    captures.mkdir(exist_ok=True)
    env = os.environ.copy()
    env.update({"SIMCTL_CHILD_DESIGN_COMPOSER": "1" if composer else "0", "SIMCTL_CHILD_DESIGN_DARK": "1" if dark else "0", "SIMCTL_CHILD_DESIGN_LARGE": "1" if large else "0"})
    for page in pages:
        env["SIMCTL_CHILD_DESIGN_SCREEN"] = page
        token = str(uuid.uuid4())
        env["SIMCTL_CHILD_DESIGN_CAPTURE_TOKEN"] = token
        run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE, env=env)
        ready = container / "tmp" / f"design-ready-{token}"
        deadline = time.monotonic() + 30
        while not ready.exists():
            if time.monotonic() > deadline:
                raise RuntimeError(f"Native view did not become ready: {page}")
            time.sleep(0.2)
        if ready.read_text() != page:
            raise RuntimeError(f"Wrong native page: {page}")
        if page == "map":
            time.sleep(8)  # Native online tiles, never a replacement image.
        suffix = ("-dark" if dark else "") + ("-large" if large else "") + ("-composer" if composer else "")
        path = captures / f"{page}{suffix}.png"
        run("xcrun", "simctl", "io", device, "screenshot", str(path), stdout=subprocess.DEVNULL)
        print(path, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", metavar="DEVICE", help="existing simulator UDID")
    parser.add_argument("--pages", default=",".join(PAGES))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--large", action="store_true")
    parser.add_argument("--composer", action="store_true")
    args = parser.parse_args()
    if not args.skip_build:
        build()
    if args.capture:
        chosen = args.pages.split(",")
        if any(page not in PAGES + ["gallery"] for page in chosen):
            parser.error("unknown page")
        capture(args.capture, chosen, args.dark, args.large, args.composer)
