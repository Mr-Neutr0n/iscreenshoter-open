import AppKit

private struct PreviewLifetime {
    var hovered = false
    var retainedByDrag = false
    var closing = false
    var deadline: TimeInterval? = 5
    mutating func enter() { hovered = true; deadline = nil }
    mutating func exit(at now: TimeInterval) { hovered = false; deadline = retainedByDrag || closing ? nil : now + 5 }
    mutating func dragged() { retainedByDrag = true; deadline = nil }
    mutating func dismiss() { closing = true; deadline = nil }
    func expired(at now: TimeInterval) -> Bool { !hovered && !retainedByDrag && !closing && deadline.map { now >= $0 } == true }
}

private final class PreviewSurface: NSView {
    var image: NSImage?
    var fill: NSColor = .white
    var hover: ((Bool) -> Void)?
    var move: ((NSEvent) -> Void)?
    var pointerMoved: (() -> Void)?
    var tracksPointer = true
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard tracksPointer else { return }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
    override func mouseDown(with event: NSEvent) { if let move { move(event) } else { super.mouseDown(with: event) } }
    override func mouseMoved(with event: NSEvent) { pointerMoved?() }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill(); bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        image.draw(in: NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height))
    }
}

private final class PreviewCircle: NSButton {
    let glyph: NSImage?
    let glyphSize: CGFloat
    let hoverColor: NSColor
    let darkHoverGlyph: Bool
    private var inside = false
    private var defaultAlpha: CGFloat
    private var area: NSTrackingArea?
    init(asset: String, size: CGFloat, glyphSize: CGFloat, hoverColor: NSColor, darkHoverGlyph: Bool, initialAlpha: CGFloat = 0.6, target: AnyObject, action: Selector) {
        defaultAlpha = initialAlpha
        glyph = publicAsset(asset); self.glyphSize = glyphSize; self.hoverColor = hoverColor; self.darkHoverGlyph = darkHoverGlyph
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        self.target = target; self.action = action; isBordered = false; title = ""
    }
    required init?(coder: NSCoder) { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self); addTrackingArea(area!)
    }
    override func mouseEntered(with event: NSEvent) { inside = true; defaultAlpha = 0.6; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { inside = false; defaultAlpha = 0.6; needsDisplay = true }
    func resetRestingAlpha() { defaultAlpha = 0.6; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        (inside ? hoverColor : NSColor.black.withAlphaComponent(defaultAlpha)).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        guard let glyph else { return }
        let rect = NSRect(x: (bounds.width-glyphSize)/2, y: (bounds.height-glyphSize)/2, width: glyphSize, height: glyphSize)
        let colored = NSImage(size: glyph.size, flipped: false) { box in
            glyph.draw(in: box); (self.inside && self.darkHoverGlyph ? NSColor.black : NSColor.white).setFill(); box.fill(using: .sourceAtop); return true
        }
        colored.draw(in: rect)
    }
}

final class HistoryPreviewController: NSWindowController, NSWindowDelegate {
    static var retained: [HistoryPreviewController] = []
    let image: NSImage
    let url: URL
    static func open(url: URL) {
        guard let image = NSImage(contentsOf: url) else { alert("Could not open this image."); return }
        let controller = HistoryPreviewController(image: image, url: url)
        retained.append(controller); controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    init(image: NSImage, url: URL) {
        self.image = image; self.url = url
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 300), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = ""; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 393, height: 262); window.center(); window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear; window.isMovableByWindowBackground = true
        super.init(window: window); window.delegate = self
        let root = PreviewSurface(frame: NSRect(x: 0, y: 0, width: 450, height: 300)); root.image = image
        root.wantsLayer = true; root.layer?.cornerRadius = 5; root.layer?.masksToBounds = true; window.contentView = root
        root.move = { [weak window] event in window?.performDrag(with: event) }
        let bar = NSView(frame: NSRect(x: 0, y: 276, width: 450, height: 24)); bar.wantsLayer = true; bar.autoresizingMask = [.width, .minYMargin]; root.addSubview(bar)
        // The archived top view contains an empty rounded box, not a filename label.
        let box = NSBox(frame: NSRect(x: 0, y: -6, width: 450, height: 30))
        box.boxType = .custom; box.titlePosition = .noTitle; box.borderType = .noBorder
        box.fillColor = .black.withAlphaComponent(0.4); box.cornerRadius = 4
        box.contentViewMargins = .zero; box.autoresizingMask = [.width]; bar.addSubview(box)
        let controls = NSView(frame: NSRect(x: 145, y: 12, width: 160, height: 40)); controls.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]; root.addSubview(controls)
        let lime = NSColor(calibratedRed: 231/255, green: 254/255, blue: 102/255, alpha: 1)
        for (index, spec) in [("icon_copy", #selector(copyImage), CGFloat(28), lime, true), ("icon_openfolder", #selector(revealImage), CGFloat(28), lime, true), ("icon_delete", #selector(deleteImage), CGFloat(24), NSColor.red, false)].enumerated() {
            let button = PreviewCircle(asset: spec.0, size: 40, glyphSize: spec.2, hoverColor: spec.3, darkHoverGlyph: spec.4, initialAlpha: index < 2 ? 0.6047217767 : 0.6, target: self, action: spec.1); button.frame.origin.x = CGFloat(index * 60); controls.addSubview(button)
        }
        controls.isHidden = true; root.hover = { inside in controls.isHidden = !inside }
        root.pointerMoved = { [weak controls] in controls?.subviews.compactMap { $0 as? PreviewCircle }.forEach { $0.resetRestingAlpha() } }
    }
    required init?(coder: NSCoder) { nil }
    static func copy(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png, forType: .png)
    }
    @objc private func copyImage() { Self.copy(image) }
    @objc private func revealImage() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    @objc private func deleteImage() { do { try HistoryStore.shared.trash(url); close() } catch { alert(error.localizedDescription) } }
    func windowWillClose(_ notification: Notification) { Self.retained.removeAll { $0 === self } }
}

