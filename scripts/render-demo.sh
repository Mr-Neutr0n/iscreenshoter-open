#!/bin/zsh
# Reproduce public media from synthetic content and production AppKit views.
# This is a scripted UI render, not a desktop capture or live user recording.
set -eu
cd "${0:A:h:h}"
command -v ffmpeg >/dev/null || { print -u2 'Install ffmpeg to encode the demo video.'; exit 1; }
./build.sh
apps=(build/*.app(N))
(( ${#apps} == 1 )) || { print -u2 'Expected one app bundle in build/.'; exit 1; }
app="${apps[1]}"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
mkdir -p docs/media
export ISCREENSHOTER_RENDER_DIR="$PWD/docs/media"
"$app/Contents/MacOS/$executable" --render-demo
"$app/Contents/MacOS/$executable" --verify
ffmpeg -hide_banner -loglevel warning -y -framerate 10 -i docs/media/demo-frame-%04d.png -vf 'scale=1280:-2' -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart docs/media/annotation-demo.mp4
ffmpeg -hide_banner -loglevel warning -y -framerate 10 -i docs/media/demo-frame-%04d.png -vf 'fps=10,scale=960:-2:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse' -loop 0 docs/media/annotation-demo.gif
rm docs/media/demo-frame-*.png
print -r -- 'Saved synthetic editor screenshot, verification renders, MP4 and GIF to docs/media/.'
