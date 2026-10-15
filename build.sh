#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
ROOT="$PWD"
for tool in xcrun xcodebuild python3 codesign; do
  command -v "$tool" >/dev/null || { print -u2 "Missing prerequisite: $tool. See README.md."; exit 1; }
done
xcrun --find actool >/dev/null 2>&1 || { print -u2 'Full Xcode is required. Select it with xcode-select.'; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { print -u2 'Build on an Apple Silicon Mac.'; exit 1; }
mkdir -p build
STAGE=$(mktemp -d "$ROOT/build/.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Screen Shoter Open.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Generate into an empty workspace, never rewrite checked-in resources.
(cd "$STAGE"; swift "$ROOT/scripts/generate-resources.swift")
xcrun actool "$STAGE/Resources/Assets.xcassets" --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --target-device mac --output-format human-readable-text --warnings
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Sources/*.swift -o "$APP/Contents/MacOS/ScreenShoterOpen" -framework AppKit -framework Vision -framework ScreenCaptureKit -framework AVFoundation -framework Carbon -framework ServiceManagement
cp "$STAGE/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
cp -R "$STAGE/Resources/Icons" "$APP/Contents/Resources/"
python3 scripts/build-manifest.py "$APP/Contents/Resources/build-manifest.json"
SIGNING_IDENTITY="${SCREENSHOTER_SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
  codesign --force --sign - --identifier org.hari.screenshoter.open "$APP"
else
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime --identifier org.hari.screenshoter.open "$APP"
fi
codesign --verify --strict "$APP"
# Only replace the last good build after compilation and signature validation.
PREVIOUS="$ROOT/build/.previous-app"
[[ ! -e "$PREVIOUS" ]] || { print -u2 "Recover or remove $PREVIOUS before building."; exit 1; }
if [[ -e "$ROOT/build/Screen Shoter Open.app" ]]; then mv "$ROOT/build/Screen Shoter Open.app" "$PREVIOUS"; fi
if ! mv "$APP" "$ROOT/build/Screen Shoter Open.app"; then
  [[ ! -e "$PREVIOUS" ]] || mv "$PREVIOUS" "$ROOT/build/Screen Shoter Open.app"
  exit 1
fi
rm -rf "$PREVIOUS"
print -r -- "$ROOT/build/Screen Shoter Open.app"