final class FloatingPreviewController: NSWindowController, NSWindowDelegate {
    static var retained: [FloatingPreviewController] = []
    private let image: NSImage
    private var lifetime = PreviewLifetime()
    private var timer: Timer?
    private let controls = NSView()
    private let imageContainer = PreviewSurface()
    private let closeButton = NSButton()
    static func open(image: NSImage, url: URL, screenFrame: NSRect? = nil, sourceFrame: NSRect? = nil) {
        let controller = FloatingPreviewController(image: image, frame: screenFrame)
        retained.append(controller)
        controller.present(from: sourceFrame)
        controller.scheduleDismissal()
    }
    // REA copy path 0x100043008: start at the global cut rect, then use
    // setFrame:display:animate:. AppKit owns the duration and interpolation.
    private func present(from sourceFrame: NSRect?) {
        guard let window else { return }
        let destination = window.frame
        let source = Self.validSourceFrame(sourceFrame)
        if let source { window.setFrame(source, display: false) }
        showWindow(nil)
        if source != nil {
            window.setFrame(destination, display: true,
                            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }
    private static func validSourceFrame(_ frame: NSRect?) -> NSRect? {
        guard let frame, frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
    private init(image: NSImage, frame: NSRect?) {
        self.image = image
        let screen = frame.flatMap { rect in NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } } ?? NSScreen.main
        let area = screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let panel = NSWindow(contentRect: NSRect(x: area.maxX-200, y: area.minY+50, width: 150, height: 100), styleMask: NSWindow.StyleMask(rawValue: 0x8009), backing: .buffered, defer: false)
        panel.setFrame(NSRect(x: area.maxX - 200, y: area.minY + 50, width: 150, height: 100), display: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(kind)?.isHidden = true }
        panel.level = NSWindow.Level(rawValue: 101); panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.isMovableByWindowBackground = true
        super.init(window: panel); panel.delegate = self
        let root = PreviewSurface(frame: NSRect(x: 0, y: 0, width: 150, height: 100)); root.fill = .clear
        imageContainer.frame = root.bounds; imageContainer.image = image
        imageContainer.fill = NSColor(calibratedWhite: 200/255, alpha: 1); imageContainer.tracksPointer = false
        imageContainer.autoresizingMask = [.width, .height]; root.addSubview(imageContainer)
        root.wantsLayer = true; root.layer?.cornerRadius = 5; root.layer?.masksToBounds = true; panel.contentView = root
        root.hover = { [weak self] inside in self?.hoverChanged(inside) }
        root.move = { [weak self] event in self?.movePreview(event) }
        controls.frame = NSRect(x: 29, y: 32, width: 92, height: 36); imageContainer.addSubview(controls)
        let save = PreviewCircle(asset: "icon_save", size: 36, glyphSize: 24, hoverColor: NSColor(calibratedRed: 231/255, green: 254/255, blue: 102/255, alpha: 1), darkHoverGlyph: true, initialAlpha: 0.6047217767, target: self, action: #selector(saveImage)); controls.addSubview(save)
        let delete = PreviewCircle(asset: "icon_delete", size: 36, glyphSize: 24, hoverColor: NSColor(calibratedRed: 253/255, green: 75/255, blue: 75/255, alpha: 1), darkHoverGlyph: false, target: self, action: #selector(dismissPreview)); delete.frame.origin.x = 56; controls.addSubview(delete)
        closeButton.frame = NSRect(x: 126, y: 76, width: 20, height: 20); closeButton.title = ""; closeButton.image = publicAsset("icon_close_black"); closeButton.imageScaling = .scaleProportionallyUpOrDown; closeButton.isBordered = false; closeButton.target = self; closeButton.action = #selector(dismissPreview); imageContainer.addSubview(closeButton)
        root.pointerMoved = { [weak controls] in controls?.subviews.compactMap { $0 as? PreviewCircle }.forEach { $0.resetRestingAlpha() } }
        controls.isHidden = true; closeButton.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    private func hoverChanged(_ inside: Bool) {
        guard !lifetime.closing else { return }
        if inside { lifetime.enter(); timer?.invalidate(); timer = nil }
        else { lifetime.exit(at: Date.timeIntervalSinceReferenceDate); scheduleDismissal() }
        controls.isHidden = !inside; closeButton.isHidden = !inside
    }
    private func scheduleDismissal() {
        timer?.invalidate(); timer = nil
        guard !lifetime.hovered, !lifetime.retainedByDrag, !lifetime.closing else { return }
        lifetime.deadline = Date.timeIntervalSinceReferenceDate + 5
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.lifetime.expired(at: Date.timeIntervalSinceReferenceDate) else { return }
            self.dismissPreview()
        }
    }
    private func movePreview(_ event: NSEvent) {
        guard let window else { return }
        // AppKit consumes drag events in its tracking loop. Observe the event itself,
        // so a drag that returns to its starting point still retains the preview.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self, weak window] drag in
            if drag.window === window { self?.retainAfterDrag() }
            return drag
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        window.performDrag(with: event)
    }
    private func retainAfterDrag() {
        lifetime.dragged(); timer?.invalidate(); timer = nil
    }
    @objc private func saveImage() {
        SaveController.present(image: image)
        if lifetime.retainedByDrag { controls.isHidden = true; closeButton.isHidden = true }
        else { dismissPreview() }
    }
    @objc private func dismissPreview() {
        guard !lifetime.closing else { return }; lifetime.dismiss(); timer?.invalidate(); timer = nil
        NSAnimationContext.runAnimationGroup { context in context.duration = 0.4; imageContainer.animator().alphaValue = 0; window?.animator().hasShadow = false }
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.close() }
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil; Self.retained.removeAll { $0 === self } }
    static func verifyInteractions() throws {
        func require(_ value: Bool, _ message: String) throws { if !value { throw NSError(domain: "PreviewVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
        let selection = NSRect(x: -1200, y: 180, width: 640, height: 360)
        try require(validSourceFrame(selection) == selection, "Flight must retain global selection coordinates on secondary displays")
        try require(validSourceFrame(nil) == nil && validSourceFrame(.zero) == nil && validSourceFrame(NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 1)) == nil, "Invalid flight geometry must use the settled preview")
        var state = PreviewLifetime()
        try require(!state.expired(at: 4.99) && state.expired(at: 5), "Preview must expire at five seconds")
        state.enter(); try require(!state.expired(at: 100) && state.deadline == nil, "Hover must cancel dismissal")
        state.exit(at: 100); try require(!state.expired(at: 104.99) && state.expired(at: 105), "Exit must start a new five-second interval")
        state.dragged(); state.exit(at: 200); try require(!state.expired(at: 1000) && state.deadline == nil, "Moved preview must remain visible")
        state.dismiss(); try require(state.closing && !state.expired(at: 1000), "Dismissal must run once without a new timer")
        let preview = FloatingPreviewController(image: NSImage(size: NSSize(width: 150, height: 100)), frame: nil)
        try require(preview.window?.styleMask.rawValue == 0x8009 && preview.window?.frame.size == NSSize(width: 150, height: 100), "Corner preview must use the recovered window style and outer frame")
        preview.retainAfterDrag(); preview.hoverChanged(false)
        try require(preview.lifetime.retainedByDrag && preview.timer == nil, "A drag event without net displacement must retain the production preview")
        preview.dismissPreview()
        try require(preview.lifetime.closing, "Dismissal must close the preview without restarting its timer")
        try require(preview.window?.contentView?.alphaValue == 1, "Dismissal must retain the animation root while fading its image container")
        preview.close()
    }
}
