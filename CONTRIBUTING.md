# Contributing

Use an Apple Silicon Mac with macOS 14 or later and full Xcode selected. The
project has no package dependencies. See the README for build commands.

1. Open an issue for a large behavior change. Small fixes can start as a pull request.
2. Keep one problem per pull request. Explain the before and after behavior.
3. Run `./verify`. Add a meaningful check for behavior that can fail silently.
4. For capture, focus, recording, permission, or display changes, complete the
   relevant cases in [the acceptance checklist](docs/ACCEPTANCE.md).
5. Use synthetic content in screenshots and recordings. Never attach private captures.

The code uses Swift 5 language mode, AppKit and SwiftUI. Match nearby code. Avoid
new packages or abstractions for a single call site. New artwork must be your
own or have a compatible license, with its origin in `THIRD_PARTY_NOTICES.md`.
Do not copy proprietary binaries, artwork, or decompiled source into this repo.

CI must pass before merge. Review may take time because this is a spare-time
project with one active maintainer. There is no response-time or release SLA.
The latest release is supported on a best-effort basis. Intel Macs and macOS
versions below 14 are not supported. A passing synthetic suite does not establish
full behavior parity with another app.

Report bugs with the app version, macOS version, architecture, exact steps,
expected result, and whether permissions were granted. Redact paths and private
screen content. Report security issues privately as described in `SECURITY.md`.

The maintainer may request changes, defer work, or close proposals outside the
project scope. Contributions use the repository's MIT license. No CLA is required.
