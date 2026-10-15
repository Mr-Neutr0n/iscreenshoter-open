import AppKit
import Carbon

let accent = NSColor(calibratedRed: 0.43, green: 0.32, blue: 0.95, alpha: 1)
func writeParityRender(_ view: NSView, name: String, background explicitBackground: NSColor? = nil) throws {
    guard let directory = ProcessInfo.processInfo.environment["ISCREENSHOTER_RENDER_DIR"] else { return }
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "ParityRender", code: 1) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    var rendered = bitmap
    if let background = explicitBackground ?? view.window?.backgroundColor, background.alphaComponent > 0,
       let composite = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
        composite.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composite)
        background.setFill(); NSRect(origin: .zero, size: view.bounds.size).fill()
        bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        NSGraphicsContext.restoreGraphicsState()
        rendered = composite
    }
    guard let png = rendered.representation(using: .png, properties: [:]) else { throw NSError(domain: "ParityRender", code: 2) }
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent(name + ".png"))
}

func alert(_ message: String) { let a = NSAlert(); a.messageText = message; a.runModal() }

final class ActionButton: NSButton {
    var handler: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; handler = action; target = self; self.action = #selector(run)
        bezelStyle = .rounded
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = .imageLeading }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func run() { handler?() }
}

final class HistoryStore {
    static let shared = HistoryStore()
    let directory: URL
    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.hari.screenshoter.open/Image", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    var files: [URL] {
        let cached = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let paths = UserDefaults.standard.stringArray(forKey: "savedImagePaths") ?? []
        let saved = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let scanned = cached.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        var seen = Set<String>()
        return (saved + scanned).filter { seen.insert($0.path).inserted }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a == b ? $0.lastPathComponent > $1.lastPathComponent : a > b
        }
    }
    func recordSaved(url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: "savedImagePaths") ?? []
        if !paths.contains(url.path) { paths.append(url.path) }
        UserDefaults.standard.set(paths, forKey: "savedImagePaths")
        NotificationCenter.default.post(name: Notification.Name("HistoryChanged"), object: nil)
    }
    @discardableResult func add(_ image: NSImage) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 1]) else { return nil }
            let date = DateFormatter(); date.dateFormat = "yyyyMMddHHmmssSSS"
            let url = directory.appendingPathComponent("Screen Shoter Open - " + date.string(from: Date()) + "-" + UUID().uuidString.prefix(5) + ".jpg")
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: Notification.Name("HistoryChanged"), object: nil)
            return url
        } catch { alert("Could not save screenshot history: \(error.localizedDescription)"); return nil }
    }
    func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        let paths = (UserDefaults.standard.stringArray(forKey: "savedImagePaths") ?? []).filter { $0 != url.path }
        UserDefaults.standard.set(paths, forKey: "savedImagePaths")
        NotificationCenter.default.post(name: Notification.Name("HistoryChanged"), object: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    var hotKeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    private var shortcutRecording = false
    var capture: CaptureController?
    var settings: SettingsController?
    var dashboard: DashboardController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        UserDefaults.standard.register(defaults: ["saveDirectory": HistoryStore.shared.directory.path, "format": "jpg", "ocrLanguage": "automatic", "captureModifiers": UInt32(cmdKey | shiftKey), "ocrModifiers": UInt32(cmdKey | shiftKey)])
        installMenu()
        item = NSStatusBar.system.statusItem(withLength: 24)
        item.button?.image = publicAsset("icon_topbar") ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Screen Shoter Open")
        item.button?.image?.size = NSSize(width: 18, height: 18)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Screen Shoter Open"
        item.button?.setAccessibilityLabel("Screen Shoter Open")
        item.button?.target = self; item.button?.action = #selector(toggle)
        dashboard = DashboardController(owner: self)
        popover.contentViewController = dashboard; popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 378)
        installHotKeys()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.shortcutRecording, self.hotKeys.count < 2 else { return }
            self.installHotKeys()
            self.dashboard?.refresh()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("StartRecording"), object: nil, queue: .main) { _ in RecorderController.present() }
        NotificationCenter.default.addObserver(forName: Notification.Name("ScreenshotCompleted"), object: nil, queue: .main) { note in
            if let image = note.object as? NSImage, let url = HistoryStore.shared.add(image) { FloatingPreviewController.open(image: image, url: url, screenFrame: note.userInfo?["screenFrame"] as? NSRect, sourceFrame: note.userInfo?["sourceFrame"] as? NSRect) }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("HistoryChanged"), object: nil, queue: .main) { [weak self] _ in self?.dashboard.refresh() }
        if CommandLine.arguments.contains("--demo-preview") {
            if let url = HistoryStore.shared.add(Self.demoImage()) { FloatingPreviewController.open(image: Self.demoImage(), url: url) }
        } else if CommandLine.arguments.contains("--demo-settings") { showSettings() }
        else if CommandLine.arguments.contains("--capture") { beginCapture(ocr: false) }
        else if CommandLine.arguments.contains("--demo") { EditorController.open(image: Self.demoImage()) }
        else if CommandLine.arguments.contains("--demo-capture"), let screen = NSScreen.main {
            let full = Self.demoImage()
            EditorController.openCapture(image: full, selection: NSRect(x: screen.frame.width * 0.15, y: screen.frame.height * 0.2, width: screen.frame.width * 0.65, height: screen.frame.height * 0.6), screenFrame: screen.frame)
        } else { toggle() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recorder = RecorderController.shared, recorder.hasActiveRecording else { return .terminateNow }
        recorder.stopForTermination { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !popover.isShown && !NSApp.windows.contains(where: { $0.isVisible && $0 != item.button?.window }) { toggle() }
        return true
    }
    func installMenu() {
        let main = NSMenu()
        let root = NSMenuItem(); let app = NSMenu(); root.submenu = app; main.addItem(root)
        for (name, selector, key) in [("Screenshot", #selector(screenshot), "a"), ("Import image…", #selector(importImage), "o"), ("Settings…", #selector(showSettings), ","), ("Quit Screen Shoter Open", #selector(quit), "q")] {
            let m = NSMenuItem(title: name, action: selector, keyEquivalent: key); m.target = self; app.addItem(m)
            if name == "Screenshot" { m.keyEquivalentModifierMask = [.command, .shift] }
        }
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let edits = NSMenu(title: "Edit"); edit.submenu = edits
        for (name, action, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edits.addItem(withTitle: name, action: action, keyEquivalent: key) }
        main.addItem(edit); NSApp.mainMenu = main
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button { dashboard.refresh(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    @objc func screenshot() { beginCapture(ocr: false) }
    func beginCapture(ocr: Bool) {
        popover.performClose(nil)
        guard capture == nil else { return }
        guard EditorController.retained.isEmpty else { EditorController.retained.last?.window?.makeKeyAndOrderFront(nil); return }
        capture = CaptureController { [weak self] result in
            self?.capture = nil
            guard let result else { return }
            if ocr { OCRController.present(image: result.croppedImage) }
            else { EditorController.openCapture(image: result.image, selection: result.selection, screenFrame: result.screenFrame) }
        }
        capture?.start()
    }
    @objc func importImage() {
        popover.performClose(nil); NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.allowsMultipleSelection = true
        if p.runModal() == .OK { for url in p.urls { if let image = NSImage(contentsOf: url) { EditorController.open(image: image) } } }
    }
    func pasteImage() {
        popover.performClose(nil)
        guard let image = NSImage(pasteboard: .general) else { alert("The clipboard does not contain an image."); return }
        EditorController.open(image: image)
    }
    @objc func showSettings() {
        popover.performClose(nil)
        if settings == nil { settings = SettingsController(owner: self) }
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func setShortcutRecording(_ recording: Bool) {
        shortcutRecording = recording
        if recording { hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll() }
        else { installHotKeys(); dashboard?.refresh() }
    }
    func installHotKeys() {
        guard !shortcutRecording else { return }
        dashboard?.shortcutError = nil
        hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll()
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
                guard let event, let context else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { owner.beginCapture(ocr: id.id == 2) }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        for (id, defaultKey, key) in [(UInt32(1), UInt32(kVK_ANSI_A), "captureKey"), (UInt32(2), UInt32(kVK_ANSI_T), "ocrKey")] {
            let code = UserDefaults.standard.object(forKey: key) as? UInt32 ?? defaultKey
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(code, UInt32(UserDefaults.standard.integer(forKey: key == "captureKey" ? "captureModifiers" : "ocrModifiers")), EventHotKeyID(signature: 0x49534C43, id: id), GetApplicationEventTarget(), 0, &ref)
            NSLog("Shortcut %@ registration status: %d", key, result)
            if result == noErr, let ref { hotKeys.append(ref) }
            else { dashboard?.shortcutError = "Shortcut in use. Choose another key in Settings." }
        }
    }
    static func demoImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 1000, height: 620))
        image.lockFocus()
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1000, height: 620).fill()
        accent.setFill(); NSBezierPath(roundedRect: NSRect(x: 70, y: 80, width: 860, height: 460), xRadius: 22, yRadius: 22).fill()
        ("Screen Shoter Open" as NSString).draw(at: NSPoint(x: 120, y: 390), withAttributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.white])
        ("Capture. Annotate. Copy.\nOCR runs on your Mac.\nAll rebuilt tools are free." as NSString).draw(at: NSPoint(x: 120, y: 210), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.white])
        image.unlockFocus(); return image
    }
}


