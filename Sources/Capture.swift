import AppKit
import ScreenCaptureKit

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct CaptureResult {
    let image: NSImage
    let croppedImage: NSImage
    let selection: NSRect
    let screenFrame: NSRect
}

final class CaptureController {
    var panels: [NSPanel] = []
    var views: [SelectionView] = []
    var finished = false
    let completion: (CaptureResult?) -> Void
    init(completion: @escaping (CaptureResult?) -> Void) { self.completion = completion }
    func start() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            guard CGPreflightScreenCaptureAccess() else {
                alert("Enable Screen Shoter Open in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen this app.")
                finish(nil); return
            }
        }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var captures: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                          let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                    let config = SCStreamConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false
                    let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier })
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    captures.append((screen, image))
                }
                guard !captures.isEmpty else { throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No screen is available."]) }
                for (screen, image) in captures {
                    let p = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    p.setFrame(screen.frame, display: false); p.level = .screenSaver; p.isOpaque = false; p.backgroundColor = .clear
                    p.collectionBehavior = NSWindow.CollectionBehavior(rawValue: 4); p.isReleasedWhenClosed = false
                    let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, screen: screen)
                    v.onComplete = { [weak self] in self?.finish($0) }; p.contentView = v
                    panels.append(p); views.append(v); p.makeKeyAndOrderFront(nil); p.makeFirstResponder(v)
                }
                NSApp.activate(ignoringOtherApps: true); NSCursor.crosshair.set()
            } catch { alert("Screen capture failed: \(error.localizedDescription)"); finish(nil) }
        }
    }
    func finish(_ image: CaptureResult?) {
        guard !finished else { return }; finished = true
        panels.forEach { $0.close() }; panels.removeAll(); views.removeAll(); NSCursor.arrow.set()
        completion(image)
    }
}

final class SelectionView: NSView {
    let image: CGImage
    private let bitmap: NSBitmapImageRep
    let screen: NSScreen
    var onComplete: ((CaptureResult?) -> Void)?
    var start: NSPoint?
    var selection: NSRect = .zero
    var pointer = NSPoint.zero
    var tracking: NSTrackingArea?
    let windows: [CGRect]
    private let magnifier: CaptureMagnifier
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: NSRect, image: CGImage, screen: NSScreen) {
        self.image = image; self.screen = screen; bitmap = NSBitmapImageRep(cgImage: image)
        magnifier = CaptureMagnifier(image: image, screenSize: frame.size)
        let globalTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        windows = info.compactMap { row in
            guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  (row[kCGWindowLayer as String] as? Int ?? 1) == 0,
                  (row[kCGWindowOwnerPID as String] as? Int) != Int(ProcessInfo.processInfo.processIdentifier), r.width > 20, r.height > 20 else { return nil }
            return CGRect(x: r.minX - screen.frame.minX, y: r.minY - (globalTop - screen.frame.maxY), width: r.width, height: r.height).intersection(NSRect(origin: .zero, size: frame.size))
        }.filter { !$0.isEmpty }
        super.init(frame: frame)
        addSubview(magnifier)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }; super.updateTrackingAreas()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if start == nil { selection = windows.first(where: { $0.contains(pointer) }) ?? bounds }
        updateMagnifier(); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil); pointer = start!; selection = .zero; updateMagnifier(); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        guard let s = start else { return }
        selection = NSRect(x: min(s.x, pointer.x), y: min(s.y, pointer.y), width: abs(s.x - pointer.x), height: abs(s.y - pointer.y)).intersection(bounds)
        updateMagnifier(); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if selection.width < 5 || selection.height < 5 { selection = windows.first(where: { $0.contains(pointer) }) ?? bounds }
        completeSelection()
    }
    override func rightMouseDown(with event: NSEvent) { onComplete?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete?(nil) }
        else if event.keyCode == 36 { if selection.isEmpty { selection = bounds }; completeSelection() }
        else if event.charactersIgnoringModifiers?.lowercased() == "c", !event.modifierFlags.contains(.command) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pixelHex(), forType: .string) }
    }
    func completeSelection() {
        let sx = CGFloat(image.width) / bounds.width, sy = CGFloat(image.height) / bounds.height
        let rect = CGRect(x: selection.minX * sx, y: selection.minY * sy, width: selection.width * sx, height: selection.height * sy).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width > 0, rect.height > 0, let cropped = image.cropping(to: rect) else { onComplete?(nil); return }
        onComplete?(CaptureResult(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), croppedImage: NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)), selection: NSRect(x: selection.minX, y: bounds.height - selection.maxY, width: selection.width, height: selection.height), screenFrame: screen.frame))
    }
    func pixelHex() -> String {
        let x = max(0, min(image.width - 1, Int(pointer.x * CGFloat(image.width) / bounds.width)))
        let y = max(0, min(image.height - 1, Int(pointer.y * CGFloat(image.height) / bounds.height)))
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpaceName(.calibratedRGB) else { return "FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))

    }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.5).setFill()
        let shade = NSBezierPath(rect: bounds); if !selection.isEmpty { shade.append(NSBezierPath(rect: selection)); shade.windingRule = .evenOdd }; shade.fill()
        if !selection.isEmpty {
            SelectionChrome.draw(rect:selection,handles:false)
        }
    }
    private func updateMagnifier() {
        magnifier.update(pointer: pointer, selection: selection, screenSize: bounds.size, hex: pixelHex())
    }

}

// Geometry recovered from VRCutScreenView and its selection update routine.
enum SelectionChrome {
    static let color = NSColor(srgbRed:21/255,green:124/255,blue:252/255,alpha:1)
    static func handleRects(_ rect:NSRect) -> [NSRect] {
        let points = [NSPoint(x:rect.minX,y:rect.minY),NSPoint(x:rect.midX,y:rect.minY),NSPoint(x:rect.maxX,y:rect.minY),NSPoint(x:rect.maxX,y:rect.midY),NSPoint(x:rect.maxX,y:rect.maxY),NSPoint(x:rect.midX,y:rect.maxY),NSPoint(x:rect.minX,y:rect.maxY),NSPoint(x:rect.minX,y:rect.midY)]
        return points.enumerated().map { index,point in let size = index % 2 == 0 ? NSSize(width:10,height:10) : index == 1 || index == 5 ? NSSize(width:18,height:9) : NSSize(width:9,height:18); return NSRect(x:point.x-size.width/2,y:point.y-size.height/2,width:size.width,height:size.height) }
    }
    static func draw(rect:NSRect,handles:Bool) {
        color.setStroke(); let border = NSBezierPath(rect:rect); border.lineWidth = 1; border.setLineDash([4,3],count:2,phase:0); border.stroke()
        if handles { for rect in handleRects(rect) { let path = NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5); NSColor.white.setFill(); color.setStroke(); path.fill(); path.lineWidth = 1; path.stroke() } }
    }
}
