import AppKit

func parityColor(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
@discardableResult func parityLabel(_ text: String, frame: NSRect, size: CGFloat = 12, color: NSColor = .white, alignment: NSTextAlignment = .left, in view: NSView) -> NSTextField {
    let label = NSTextField(labelWithString: text); label.frame = frame; label.font = .systemFont(ofSize: size); label.textColor = color; label.alignment = alignment; view.addSubview(label); return label
}
@discardableResult func parityButton(_ title: String, frame: NSRect, image: String? = nil, fill: NSColor? = nil, color: NSColor = .white, action: @escaping () -> Void, in view: NSView) -> ActionButton {
    let button = ActionButton(title, action: action); button.frame = frame; button.isBordered = false; button.font = .systemFont(ofSize: 14); button.contentTintColor = color
    if let image { button.image = publicAsset(image); button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyUpOrDown }
    if let fill { button.wantsLayer = true; button.layer?.backgroundColor = fill.cgColor; button.layer?.cornerRadius = 4 }
    view.addSubview(button); return button
}

final class DashboardController: NSViewController {
    weak var owner: AppDelegate?
    var shortcutError: String?
    private let history = NSView()
    private let scroll = NSScrollView()
    private var selected: Set<URL> = []
    private var deleteButton: NSButton?
    private var captureLabel: NSTextField?
    private var ocrLabel: NSTextField?
    init(owner: AppDelegate) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 378)); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(deviceRed: 0.2, green: 0.2, blue: 0.2, alpha: 1).cgColor; view.layer?.cornerRadius = 8; view.layer?.masksToBounds = true
        let effect = NSVisualEffectView(frame: view.bounds); effect.material = NSVisualEffectView.Material(rawValue: 2)!; effect.blendingMode = .behindWindow; effect.state = .active; effect.isHidden = true; view.addSubview(effect)
        parityButton("Settings", frame: NSRect(x: 290, y: 349, width: 17, height: 17), image: "icon_settings", action: { [weak self] in self?.owner?.showSettings() }, in: view)
        for (index, asset, title) in [(0,"icon_shot","Screenshot"),(1,"icon_shot_A","Text ( OCR )"),(2,"btn_record_normal","Record screen")] {
            let button = parityButton(title, frame: NSRect(x: 26 + index * 105, y: 292, width: 58, height: 58), image: asset, action: { [weak self] in
                guard let self else { return }; if index == 0 { self.owner?.screenshot() }; if index == 1 { self.owner?.beginCapture(ocr: true) }; if index == 2 { self.owner?.popover.performClose(nil); RecorderController.present() }
            }, in: view); button.toolTip = title

        }
        // Original Home archive: title26/53/164 is sRGB white, alpha0.8031846513.
        let titleColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8031846513)
        parityLabel("Screenshot", frame: NSRect(x: 21, y: 269, width: 69, height: 15), color: titleColor, in: view)
        parityLabel("Text ( OCR )", frame: NSRect(x: 123, y: 267, width: 73, height: 15), color: titleColor, in: view)
        let recordTitle = parityLabel("Record screen", frame: NSRect(x: 226, y: 254, width: 79, height: 30), color: titleColor, alignment: .center, in: view)
        recordTitle.maximumNumberOfLines = 2; recordTitle.cell?.wraps = true
        captureLabel = parityLabel("", frame: NSRect(x: 21, y: 250, width: 68, height: 16), size: 13, color: .white.withAlphaComponent(0.5), in: view)
        ocrLabel = parityLabel("", frame: NSRect(x: 125, y: 248, width: 68, height: 16), size: 13, color: .white.withAlphaComponent(0.5), in: view)
        scroll.frame = NSRect(x: 0, y: 59, width: 320, height: 183); scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false; scroll.documentView = history; view.addSubview(scroll)
        parityButton("Open folder", frame: NSRect(x: 21, y: 31, width: 18, height: 16), image: "icon_openfolder", action: { NSWorkspace.shared.open(HistoryStore.shared.directory) }, in: view)
        deleteButton = parityButton("Delete selected", frame: NSRect(x: 63, y: 30, width: 15, height: 17), image: "icon_del", action: { [weak self] in self?.deleteSelected() }, in: view)
        refresh()
    }
    func refresh() {
        guard isViewLoaded else { return }
        captureLabel?.stringValue = homeShortcutTitle("capture", fallback: 0); ocrLabel?.stringValue = homeShortcutTitle("ocr", fallback: 17)
        captureLabel?.toolTip = shortcutError; ocrLabel?.toolTip = shortcutError
        let priorHeight = history.bounds.height
        let priorOrigin = scroll.contentView.bounds.origin.y
        let atTop = priorOrigin >= max(0, priorHeight - scroll.contentView.bounds.height) - 0.5
        let files = HistoryStore.shared.files; selected.formIntersection(Set(files)); history.subviews.forEach { $0.removeFromSuperview() }
        let height = max(183, 42 + CGFloat((files.count + 2) / 3) * 78 - 18)
        history.frame = NSRect(x: 0, y: 0, width: 320, height: height)
        for (index, url) in files.enumerated() {
            let thumb = HistoryThumbnail(frame: NSRect(x: 20 + CGFloat(index % 3) * 96, y: height - 21 - 60 - CGFloat(index / 3) * 78, width: 80, height: 60)); thumb.image = NSImage(contentsOf: url); thumb.selected = selected.contains(url)
            thumb.clicked = { [weak self] double in
                guard let self else { return }
                if double { self.owner?.popover.performClose(nil); HistoryPreviewController.open(url: url) }
                else { if self.selected.contains(url) { self.selected.remove(url) } else { self.selected.insert(url) }; self.refresh() }
            }; history.addSubview(thumb)
        }
        let top = max(0, height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: atTop ? top : min(top, max(0, priorOrigin + height - priorHeight))))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.isHidden = files.isEmpty; deleteButton?.isHidden = selected.isEmpty
    }
    func verifyLayout() throws {
        loadViewIfNeeded()
        let titles = view.subviews.compactMap { $0 as? NSTextField }
        guard view.bounds.size == NSSize(width: 320, height: 378), view.layer?.cornerRadius == 8,
              titles.contains(where: { $0.stringValue == "Screenshot" && $0.frame == NSRect(x: 21, y: 269, width: 69, height: 15) }),
              titles.contains(where: { $0.stringValue == "Text ( OCR )" && $0.frame == NSRect(x: 123, y: 267, width: 73, height: 15) }),
              titles.contains(where: { $0.stringValue == "Record screen" && $0.frame == NSRect(x: 226, y: 254, width: 79, height: 30) }),
              captureLabel?.frame.size == NSSize(width: 68, height: 16),
              captureLabel?.textColor?.alphaComponent == 0.5 else {
            throw NSError(domain: "HomeParity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recovered Home layout failed"])
        }
    }
    private func deleteSelected() { do { for url in selected { try HistoryStore.shared.trash(url) }; selected.removeAll(); refresh() } catch { alert(error.localizedDescription) } }
}
private final class HistoryThumbnail: NSView {
    var image: NSImage?
    var selected = false
    var clicked: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) { clicked?(event.clickCount > 1) }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: (bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height))
        if selected { parityColor(0x0083F4).setStroke(); let p = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); p.lineWidth = 2; p.stroke() }
    }
}

// The archive uses "⌘ + ⇧ + A" rather than compact menu glyph notation.
private func homeShortcutTitle(_ preference: String, fallback: UInt32) -> String {
    let compact = shortcutTitle(preference, fallback: fallback)
    let modifiers: [Character] = ["⌘", "⇧", "⌥", "⌃"]
    let parts = modifiers.filter { compact.contains($0) }.map(String.init)
    let key = String(compact.filter { !modifiers.contains($0) })
    return (parts + [key]).joined(separator: " + ")
}
