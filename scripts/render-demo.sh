#!/bin/zsh
# Synthetic offscreen render. AppEnvironment isolates history and preferences.
set -euo pipefail
cd "${0:A:h:h}"
command -v ffmpeg >/dev/null || { print -u2 'Install ffmpeg to encode the demo video.'; exit 1; }
./build.sh
APP="$PWD/build/Screen Shoter Open.app"
MEDIA=$(mktemp -d "${TMPDIR:-/tmp}/screenshoter-demo.XXXXXX")
trap 'rm -rf "$MEDIA"' EXIT
export ISCREENSHOTER_RENDER_DIR="$MEDIA"
"$APP/Contents/MacOS/ScreenShoterOpen" --render-demo
"$APP/Contents/MacOS/ScreenShoterOpen" --verify
ffmpeg -hide_banner -loglevel warning -y -framerate 10 -i "$MEDIA/demo-frame-%04d.png" -vf 'scale=1280:-2' -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart "$MEDIA/annotation-demo.mp4"
ffmpeg -hide_banner -loglevel warning -y -framerate 10 -i "$MEDIA/demo-frame-%04d.png" -vf 'fps=10,scale=960:-2:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse' -loop 0 "$MEDIA/annotation-demo.gif"
# Copy only known generated outputs after every step succeeds.
mkdir -p docs/media
for name in editor editor-palette editor-toolbar capture-magnifier home ocr-complete ocr-error pin-scale-menu save-empty-png settings-privacy settings-about settings-general settings-shortcuts; do
  [[ -f "$MEDIA/$name.png" ]] && cp "$MEDIA/$name.png" docs/media/
done
cp "$MEDIA/annotation-demo.mp4" "$MEDIA/annotation-demo.gif" docs/media/
print -r -- 'Saved synthetic view renders, MP4 and GIF to docs/media/.'
