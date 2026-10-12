#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/build/Screen Shoter Open.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift scripts/generate-resources.swift
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --target-device mac --output-format human-readable-text --warnings
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Sources/*.swift -o "$APP/Contents/MacOS/ScreenShoterOpen" -framework AppKit -framework Vision -framework ScreenCaptureKit -framework AVFoundation -framework Carbon -framework ServiceManagement
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Icons "$APP/Contents/Resources/"
codesign --force --sign - --identifier org.hari.screenshoter.open "$APP"
print -r -- "$APP"
