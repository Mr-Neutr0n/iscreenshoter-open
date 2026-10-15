# Releasing

Only a maintainer publishes releases. Use a clean checkout of `main`, with CI
passing and the relevant manual results recorded. Review screenshots for private
data. Update `Info.plist`, `CHANGELOG.md` and the release notes before tagging.

```sh
./verify
git tag v1.1.0
git push origin v1.1.0
```

The Release workflow checks out that tag, builds from an empty staging directory,
runs verification, packages the app with its license, notices, README and build
manifest, then attests the ZIP and publishes the release. An existing tag can be
retried through workflow_dispatch. Do not move a published version tag.

For local packaging of the same clean, verified checkout:

```sh
./scripts/package-release.sh v1.1.0
```

The script rejects a dirty tree, a mismatched tag or app version, and a build
manifest that names a different source commit. Outputs go to ignored `dist/`.
The manifest records Xcode, SDK, Swift, macOS, architecture, source hashes and a
UTC timestamp. Compiler output and signatures may vary across toolchains and
runs. Bit-for-bit reproducibility is not claimed.

Verify a download against its checksums and GitHub provenance:

```sh
shasum -a 256 -c Screen-Shoter-Open-v1.1.0-arm64-SHA256SUMS.txt
gh attestation verify Screen-Shoter-Open-v1.1.0-arm64.zip --repo Mr-Neutr0n/iscreenshoter-open
```

The current hosted workflow uses ad-hoc signing. For a local Developer ID build,
install a valid Developer ID Application certificate in the login keychain and
set `SCREENSHOTER_SIGNING_IDENTITY` to its identity name before building. The
build requests a secure timestamp and hardened runtime. Certificate installation
and notarization need the owner's Apple Developer credentials and are not
performed by this repository. Do not commit certificates, passwords or keys.
A Developer ID signature alone is not notarization. Do not label a download
notarized unless `spctl` and the stapled notarization ticket validate it.

The CI workflow runs with read-only repository access. Release publishing gets
contents, OIDC and attestation write permissions only in the release job. Actions
are pinned to commit SHAs. Dependabot proposes monthly updates. GitHub's standard
[`macos-15` runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
is ARM64 for this public repository. The manifest records the selected hosted
Xcode version because the runner image changes over time.
