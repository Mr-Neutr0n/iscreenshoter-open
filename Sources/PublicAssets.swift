import AppKit

// Artwork is drawn by scripts/generate-resources.swift and licensed with this project.
func publicAsset(_ name: String) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
          let image = NSImage(contentsOf: url) else { return nil }
    guard let bitmap = image.representations.first as? NSBitmapImageRep else { return nil }
    image.size = NSSize(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
    if name == "icon_topbar" { image.isTemplate = true }
    return image
}
