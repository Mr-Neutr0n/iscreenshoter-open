# Screen Shoter Open

An independent, open-source alternative to **iScreen Shoter** for macOS.
Capture, annotate, pin, extract text, and record locally. No account, subscriptions,
analytics, or cloud services. All implemented tools are available for free.

This is an unofficial reconstruction inspired by iScreen Shoter's workflows. It
is not the original app's source code or an official open-source release. The
public build uses its own artwork. It does not claim pixel-perfect equivalence.

![Screenshot editor](docs/media/editor.png)

![Scripted annotation demo](docs/media/annotation-demo.gif)

[Watch or download the MP4 demo](docs/media/annotation-demo.mp4)

The images and video show production native views with synthetic sample content.
The annotation video is scripted and rendered offscreen. It is not a recording
of someone's desktop. Reproduce the media with `./scripts/render-demo.sh`.

## Features

- Region and window selection, magnification, color sampling, and adjustable capture bounds.
- Rectangle, oval, line, arrow, pen, mosaic, multiline text, stickers, and imported images.
- Annotation movement, resizing, and undo.
- PNG clipboard copy, JPG/PNG/PDF exports, quick save, and the macOS share sheet.
- Optional, bounded screenshot history, animated copy-to-corner previews, drag-out, Finder reveal, and explicit Trash deletion.
- Local Apple Vision OCR with editable results and table formatting.
- Floating pins with preset or custom scale.
- Screen or window recording to H.264 MP4, with optional system audio.
- Custom global shortcuts, save directory, and optional launch at login.

Cloud OCR, translation, purchases, analytics, and the original app's external
recorder integration are excluded. Screen recording is implemented locally.

## Install

Requires **Apple Silicon** and **macOS 14 or later**. Source builds need full
Xcode and its selected command-line tools, plus `python3` for build metadata.
Command Line Tools alone do not include the asset catalog compiler. Select your
installed Xcode with `sudo xcode-select --switch /Applications/Xcode.app`, then
accept its license if prompted. The maintainer uses Xcode 26.6 with SDK 26.5;
CI records its current Xcode/SDK versions in each build manifest.

```sh
git clone https://github.com/Mr-Neutr0n/iscreenshoter-open.git
cd iscreenshoter-open
./build.sh
open 'build/Screen Shoter Open.app'
```

You can also download the app ZIP from [Releases](https://github.com/Mr-Neutr0n/iscreenshoter-open/releases).
The app is ad-hoc signed and is not notarized. Build from source if macOS blocks
the downloaded app. Move the app to `/Applications` before enabling launch at login.

For a release ZIP, download its checksum file too and run the command in
[release verification](docs/RELEASING.md). Published CI builds include GitHub
artifact attestations. The app has no automatic updater; install a newer release
manually after quitting the old copy. See [the changelog](CHANGELOG.md).

Screen capture requires permission in **System Settings > Privacy & Security >
Screen & System Audio Recording**. Grant it to **Screen Shoter Open** and reopen
the app if macOS requests it. OCR runs entirely on your Mac.

## Shortcuts

| Action | Default |
| --- | --- |
| Screenshot | Command + Shift + A |
| OCR capture | Command + Shift + T |
| Copy in editor | Command + C |
| Save in editor | Command + S |
| Quick save in editor | Command + Return |
| Undo in editor | Command + Z |
| Cancel capture/editor | Escape |

Change the global shortcuts in Settings. Quit other apps that own the same
combination. Failed registrations retry when another application exits.

Copying a capture now shrinks and moves it into the corner with the native macOS
window animation. [Motion evidence and validation](docs/MOTION.md).

## More screenshots

| Settings | OCR |
| --- | --- |
| ![Settings](docs/media/settings-general.png) | ![Local OCR](docs/media/ocr-complete.png) |

![Editor toolbar](docs/media/editor-toolbar.png)

![Color and width palette](docs/media/editor-palette.png)

[Palette appearance correction](docs/PALETTE.md).

## Build and verification

No third-party packages are needed. The project builds with `swiftc` and `actool`.

```sh
./verify
```

Verification builds and checks the signature, then exercises annotation rendering,
crop orientation, toolbar geometry, previews, Settings, pin layout, asset loading,
shortcut registration, JPG/PNG/PDF export, Vision recognition, and H.264 encoding
with decoded frames. Each verification or demo process creates a temporary
workspace and a fresh preference suite, then removes both on exit. It never
loads your real capture history or exports into your normal save directory.
Tests use synthetic content and do not grant screen access. Demo output is
staged in a temporary directory and copied to `docs/media` only after success.

These checks do not prove live desktop capture, system audio, shortcut delivery
between applications, drag receivers, or behavior on every display arrangement.
Some popup placement, focus, animation timing, and alternate pin interactions
still need manual testing. See [development notes](docs/DEVELOPMENT.md).

## Privacy

Captures and recordings stay on your Mac. Copying puts the image on the system
clipboard. Screenshot history is **off by default**, including after upgrading.
Enable it in Settings > Privacy if you want retained copies. Enabled history
retains captures for 7 days, up to 200 items or 100 MB, whichever limit is hit
first. Expiry is checked at startup, when history is accessed, and hourly while the app runs. It is not a background service.
Turning history off clears cached captures. Clear History in Privacy settings also
removes history references while preserving exported files.

Cached images live beneath
`~/Library/Caches/org.hari.screenshoter.open/Image`. Exports and recordings use
your selected save folder and remain until you remove them. Removing an export
from history only removes its reference. The separate, confirmed Move to Trash
action moves the selected exported file to the system Trash. The app never
expires exports outside its cache. Clearing the cache does not empty the system
clipboard or your Trash.

The app has no networking client, account system, telemetry, or updater. Reports
and GitHub downloads use your browser or development tools, not an app service.

## Uninstall

1. Stop any recording. In Settings, turn off launch at login, then quit the app.
2. Check System Settings > General > Login Items and remove or disable Screen
   Shoter Open if it remains listed.
3. Delete `Screen Shoter Open.app` from Applications or your build directory.
4. To remove cached captures, delete
   `~/Library/Caches/org.hari.screenshoter.open`. To remove preferences, run
   `defaults delete org.hari.screenshoter.open` after quitting the app.
5. In System Settings > Privacy & Security > Screen & System Audio Recording,
   remove or disable the app's permission. The exact label varies by macOS version.

Exports and recordings in other folders are not removed by uninstalling. Review
those folders separately. Empty the system Trash only if you intend to delete
its contents permanently.

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) for development and review expectations,
[SECURITY.md](SECURITY.md) for private reports, and
[the conduct policy](CODE_OF_CONDUCT.md) for community rules. This volunteer
project has one active maintainer and no response or release SLA. The latest
release receives best-effort support. Intel and macOS below 14 are unsupported.

Pull requests run macOS ARM64 CI. Maintainers use
[manual acceptance checks](docs/ACCEPTANCE.md) for permission, audio, sleep,
display and focus behavior. Release notes distinguish automated results from
manual cases that remain untested. See [release tooling](docs/RELEASING.md).

The implementation and generated resources are [MIT licensed](LICENSE).
See [resource provenance](THIRD_PARTY_NOTICES.md) for the scope of that license.
