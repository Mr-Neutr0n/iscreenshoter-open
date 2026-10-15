# Manual acceptance checklist

Run these checks with a disposable account or synthetic desktop content. Record
pass, fail, or not tested for each applicable case. A CI pass covers synthetic
rendering and encoding, not permission prompts or real audio capture.

| Case | Expected result |
| --- | --- |
| Fresh install with permission denied | Capture and recording explain the missing permission and remain usable after cancellation. No empty output is reported as success. |
| Grant screen permission and reopen | Region and window capture produce the selected content. |
| Revoke permission in System Settings | The next capture fails clearly; granting and reopening recovers. |
| Screenshot and OCR shortcuts from another app | One action fires once. Editing shortcut bindings suspends delivery; cancellation and conflicts recover. |
| Annotate, undo, copy, save, quick save | Clipboard and exported files contain the intended crop and annotations. Filename collisions do not overwrite existing files. |
| Copy-to-corner and Reduce Motion | Preview reaches the selected display's corner. Reduce Motion avoids travel. |
| History off, then enabled | Copy creates no retained cache when off. Enabled history respects configured retention. |
| Remove from history, then Trash export | Removing a reference preserves the export. Trash requires the separately named action and only affects the selected file. |
| Large history fixture | History remains responsive with bounded, downsampled thumbnails. |
| Record screen and window, with system audio | MP4 plays with expected frames and audible synthetic system audio. No microphone recording is implied. |
| Close recorder controls while recording | Recording stops and saves. The menu bar clears its recording state after finalization. |
| Stop recording and quit | Output is finalized and playable; no orphan capture session continues. |
| Connect, rearrange and disconnect displays | Selection, preview and pin geometry remain on valid screens. Test Retina and mixed scale displays. |
| Sleep and wake while idle and recording | App recovers or stops clearly; recording output remains usable. |
| Change application focus, Spaces and full screen | Capture/editor controls keep the intended focus and can be dismissed. |
| Drag preview to Finder and another app | Supported receivers get the intended image without duplicate windows. |
| Keyboard and VoiceOver | Controls expose labels, history removal and Trash remain distinguishable, and keyboard focus can reach primary actions. |
| Disable login item and uninstall | The app stops launching at login and documented data paths can be removed. |

For each release, publish a short table like this in its release notes:

| Environment | Automated | Manual |
| --- | --- | --- |
| macOS / architecture / Xcode from build manifest | CI run link and result | Specific cases checked, or "Not run" |

Do not mark a case as passed based on source inspection. Document known failures
and untested cases before publishing. Copy the Xcode, SDK, architecture and source
commit from the released build manifest so the result refers to the actual ZIP.
