import AppKit
import Darwin

private final class SavePanel: NSPanel { override var canBecomeKey: Bool { true } }
private final class SaveTitleField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SaveController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static var retained: [SaveController] = []
    static func present(image: NSImage, parentWindow: NSWindow? = nil, completion: ((URL) -> Void)? = nil) {
        let controller = SaveController(image: image, completion: completion)
        controller.window?.level = NSWindow.Level(rawValue: max(NSWindow.Level.normal.rawValue, NSApp.windows.filter { $0.isVisible }.map { $0.level.rawValue }.max() ?? 0) + 1)
        retained.append(controller)
        if let parentWindow, let window = controller.window { parentWindow.beginSheet(window) }
        else { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func quickSave(image: NSImage) throws -> URL {
        let directory = selectedDirectory()
        let url = try write(image: image, directory: directory, name: defaultName(), format: .jpg, resolveCollision: true)
        HistoryStore.shared.recordSaved(url: url)
        return url
    }

    private enum Format: String, CaseIterable {
        case jpg, png, pdf
        var label: String { rawValue.uppercased() }
    }
    private let image: NSImage
    private let completion: ((URL) -> Void)?
    private let nameField = NSTextField()
    private let extensionLabel = NSTextField(labelWithString: ".jpg")
    private let location = NSTextField(labelWithString: "")
    private let reveal = NSButton(checkboxWithTitle: "Open Folder", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private let save = NSButton(title: "Save", target: nil, action: nil)
    private var format: Format
    private var directory: URL
    private var radios: [NSButton] = []

    private init(image: NSImage, completion: ((URL) -> Void)?) {
        self.image = image
        self.completion = completion
        self.format = Format(rawValue: UserDefaults.standard.string(forKey: "format") ?? "jpg") ?? .jpg
        self.directory = Self.selectedDirectory()
        let window = SavePanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 318), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Save"; window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true; window.center()
        super.init(window: window); window.delegate = self
        let view = NSView(frame: window.contentView!.bounds); view.wantsLayer = true; view.layer?.backgroundColor = parityColor(0x2C2C2C).cgColor; window.contentView = view
        let center = NSView(frame: NSRect(x: 0, y: 79, width: 480, height: 209)); center.wantsLayer = true; center.layer?.backgroundColor = parityColor(0x212121).cgColor; view.addSubview(center)
        parityLabel("Save", frame: NSRect(x: 222, y: 295, width: 36, height: 17), size: 14, color: NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 0.8470588235), in: view)
        // These early archive colors have no custom profile: NSColorSpace1 is calibrated RGB.
        let leftColor = NSColor(calibratedRed: 0.8, green: 0.8, blue: 0.8, alpha: 0.8)
        for (title,x,y,width) in [("Save Location:",46,230,127),("Format:",46,193,127),("File Name:",69,157,104),("View in folder:",48,119,125)] {
            parityLabel(title, frame: NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: 15), color: leftColor, alignment: .right, in: view)
        }
        for y in [226,153] { let bg = NSView(frame: NSRect(x: 188, y: y, width: 245, height: 22)); bg.wantsLayer = true; bg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor; bg.layer?.cornerRadius = 4; view.addSubview(bg) }
        location.frame = NSRect(x: 194, y: 230, width: 210, height: 15); location.lineBreakMode = .byTruncatingMiddle; location.font = .systemFont(ofSize: 12); location.textColor = NSColor(calibratedRed: 0.8, green: 0.8, blue: 0.8, alpha: 1); view.addSubview(location)
        parityButton("Choose folder", frame: NSRect(x: 412, y: 230, width: 16, height: 14), image: "icon_openfolder", action: { [weak self] in self?.chooseFolder() }, in: view)
        for (index,value) in Format.allCases.enumerated() {
            let x = CGFloat([188, 270, 354][index])
            let button = NSButton(title: "", target: self, action: #selector(changeFormat(_:))); button.tag = index; button.frame = NSRect(x: x, y: 193, width: 16, height: 16); button.isBordered = false; button.wantsLayer = true; button.layer?.borderWidth = 1; button.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor; button.layer?.cornerRadius = 2; button.state = value == format ? .on : .off; button.toolTip = value.label
            view.addSubview(button); radios.append(button); parityLabel(value.label, frame: NSRect(x: x + 22, y: 194, width: CGFloat([28,30,28][index]), height: 15), color: NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 0.8), in: view)
        }
        nameField.frame = NSRect(x: 192, y: 157, width: 237, height: 15); nameField.stringValue = Self.defaultName(); nameField.delegate = self; nameField.font = .systemFont(ofSize: 12); nameField.isBordered = false; nameField.drawsBackground = false; nameField.textColor = .white; nameField.focusRingType = .none; view.addSubview(nameField)
        reveal.frame = NSRect(x: 186, y: 119, width: 101, height: 18); reveal.font = .systemFont(ofSize: 13); reveal.state = UserDefaults.standard.bool(forKey: "revealSaved") ? .on : .off; view.addSubview(reveal)
        errorLabel.frame = NSRect(x: 171, y: 96, width: 4, height: 13); errorLabel.font = .systemFont(ofSize: 10); errorLabel.textColor = NSColor(srgbRed: 1, green: 0.3529411765, blue: 0.3529411765, alpha: 1); errorLabel.lineBreakMode = .byTruncatingMiddle; view.addSubview(errorLabel)
        let cancel = parityButton("Cancel", frame: NSRect(x: 16, y: 34, width: 43, height: 15), color: NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 0.8), action: { [weak self] in self?.cancelSave() }, in: view); cancel.font = .systemFont(ofSize: 12); cancel.keyEquivalent = "\u{1b}"
        save.title = ""; save.setAccessibilityLabel("SAVE"); save.isBordered = false; save.keyEquivalent = "\r"; save.font = .systemFont(ofSize: 14); save.contentTintColor = .black; save.wantsLayer = true; save.layer?.backgroundColor = parityColor(0xDEFD35).cgColor; save.layer?.cornerRadius = 4; save.target = self; save.action = #selector(saveImage); save.frame = NSRect(x: 191, y: 25, width: 98, height: 32); view.addSubview(save)
        let saveTitle = SaveTitleField(labelWithString: "SAVE"); saveTitle.frame = NSRect(x: 221, y: 33, width: 39, height: 17); saveTitle.font = .systemFont(ofSize: 14); saveTitle.textColor = .black; view.addSubview(saveTitle)
        updateFormats()
        updateLocation()
        validate()
        window.initialFirstResponder = nameField
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func label(_ text: String, frame: NSRect, in view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: 13, weight: .medium)
        view.addSubview(label)
    }
    private static func defaultName() -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyyMMddHHmmssSSS"
        return "Screen Shoter Open - " + date.string(from: Date())
    }
    private static func selectedDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "saveDirectory"), !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        let directory = HistoryStore.shared.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func updateLocation() {
        location.stringValue = directory.path
        location.toolTip = directory.path
    }
    @objc private func changeFormat(_ sender: NSButton) {
        format = Format.allCases[sender.tag]
        for button in radios { button.state = button === sender ? .on : .off }
        updateFormats()
        extensionLabel.stringValue = "." + format.rawValue
        UserDefaults.standard.set(format.rawValue, forKey: "format")
        validate()
    }
    private func updateFormats() {
        for button in radios {
            button.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            if button.state == .on { let square = CALayer(); square.frame = NSRect(x: 3, y: 3, width: 10, height: 10); square.backgroundColor = parityColor(0x0083F4).cgColor; square.cornerRadius = 5; button.layer?.addSublayer(square) }
        }
    }
    private func setError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.invalidateIntrinsicContentSize()
        errorLabel.sizeToFit()
        errorLabel.setFrameSize(NSSize(width: min(276, max(4, errorLabel.frame.width)), height: 13))
    }
    func controlTextDidChange(_ obj: Notification) { validate() }
    private func validate() {
        do {
            let name = try Self.checkedName(nameField.stringValue)
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).appendingPathExtension(format.rawValue).path) {
                throw Self.failure("Filename already exists!")
            }
            setError("")
            save.isEnabled = true
        } catch {
            setError(error.localizedDescription)
            save.isEnabled = false
        }
    }
    @objc private func chooseFolder() { chooseDirectory(afterSelection: nil) }
    private func chooseDirectory(afterSelection: (() -> Void)?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.directory = url
            UserDefaults.standard.set(url.path, forKey: "saveDirectory")
            self.updateLocation()
            self.validate()
            afterSelection?()
        }
    }
    @objc private func openDirectory() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            chooseDirectory(afterSelection: { [weak self] in if let self { NSWorkspace.shared.open(self.directory) } })
            return
        }
        NSWorkspace.shared.open(directory)
    }
    @objc private func cancelSave() { closeSave() }
    private func closeSave() { if let window, let parent = window.sheetParent { parent.endSheet(window) }; window?.close() }
    @objc private func saveImage() {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            chooseDirectory(afterSelection: { [weak self] in self?.saveImage() })
            return
        }
        do {
            let url = try Self.write(image: image, directory: directory, name: nameField.stringValue, format: format, resolveCollision: false)
            UserDefaults.standard.set(format.rawValue, forKey: "format")
            UserDefaults.standard.set(directory.path, forKey: "saveDirectory")
            UserDefaults.standard.set(reveal.state == .on, forKey: "revealSaved")
            HistoryStore.shared.recordSaved(url: url)
            if reveal.state == .on { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            completion?(url)
            closeSave()
        } catch { setError(error.localizedDescription); validateAfterFailure(error) }
    }
    private func validateAfterFailure(_ error: Error) {
        validate()
        setError(error.localizedDescription)
    }
    func windowWillClose(_ notification: Notification) { Self.retained.removeAll { $0 === self } }

    private static func checkedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw failure("Filename cannot be empty!") }
        guard trimmed != ".", trimmed != "..", !trimmed.hasPrefix("."), trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil else {
            throw failure("Use a filename without /, \\, :, or control characters.")
        }
        guard trimmed.utf8.count <= 230 else { throw failure("The filename is too long.") }
        return trimmed
    }
    private static func failure(_ message: String) -> Error {
        NSError(domain: "LocalImageExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func encoded(_ image: NSImage, format: Format) throws -> Data {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { throw failure("The image could not be read.") }
        if format == .pdf {
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            view.image = NSImage(cgImage: cgImage, size: view.bounds.size)
            view.imageScaling = .scaleAxesIndependently
            return view.dataWithPDF(inside: view.bounds)
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cgImage.width, pixelsHigh: cgImage.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("The image could not be encoded.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        if format == .jpg { NSColor.white.setFill(); rect.fill() }
        context.cgContext.draw(cgImage, in: rect)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: format == .jpg ? .jpeg : .png, properties: format == .jpg ? [.compressionFactor: 1] : [:]) else { throw failure("The image could not be encoded.") }
        return data
    }
    private static func write(image: NSImage, directory: URL, name: String, format: Format, resolveCollision: Bool) throws -> URL {
        let name = try checkedName(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw failure("The save folder is unavailable. Choose another folder.") }
        let data = try encoded(image, format: format)
        let temporary = directory.appendingPathComponent(".iscreenshoter-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        var suffix = 0
        while true {
            let url = directory.appendingPathComponent(name + (suffix == 0 ? "" : " \(suffix)")).appendingPathExtension(format.rawValue)
            let result = temporary.withUnsafeFileSystemRepresentation { source in
                url.withUnsafeFileSystemRepresentation { destination in renameatx_np(AT_FDCWD, source!, AT_FDCWD, destination!, UInt32(RENAME_EXCL)) }
            }
            if result == 0 { return url }
            let code = errno
            guard code == EEXIST, resolveCollision else {
                if code == EEXIST { throw failure("Filename already exists!") }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Could not save the image: \(String(cString: strerror(code)))"])
            }
            suffix += 1
        }
    }

    static func verifyPanelLayout() throws {
        let controller = SaveController(image: NSImage(size: NSSize(width: 10, height: 10)), completion: nil)
        defer { controller.window?.close() }
        guard let view = controller.window?.contentView,
              view.bounds.size == NSSize(width: 480, height: 318),
              controller.reveal.title == "Open Folder", controller.reveal.frame == NSRect(x: 186, y: 119, width: 101, height: 18),
              controller.radios.map({ $0.frame.origin.x }) == [188, 270, 354],
              controller.errorLabel.font?.pointSize == 10 else { throw failure("Recovered Save panel layout failed") }
        controller.nameField.stringValue = ""
        controller.validate()
        guard controller.errorLabel.stringValue == "Filename cannot be empty!", !controller.save.isEnabled,
              controller.errorLabel.frame.height == 13 else { throw failure("Save empty-name state failed") }
        controller.format = .png
        controller.radios.forEach { $0.state = $0.tag == 1 ? .on : .off }
        controller.updateFormats()
        guard controller.radios[1].layer?.sublayers?.first?.cornerRadius == 5 else { throw failure("Save selection radius failed") }
        try writeParityRender(view, name: "save-empty-png")
        // Render through AppKit into a bitmap. This checks stored background channels, not final display color equivalence.
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw failure("Save offscreen render unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let sample = bitmap.colorAt(x: Int(CGFloat(bitmap.pixelsWide) * 470 / 480), y: bitmap.pixelsHigh / 2),
              abs(sample.redComponent - 33.0/255.0) < 0.02,
              abs(sample.greenComponent - sample.redComponent) < 0.01 else { throw failure("Save middle background render failed") }
    }

    static func verifyExports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iscreenshoter-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 137, pixelsHigh: 83, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Cannot prepare export verification") }
        if let data = bitmap.bitmapData { memset(data, 160, bitmap.bytesPerRow * bitmap.pixelsHigh) }
        let image = NSImage(size: NSSize(width: 137, height: 83))
        image.addRepresentation(bitmap)
        for format in Format.allCases {
            let url = try write(image: image, directory: directory, name: "Image", format: format, resolveCollision: false)
            let bytes = try Data(contentsOf: url)
            if format == .pdf {
                guard let provider = CGDataProvider(data: bytes as CFData), let pdf = CGPDFDocument(provider), let page = pdf.page(at: 1), page.getBoxRect(.mediaBox).size == NSSize(width: 137, height: 83) else { throw failure("PDF verification failed") }
            } else {
                guard let decoded = NSBitmapImageRep(data: bytes), decoded.pixelsWide == 137, decoded.pixelsHigh == 83 else { throw failure("\(format.label) verification failed") }
            }
        }
        let duplicate = try write(image: image, directory: directory, name: "Image", format: .jpg, resolveCollision: true)
        guard duplicate.lastPathComponent == "Image 1.jpg" else { throw failure("Collision suffix verification failed") }
        do {
            _ = try write(image: image, directory: directory, name: "Image", format: .jpg, resolveCollision: false)
            throw failure("Duplicate export overwrote a file")
        } catch let error as NSError where error.domain == "LocalImageExport" && error.localizedDescription.contains("already exists") {}
        for invalid in ["", "../Image", "a/b", "a\\b", ".", "..", "a:b"] {
            do { _ = try checkedName(invalid); throw failure("Invalid filename accepted") }
            catch let error as NSError where error.domain == "LocalImageExport" && error.localizedDescription != "Invalid filename accepted" {}
        }
    }
}
