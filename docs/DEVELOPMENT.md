# Development notes

The implementation was informed by REA analysis of iScreen Shoter 3.0.2 build 28
and reference screenshots. The private lab retained its binary and analysis
records. They are not included in this repository. Public source implements the
workflows using macOS frameworks and independently generated resources.

## Source map

| File | Responsibility |
| --- | --- |
| `main.swift` | Menu bar, application lifecycle, global shortcuts, cache/history, verification entry point |
| `Capture.swift`, `CaptureMagnifier.swift` | ScreenCaptureKit capture, selection overlay, magnifier |
| `Editor.swift` | Annotation model, native renderer, selection, tools, editor controls |
| `Home.swift`, `Preview.swift` | History, thumbnail interactions, drag-out |
| `Save.swift` | Save dialog, export formats, collision protection |
| `OCR.swift` | Vision recognition, editable results, table ordering |
| `Pin.swift` | Floating image windows and scaling |
| `Settings.swift` | SwiftUI settings and shortcut recorder |
| `Recorder.swift` | ScreenCaptureKit stream, AVAssetWriter video/audio output |
| `PublicAssets.swift` | Generated resource loading |

Run `./verify` after changing behavior. Use `./scripts/render-demo.sh` to rebuild
native view screenshots and the scripted annotation video. No desktop automation
is required for these render checks. Verify real capture and focus behavior by
using the app manually with the required macOS permissions.

## Intentional differences

- Original proprietary artwork is replaced with independent generated icons and stickers.
- Corner previews use a simple fade instead of the original destruction animation.
- ScreenCaptureKit replaces older screenshot APIs.
- Recording is local, instead of launching the original external recorder.
- Shortcuts retry registration when another application exits.
- The public app has a separate name, bundle identifier, preference store, and cache.
- Cloud features, subscriptions, translation, support links, analytics, and update checks are omitted.

There is no claim that every original feature or visual state has been reproduced.
Remaining comparison gaps include selected annotation chrome, some hover/popup
states, edge placement, preview entrance timing, custom OCR dropdown behavior,
and alternate pin drag affordances.