func verifyPublicAssets() throws {
    for name in ["icon_topbar", "icon_close_normal", "mosaic", "add_Image", "icon_tools_ocr", "save_image", "save_arrow", "icon_shot", "icon_shot_A", "btn_record_normal", "icon_delete", "icon_close_black", "bar_drag", "q_1", "q_2", "q_3", "q_4", "q_5"] {
        guard publicAsset(name) != nil else { throw NSError(domain: "AssetVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing generated asset " + name]) }
    }
    guard publicAsset("icon_topbar")?.size == NSSize(width: 18, height: 18) else { throw NSError(domain: "AssetVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: "Menu icon must be 18 points"]) }
}
func verifyShortcutRegistration() throws {
    let keys = ["captureKey", "ocrKey", "captureModifiers", "ocrModifiers"]
    let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
    let owner = AppDelegate()
    defer {
        owner.hotKeys.forEach { UnregisterEventHotKey($0) }
        if let handler = owner.eventHandler { RemoveEventHandler(handler) }
        for (key, value) in zip(keys, previous) { if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
    }
    let flags = UInt32(controlKey | optionKey | shiftKey)
    UserDefaults.standard.set(UInt32(kVK_F18), forKey: "captureKey")
    UserDefaults.standard.set(UInt32(kVK_F19), forKey: "ocrKey")
    UserDefaults.standard.set(flags, forKey: "captureModifiers")
    UserDefaults.standard.set(flags, forKey: "ocrModifiers")
    owner.installHotKeys()
    guard owner.hotKeys.count == 2 else { throw NSError(domain: "ShortcutVerification", code: 1) }
    owner.setShortcutRecording(true)
    owner.installHotKeys()
    guard owner.hotKeys.isEmpty else { throw NSError(domain: "ShortcutVerification", code: 2) }
    owner.setShortcutRecording(false)
    guard owner.hotKeys.count == 2 else { throw NSError(domain: "ShortcutVerification", code: 3) }
}

let application = NSApplication.shared
if CommandLine.arguments.contains("--render-demo") {
    application.setActivationPolicy(.prohibited)
    application.appearance = NSAppearance(named: .aqua)
    do {
        try EditorController.renderPublicDemo()
        exit(0)
    } catch {
        fputs("Demo rendering failed: \(error)\n", stderr)
        exit(1)
    }
}
if CommandLine.arguments.contains("--verify") {
    application.setActivationPolicy(.prohibited)
    application.appearance = NSAppearance(named: .aqua)
    UserDefaults.standard.register(defaults: ["captureModifiers": UInt32(cmdKey | shiftKey), "ocrModifiers": UInt32(cmdKey | shiftKey)])
    Task { @MainActor in
        do {
            try EditorController.verifyRendering()
            print("PASS: editor rendering and toolbar geometry")
            try CaptureMagnifier.verifyRendering()
            print("PASS: recovered magnifier layout, pointer placement and update throttling")
            let home = DashboardController(owner: AppDelegate())
            try home.verifyLayout()
            try writeParityRender(home.view, name: "home")
            try SaveController.verifyPanelLayout()
            try SettingsController.verifyCurrentLayout()
            try PinController.verifyLayout()
            print("PASS: Home, Save, current Settings and pin layout")
            try FloatingPreviewController.verifyInteractions()
            print("PASS: preview dismissal, hover, drag persistence and screen placement")
            try verifyPublicAssets()
            print("PASS: catalog assets and menu icon logical size")
            try verifyShortcutRegistration()
            print("PASS: shortcut registration, suspension and resume")
            try SaveController.verifyExports()
            print("PASS: PNG, JPG, PDF and collision handling")
            try OCRController.verifyLayout()
            try await OCRController.verifyRecognition()
            print("PASS: local OCR and table formatting")
            try await RecorderController.verifyEncoding()
            print("PASS: H.264 encoding, duration and decoded frames")
            exit(0)
        } catch {
            fputs("Verification failed: \(error)\n", stderr)
            exit(1)
        }
    }
    application.run()
}

let delegate = AppDelegate()
application.delegate = delegate
application.run()
