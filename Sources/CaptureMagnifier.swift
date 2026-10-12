import AppKit

// VRViewMagnifier constructor 0x100068858, parent 0x100091a30 and update 0x100069960.
final class CaptureMagnifier: NSView {
    let viewport = NSView(frame: NSRect(x: 2, y: 50, width: 96, height: 92))
    let imageView = NSImageView()
    let info = NSTextField(labelWithString: "")
    private let horizontal = NSBox()
    private let vertical = NSBox()
    private var lastInfoUpdate = -Double.infinity
    init(image: CGImage, screenSize: NSSize) {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 144))
        wantsLayer = true
        let background = NSView(frame: bounds); background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        background.layer?.cornerRadius = 4; background.layer?.masksToBounds = true
        addSubview(background)
        viewport.wantsLayer = true; viewport.layer?.masksToBounds = true; addSubview(viewport)
        imageView.image = NSImage(cgImage: image, size: screenSize)
        imageView.imageScaling = .scaleAxesIndependently; viewport.addSubview(imageView)
        let color = NSColor(calibratedRed: 35 / 255, green: 190 / 255, blue: 65 / 255, alpha: 1)
        for box in [horizontal, vertical] { box.boxType = .custom; box.borderWidth = 0; box.fillColor = color; viewport.addSubview(box) }
        horizontal.frame = NSRect(x: 0, y: 45.5, width: 96, height: 1)
        vertical.frame = NSRect(x: 47.5, y: 0, width: 1, height: 92)
        info.frame = NSRect(x: -50, y: 5, width: 200, height: 40)
        info.alignment = .center; info.textColor = .white; info.isBordered = false; info.drawsBackground = false
        info.font = .systemFont(ofSize: 10, weight: .medium); addSubview(info)
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    func update(pointer: NSPoint, selection: NSRect, screenSize: NSSize, hex: String, now: Double = ProcessInfo.processInfo.systemUptime) {
        // SelectionView is flipped. Original magnifier and its image are not.
        var x = pointer.x + 36
        if x + bounds.width >= screenSize.width { x = pointer.x - 36 - bounds.width }
        let y = pointer.y + bounds.height < screenSize.height ? pointer.y : pointer.y - bounds.height
        frame.origin = NSPoint(x: x, y: y)
        imageView.frame = NSRect(x: 48 - pointer.x * 5, y: 46 - (screenSize.height - pointer.y) * 5, width: screenSize.width * 5, height: screenSize.height * 5)
        isHidden = false
        guard now - lastInfoUpdate >= 0.2 else { return }; lastInfoUpdate = now
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing = 1.5; paragraph.lineBreakMode = .byTruncatingTail
        // 0x10006a520 replaces the constructor's 10pt font with 9pt for attributed updates.
        info.attributedStringValue = NSAttributedString(string: "\(Int(selection.width)) * \(Int(selection.height))\r\(hex)\r(Press “C” to copy)", attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
    static func verifyRendering() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<300 { for x in 0..<400 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        let view = CaptureMagnifier(image: bitmap.cgImage!, screenSize: NSSize(width: 200, height: 150))
        view.update(pointer: NSPoint(x: 40, y: 4), selection: NSRect(x: 0, y: 0, width: 100, height: 80), screenSize: NSSize(width: 200, height: 150), hex: "#123456", now: 1)
        guard view.frame.size == NSSize(width: 100, height: 144), view.viewport.frame == NSRect(x: 2, y: 50, width: 96, height: 92), view.frame.minX == 76, view.info.stringValue == "100 * 80\r#123456\r(Press “C” to copy)", view.info.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NSFont.systemFont(ofSize: 9, weight: .medium) else { throw NSError(domain: "CaptureMagnifier", code: 1) }
        view.update(pointer: NSPoint(x: 190, y: 140), selection: .zero, screenSize: NSSize(width: 200, height: 150), hex: "#FFFFFF", now: 1.1)
        guard view.frame.minX == 54, view.frame.minY == -4, view.info.stringValue.hasPrefix("100 * 80") else { throw NSError(domain: "CaptureMagnifier", code: 2) }
        view.update(pointer: NSPoint(x: 190, y: 140), selection: .zero, screenSize: NSSize(width: 200, height: 150), hex: "#FFFFFF", now: 1.3)
        guard view.info.stringValue.contains("#FFFFFF") else { throw NSError(domain: "CaptureMagnifier", code: 3) }
        view.frame.origin = .zero
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "CaptureMagnifier", code: 4) }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let output = ProcessInfo.processInfo.environment["ISCREENSHOTER_RENDER_DIR"], let data = rep.representation(using: .png, properties: [:]) { try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("capture-magnifier.png")) }
        guard let sampled = rep.colorAt(x: rep.pixelsWide / 5, y: rep.pixelsHigh / 5), sampled.redComponent > 0.7, sampled.redComponent > sampled.greenComponent + 0.5, sampled.redComponent > sampled.blueComponent + 0.5 else { throw NSError(domain: "CaptureMagnifier", code: 5, userInfo: [NSLocalizedDescriptionKey: "Magnifier lost the source image during native rendering"]) }
        if let output = ProcessInfo.processInfo.environment["ISCREENSHOTER_RENDER_DIR"], let data = rep.representation(using: .png, properties: [:]) { try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("capture-magnifier.png")) }
    }
}
