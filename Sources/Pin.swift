import AppKit
import SwiftUI

private final class PinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
}

private final class MovablePinImage: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class PinScaleButton: NSButton {
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let text = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 0, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if let arrow = publicAsset("pin_arrow") {
            arrow.draw(in: NSRect(x: size.width + 6, y: (bounds.height - arrow.size.height) / 2, width: arrow.size.width, height: arrow.size.height))
        }
    }
}

private struct PinScaleOptions: View {
    let selected: Int
    let choose: (Int) -> Void
    @State private var hovered: Int?
    var body: some View {
        VStack(spacing: 0) {
            ForEach([50, 100, 200], id: \.self) { percentage in
                Button { choose(percentage) } label: {
                    Text("\(percentage)%")
                        .font(.system(size: 14))
                        .foregroundColor(percentage == selected ? Color(.sRGB, red: 231/255, green: 254/255, blue: 102/255) : .white)
                        .frame(width: 52, height: 24)
                        .background(hovered == percentage ? Color(.sRGB, red: 72/255, green: 72/255, blue: 72/255) : .clear)
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? percentage : nil }
            }
        }
        .padding(.vertical, 5)
        .background(Color(.sRGB, red: 58/255, green: 58/255, blue: 58/255))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private final class PinRootView: NSView {
    var hover: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area!)
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
}

private final class PinDragView: NSImageView, NSDraggingSource {
    var screenshot: NSImage?
    private var initialEvent: NSEvent?
    private var temporaryURLs: [URL] = []
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { initialEvent = event }
    override func mouseDragged(with event: NSEvent) {
        guard let first = initialEvent, let screenshot else { return }
        let start = first.locationInWindow, point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        do {
            let url = try Self.makeFile(screenshot)
            temporaryURLs.append(url)
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: screenshot)
            initialEvent = nil
            beginDraggingSession(with: [item], event: first, source: self)
        } catch { alert("Could not drag screenshot: \(error.localizedDescription)") }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    private static func makeFile(_ image: NSImage) throws -> URL {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 1]) else {
            throw NSError(domain: "PinDrag", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode screenshot"])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iScreenShoterLocal-PinDrag", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Screen Shoter Open - \(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
    deinit {
        // A receiver can read the file after the drag callback returns. Keep it until this pin closes.
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
    }
}

final class PinController: NSWindowController, NSWindowDelegate {
    private static var retained: [PinController] = []
    private let screenshot: NSImage
    private let imageView = MovablePinImage()
    private let controls = NSView()
    private let topBand = NSView()
    private let scale = PinScaleButton()
    private let copyButton = NSButton()
    private let dragView = PinDragView()
    private var feedbackID = 0
    private let scalePopover = NSPopover()

    static func open(image: NSImage, frame: NSRect? = nil) {
        let controller = PinController(image: image, frame: frame)
        retained.append(controller); controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }
    private init(image: NSImage, frame supplied: NSRect?) {
        screenshot = image
        let width = max(1, image.size.width), height = max(1, image.size.height)
        let windowFrame: NSRect
        if let supplied, supplied.width > 0, supplied.height > 0 { windowFrame = supplied }
        else {
            let factor = min(1, 700 / width, 520 / height)
            windowFrame = NSRect(x: 0, y: 0, width: width * factor, height: height * factor)
        }
        let window = PinWindow(contentRect: windowFrame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("VRPinView-\(UUID().uuidString)")
        window.title = ""; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.level = .floating
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        window.collectionBehavior = NSWindow.CollectionBehavior(rawValue: 0x85)
        window.appearance = NSAppearance(named: .aqua); window.aspectRatio = NSSize(width: width, height: height)
        window.minSize = NSSize(width: 80, height: max(40, 80 * height / width))
        super.init(window: window)
        window.delegate = self
        if supplied == nil { window.center() }
        let root = PinRootView(frame: NSRect(origin: .zero, size: windowFrame.size))
        window.contentView = root
        imageView.image = image; imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = root.bounds; imageView.autoresizingMask = [.width, .height]
        root.addSubview(imageView)
        topBand.frame = NSRect(x: 0, y: root.bounds.height - 35, width: 35, height: 35)
        topBand.autoresizingMask = [.minYMargin]; topBand.wantsLayer = true
        topBand.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor; root.addSubview(topBand)
        controls.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: 42)
        controls.autoresizingMask = [.width, .maxYMargin]; controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor; root.addSubview(controls)
        scale.title = "100%"
        scale.isBordered = false; scale.font = .systemFont(ofSize: 16); scale.target = self; scale.action = #selector(changeScale)
        scale.frame = NSRect(x: 9, y: 9, width: 64, height: 24); controls.addSubview(scale)
        copyButton.title = ""; copyButton.image = publicAsset("Icon_pin_copy")
        copyButton.toolTip = "Copy"; copyButton.target = self; copyButton.action = #selector(copyImage); copyButton.isBordered = false
        let save = NSButton(); save.image = publicAsset("Icon_pin_save")
        save.title = ""; save.isBordered = false; save.toolTip = "Save"; save.target = self; save.action = #selector(saveImage)
        copyButton.frame = NSRect(x: root.bounds.width - 73, y: 9, width: 24, height: 24)
        save.frame = NSRect(x: root.bounds.width - 33, y: 9, width: 24, height: 24)
        for button in [copyButton, save] {
            button.contentTintColor = .white; button.imageScaling = .scaleProportionallyUpOrDown
            button.autoresizingMask = [.minXMargin]; controls.addSubview(button)
        }
        dragView.image = publicAsset("bar_drag"); dragView.imageScaling = .scaleAxesIndependently
        dragView.screenshot = image; dragView.toolTip = "Drag screenshot to another app or folder"
        dragView.frame = NSRect(x: (root.bounds.width - 62)/2, y: 9, width: 62, height: 24)
        dragView.autoresizingMask = [.minXMargin, .maxXMargin]; controls.addSubview(dragView)
        root.hover = { [weak self] inside in
            self?.controls.isHidden = !inside; self?.topBand.isHidden = !inside
            self?.window?.standardWindowButton(.closeButton)?.isHidden = !inside
        }
        controls.isHidden = true; topBand.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        updateScale()
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { feedbackID += 1; Self.retained.removeAll { $0 === self } }
    func windowDidResize(_ notification: Notification) { updateScale() }
    private func updateScale() {
        guard let window else { return }
        let ratio = window.contentLayoutRect.width / max(1, screenshot.size.width)
        scale.title = "\(Int((ratio * 100).rounded()))%"; scale.needsDisplay = true
    }
    @objc private func changeScale() {
        if scalePopover.isShown { scalePopover.performClose(nil); return }
        let controller = NSViewController()
        let selected = Int(scale.title.dropLast()) ?? 100
        let options = PinScaleOptions(selected: selected) { [weak self] percentage in
            guard let self, let window = self.window else { return }
            self.scalePopover.performClose(nil)
            let ratio = CGFloat(percentage) / 100
            let size = NSSize(width: self.screenshot.size.width * ratio, height: self.screenshot.size.height * ratio)
            let top = window.frame.maxY
            window.setFrame(NSRect(x: window.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true, animate: true)
            self.updateScale()
        }
        controller.view = NSHostingView(rootView: options)
        controller.view.frame = NSRect(x: 0, y: 0, width: 52, height: 82)
        scalePopover.contentViewController = controller
        scalePopover.contentSize = controller.view.frame.size
        scalePopover.behavior = .transient
        scalePopover.appearance = NSAppearance(named: .darkAqua)
        scalePopover.show(relativeTo: scale.bounds, of: scale, preferredEdge: .minY)
    }
    @objc private func copyImage() {
        guard let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [.compressionFactor: 1]) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png, forType: .png)
        feedbackID += 1; let identity = feedbackID
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.feedbackID == identity else { return }
            self.copyButton.image = publicAsset("Icon_pin_copy") ?? NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        }
    }
    @objc private func saveImage() { SaveController.present(image: screenshot, parentWindow: window) }
    static func verifyLayout() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "PinVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let pin = PinController(image: NSImage(size: NSSize(width: 400, height: 300)), frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        try require(pin.window?.collectionBehavior.rawValue == 0x85, "Pin window must use the recovered space collection mask")
        try require(pin.controls.frame.height == 42 && pin.topBand.frame.size == NSSize(width: 35, height: 35), "Pin hover regions must retain the recovered geometry")
        let popup = NSHostingView(rootView: PinScaleOptions(selected: 100, choose: { _ in }))
        let size = popup.fittingSize
        try require(abs(size.width - 52) < 0.01 && abs(size.height - 82) < 0.01, "Recovered scale rows and padding must produce a 52 by 82 popup body")
        popup.frame = NSRect(origin: .zero, size: size)
        try writeParityRender(popup, name: "pin-scale-menu")
        pin.close()
    }
    @objc private func closePin() { window?.close() }
}
