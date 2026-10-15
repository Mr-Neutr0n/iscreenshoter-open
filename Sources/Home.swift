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
    private let historyStore: HistoryStore
    var shortcutError: String?
    private let history = NSView()
    private let scroll = NSScrollView()
    private var selected: Set<URL> = []
    private var deleteButton: NSButton?
    private var trashButton: NSButton?
    private var visibleFiles: [URL] = []
    private var thumbnails: [URL: HistoryThumbnail] = [:]
    private var pending: [URL: Operation] = [:]
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let thumbnailQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private var scrollObserver: NSObjectProtocol?
    private var scrollUpdate: DispatchWorkItem?
    private var captureLabel: NSTextField?
    private var ocrLabel: NSTextField?
    init(owner: AppDelegate, historyStore: HistoryStore = .shared) { self.owner = owner; self.historyStore = historyStore; super.init(nibName: nil, bundle: nil) }
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
        parityButton("Open folder", frame: NSRect(x: 21, y: 31, width: 18, height: 16), image: "icon_openfolder", action: { [weak self] in if let folder = self?.historyStore.directory { try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); NSWorkspace.shared.open(folder) } }, in: view)
        deleteButton = parityButton("Delete selected", frame: NSRect(x: 63, y: 30, width: 15, height: 17), image: "icon_del", action: { [weak self] in self?.removeSelected() }, in: view)
        deleteButton?.toolTip = "Remove selected from history. Exported files are kept."
        deleteButton?.setAccessibilityLabel("Remove selected from history")
        trashButton = parityButton("Move to Trash…", frame:NSRect(x:96,y:25,width:128,height:27), action:{ [weak self] in self?.trashSelected() }, in:view)
        trashButton?.font = .systemFont(ofSize:12)
        thumbnailCache.countLimit = 48
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification, object:scroll.contentView, queue:.main) { [weak self] _ in
            self?.scrollUpdate?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.loadVisibleThumbnails() }
            self?.scrollUpdate = work; DispatchQueue.main.asyncAfter(deadline:.now() + 0.05, execute:work)
        }
        refresh()
    }
    deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }; thumbnailQueue.cancelAllOperations(); scrollUpdate?.cancel() }
    func refresh() {
        guard isViewLoaded else { return }
        captureLabel?.stringValue = homeShortcutTitle("capture", fallback: 0); ocrLabel?.stringValue = homeShortcutTitle("ocr", fallback: 17)
        captureLabel?.toolTip = shortcutError; ocrLabel?.toolTip = shortcutError
        let priorHeight = history.bounds.height
        let priorOrigin = scroll.contentView.bounds.origin.y
        let atTop = priorOrigin >= max(0, priorHeight - scroll.contentView.bounds.height) - 0.5
        let files = historyStore.files; selected.formIntersection(Set(files))
        if files != visibleFiles {
            for url in visibleFiles where !files.contains(url) { thumbnailCache.removeObject(forKey:url as NSURL) }
            visibleFiles = files
            for (url, thumb) in thumbnails where !files.contains(url) { thumb.removeFromSuperview(); thumbnails.removeValue(forKey:url) }
            for (url, operation) in pending where !files.contains(url) { operation.cancel(); pending.removeValue(forKey:url) }
        }
        let height = max(183, 42 + CGFloat((files.count + 2) / 3) * 78 - 18)
        history.frame = NSRect(x:0,y:0,width:320,height:height)
        let top = max(0,height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:NSPoint(x:0,y:atTop ? top : min(top,max(0,priorOrigin + height - priorHeight))))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.isHidden = files.isEmpty
        loadVisibleThumbnails(); updateSelection()
    }
    private func updateSelection() {
        for (url, thumb) in thumbnails { thumb.selected = selected.contains(url); thumb.needsDisplay = true }
        deleteButton?.isHidden = selected.isEmpty; trashButton?.isHidden = selected.isEmpty
    }
    private func loadVisibleThumbnails() {
        let visible = scroll.contentView.bounds.insetBy(dx:0,dy:-78)
        let height = history.frame.height
        let targets = visibleFiles.enumerated().compactMap { index, url -> (URL,NSRect)? in
            let frame = NSRect(x:20 + CGFloat(index % 3) * 96,y:height - 81 - CGFloat(index / 3) * 78,width:80,height:60)
            return frame.intersects(visible) ? (url,frame) : nil
        }
        let targetURLs = Set(targets.map { $0.0 })
        for (url, thumb) in thumbnails where !targetURLs.contains(url) { thumb.removeFromSuperview(); thumbnails.removeValue(forKey:url) }
        for (url, operation) in pending where !targetURLs.contains(url) { operation.cancel(); pending.removeValue(forKey:url) }
        for (url, frame) in targets {
            let thumb = thumbnails[url] ?? HistoryThumbnail(frame:frame)
            thumb.frame = frame; thumb.selected = selected.contains(url)
            if thumbnails[url] == nil {
                thumbnails[url] = thumb; history.addSubview(thumb)
                thumb.clicked = { [weak self] double in
                    guard let self else { return }
                    if double { self.owner?.popover.performClose(nil); HistoryPreviewController.open(url:url) }
                    else { if self.selected.contains(url) { self.selected.remove(url) } else { self.selected.insert(url) }; self.updateSelection() }
                }
            }
            if let cached = thumbnailCache.object(forKey:url as NSURL) { thumb.image = cached; thumb.needsDisplay = true; continue }
            guard pending[url] == nil else { continue }
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak operation] in
                guard operation?.isCancelled == false else { return }
                let image = HistoryStore.thumbnail(at:url)
                DispatchQueue.main.async { [weak self, weak operation] in
                    guard let self, operation?.isCancelled == false else { return }
                    self.pending.removeValue(forKey:url)
                    if let image { self.thumbnailCache.setObject(image,forKey:url as NSURL); self.thumbnails[url]?.image = image; self.thumbnails[url]?.needsDisplay = true }
                }
            }
            pending[url] = operation; thumbnailQueue.addOperation(operation)
        }
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
    static func verifyHistoryScaling() throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("home-history-" + UUID().uuidString)
        let suite = "home-history-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:fixture); defaults.removePersistentDomain(forName:suite) }
        let store = HistoryStore(directory:fixture.appendingPathComponent("cache"),defaults:defaults)
        store.setEnabled(true)
        let image = NSImage(size:NSSize(width:12,height:8)); image.lockFocus(); NSColor.green.setFill(); NSRect(x:0,y:0,width:12,height:8).fill(); image.unlockFocus()
        let data = NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!).representation(using:.jpeg,properties:[:])!
        for index in 0..<205 {
            let file = fixture.appendingPathComponent("fixture-\(index).jpg")
            try data.write(to:file); store.recordSaved(url:file)
        }
        let owner = AppDelegate(); let controller = DashboardController(owner:owner,historyStore:store)
        controller.loadViewIfNeeded()
        let originalViews = controller.thumbnails.mapValues(ObjectIdentifier.init)
        if let first = controller.visibleFiles.first { controller.selected.insert(first) }
        controller.updateSelection()
        guard controller.visibleFiles.count == 200, controller.thumbnails.count <= 18,
              originalViews == controller.thumbnails.mapValues(ObjectIdentifier.init) else {
            throw NSError(domain:"HomeScaling",code:1,userInfo:[NSLocalizedDescriptionKey:"History must bound thumbnail views and reuse them on selection"])
        }
        controller.scroll.contentView.scroll(to:NSPoint(x:0,y:0)); controller.loadVisibleThumbnails()
        guard controller.thumbnails.count <= 18, controller.pending.count <= 18 else { throw NSError(domain:"HomeScaling",code:2) }
        controller.thumbnailQueue.cancelAllOperations(); controller.scrollUpdate?.cancel()
        print("History dashboard verified: 205 fixtures capped at 200, visible-only views and requests, selection reuses views")
    }
    private func removeSelected() {
        historyStore.removeFromHistory(Array(selected)); selected.removeAll(); refresh()
    }
    private func trashSelected() {
        let urls = selected
        let prompt = NSAlert(); prompt.messageText = "Move \(urls.count) selected file(s) to Trash?"
        prompt.informativeText = "This moves the actual files to Trash, including exports in your chosen folders. To keep exported files, use Remove from history instead."
        prompt.addButton(withTitle:"Move to Trash"); prompt.addButton(withTitle:"Cancel")
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        do { for url in urls { try historyStore.trash(url) }; selected.removeAll(); refresh() } catch { alert(error.localizedDescription) }
    }
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
