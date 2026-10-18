#!/usr/bin/env python3
"""Build the native app and an ad-hoc signed Apple Silicon DMG. No Xcode required."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--no-dmg", action="store_true")
    args = parser.parse_args()
    configuration = "debug" if args.debug else "release"
    run("swift", "build", "-c", configuration, "--product", "FoldBar")
    binary_dir = Path(run("swift", "build", "-c", configuration, "--show-bin-path", capture_output=True, text=True).stdout.strip())
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    app = output / "FoldBar.app"
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    shutil.copy2(binary_dir / "FoldBar", contents / "MacOS/FoldBar")
    shutil.copy2(ROOT / "LICENSE", contents / "Resources/LICENSE")
    info = {
        "CFBundleExecutable": "FoldBar",
        "CFBundleIdentifier": "io.github.wutongyuonce.FoldBar",
        "CFBundleName": "FoldBar",
        "CFBundleDisplayName": "FoldBar",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSScreenCaptureUsageDescription": "FoldBar 仅在内存中显示菜单栏图标，不保存屏幕录像或截图。",
        "NSHumanReadableCopyright": "Copyright © 2026 FoldBar contributors. GPL-3.0."
    }
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    run("codesign", "--force", "--sign", "-", "--identifier", info["CFBundleIdentifier"], str(app))
    run("codesign", "--verify", "--strict", "--verbose=2", str(app))
    if not args.no_dmg:
        staging = output / "dmg-staging"
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        shutil.copytree(app, staging / app.name)
        (staging / "Applications").symlink_to("/Applications")
        (staging / "安装说明.txt").write_text(
            "将 FoldBar 拖入 Applications 后打开。\n"
            "这是未公证的开发版本。首次启动可能需要通过系统设置允许打开。\n"
            "辅助功能和屏幕录制权限请在 FoldBar 设置页按需授权。\n"
            "源码与手动下载：https://github.com/wutongyuonce/FoldBar\n",
            encoding="utf-8"
        )
        dmg = output / "FoldBar-1.0-arm64.dmg"
        run("hdiutil", "create", "-volname", "FoldBar", "-srcfolder", str(staging), "-ov", "-format", "UDZO", str(dmg))
        shutil.rmtree(staging)
        run("hdiutil", "verify", str(dmg))
        print(dmg)
    print(app)


if __name__ == "__main__":
    main()
