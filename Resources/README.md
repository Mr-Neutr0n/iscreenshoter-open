All resources in this directory are independently authored for this project and distributed under the repository's MIT license.

`scripts/generate-resources.swift` draws the icons and stickers from geometric paths using AppKit. It also writes the numeric color catalog and app icon. The generator reads no original app files and uses no extracted image assets, fonts, or compiled asset catalogs.

The resource aliases in `Icons` correspond to the source's UI roles. They do not imply ownership of similarly named artwork in another app. Public artwork differs from iScreen Shoter's artwork. The public app uses its own fade transition instead of the original app's animation.

Run the generator from the repository root:

```sh
swift scripts/generate-resources.swift
```
