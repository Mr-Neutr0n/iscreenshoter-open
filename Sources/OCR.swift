import AppKit
import Vision
import SwiftUI

private struct OCRFragment {
    let rect: CGRect
    let text: String
}

private struct OCRTextPair {
    let plain: String
    let table: String
}

private final class OCRWindow: NSWindow {
    var copyText: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { close(); return }
            if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                copyText?(); return
            }
        }
        super.sendEvent(event)
    }
}

private final class OCRPresentation: ObservableObject {
    @Published var image: NSImage?
    @Published var text = ""
    @Published var error = false
    @Published var copied = false
    @Published var table = false
    @Published var selectedLanguage = 0
    @Published var languageTitles: [String] = []
    var copy: () -> Void = {}
    var languageChanged: () -> Void = {}
    var tableChanged: () -> Void = {}
}

// This follows the current SwiftUI body, rather than the retired OCR nib.
// Geometry comes from c277c/c3cbc/c40d4/c43ac/c89ec; named colors come from the original catalog.
private struct OCRContent: View {
    @ObservedObject var model: OCRPresentation
    var body: some View {
        VStack(spacing: 0) {
            Text("Picture To Text").font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color("color-title-color"))
                .frame(height: 18).padding(.top, 7)
            HStack(spacing: 0) {
                ZStack {
                    Color(nsColor: NSColor(srgbRed: 38/255, green: 38/255, blue: 38/255, alpha: 1))
                    if let image = model.image { Image(nsImage: image).resizable() }
                }
                .frame(width: 300)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.vertical, 16).padding(.leading, 16)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recognize Language").font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color("color-title-color"))
                        Picker("Recognize Language", selection: $model.selectedLanguage) {
                            ForEach(model.languageTitles.indices, id: \.self) { index in Text(model.languageTitles[index]).tag(index) }
                        }.labelsHidden().onChange(of: model.selectedLanguage) { _,_ in model.languageChanged() }
                    }.padding(.vertical, 16)
                    VStack(spacing: 0) {
                        Color("color-line-bg").frame(height: 1)
                        ZStack {
                            Color.clear
                            if model.text.isEmpty {
                                OCRSpinner().frame(width: 30, height: 30).frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                TextEditor(text: $model.text).font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(model.error ? Color.red : Color.white)
                                    .scrollContentBackground(.hidden)
                                    .padding(.vertical, 8).padding(.leading, -3)
                                    .environment(\.colorScheme, .dark)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack(spacing: 4) {
                            Text("Optimise OCR results for tables").font(.system(size: 12, weight: .regular)).foregroundStyle(.white)
                            Toggle("Optimise OCR results for tables", isOn: $model.table).labelsHidden().toggleStyle(.switch)
                                .tint(Color("color_purchase_bg"))
                                .background(Color("color-toggle-bg"))
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .onChange(of: model.table) { _,_ in model.tableChanged() }
                            Spacer()
                        }.padding(.bottom, 8)
                        Color("color-line-bg").frame(height: 1)
                        HStack {
                            // The original left-hand actions invoke excluded cloud integrations.
                            Spacer(minLength: 32)
                            Button(action: model.copy) {
                                Text("Copy (⌘↩)").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color("color_purchase_bg"))
                                    .padding(.horizontal, 10).frame(height: 32)
                                    .background(Color("color-btn-bg"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 16)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("color-view-bg"))
        .overlay {
            if model.copied {
                HStack(spacing: 8) {
                    if let icon = publicAsset("icon_copy_ok") { Image(nsImage: icon) }
                    Text("Copied").font(.system(size: 14, weight: .regular))
                    Text("Command + V to paste").font(.system(size: 10, weight: .regular))
                }.foregroundStyle(.white).padding().background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
private struct OCRSpinner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        indicator.style = .spinning; indicator.startAnimation(nil); return indicator
    }
    func updateNSView(_ view: NSProgressIndicator, context: Context) {}
}

final class OCRController: NSWindowController, NSWindowDelegate {
    private static var shared: OCRController?
    private let model = OCRPresentation()
    private var codes: [String] = []
    private var image: NSImage?
    private var result = OCRTextPair(plain: "", table: "")
    private var requestID = 0

    static func present(image: NSImage) {
        let controller = shared ?? OCRController(); shared = controller
        controller.image = image; controller.model.image = image
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); controller.recognize()
    }
    private init() {
        let window = OCRWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 446), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = ""; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(named: "color-view-bg") ?? .windowBackgroundColor
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window); window.delegate = self
        model.table = AppEnvironment.defaults.bool(forKey: "ocrTables")
        loadLanguages()
        model.copy = { [weak self] in self?.copyResult() }
        model.languageChanged = { [weak self] in self?.changeLanguage() }
        model.tableChanged = { [weak self] in self?.changeFormatting() }
        window.contentViewController = NSHostingController(rootView: OCRContent(model: model))
        window.setContentSize(NSSize(width: 710, height: 446)); window.center()
        window.copyText = { [weak self] in self?.copyResult() }
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { requestID += 1 }
    private func loadLanguages() {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        codes = ["automatic"] + ((try? request.supportedRecognitionLanguages()) ?? ["en-US"])
        model.languageTitles = codes.map { code in code == "automatic" ? "Automatic" : (Locale.current.localizedString(forIdentifier: code) ?? code) }
        let selected = AppEnvironment.defaults.string(forKey: "ocrLanguage") ?? Locale.preferredLanguages.first ?? "en-US"
        model.selectedLanguage = codes.firstIndex(of: selected) ?? codes.firstIndex(where: { $0.hasPrefix(String(selected.prefix(2))) }) ?? 0
    }
    private func changeLanguage() {
        AppEnvironment.defaults.set(codes[model.selectedLanguage], forKey: "ocrLanguage"); recognize()
    }
    private func changeFormatting() {
        AppEnvironment.defaults.set(model.table, forKey: "ocrTables"); applyResult()
    }
    private func applyResult() { model.text = (model.table ? result.table : result.plain).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func copyResult() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.text, forType: .string)
        model.copied = true
    }
    private func recognize() {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        requestID += 1; let identity = requestID
        let code = codes[max(0, model.selectedLanguage)]
        result = OCRTextPair(plain: "", table: ""); model.text = ""; model.error = false; model.copied = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let pair = try Self.read(cg, language: code)
                DispatchQueue.main.async {
                    guard let self, self.requestID == identity else { return }
                    self.result = pair; self.applyResult()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.requestID == identity else { return }
                    self.model.error = true; self.model.text = "Text recognition failed!"
                }
            }
        }
    }
    private static func read(_ image: CGImage, language: String) throws -> OCRTextPair {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        if language != "automatic" { request.recognitionLanguages = [language] }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let fragments = (request.results ?? []).compactMap { item -> OCRFragment? in
            guard let text = item.topCandidates(1).first?.string else { return nil }
            let box = item.boundingBox
            return OCRFragment(rect: CGRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height), text: text)
        }
        return format(fragments)
    }
    private static func format(_ fragments: [OCRFragment]) -> OCRTextPair {
        var plain = "", previous: CGRect?
        for item in fragments {
            let sameRow = previous.map { $0.minY <= item.rect.midY && item.rect.midY <= $0.maxY } ?? true
            plain += (sameRow ? " " : "\r") + item.text; previous = item.rect
        }
        var rows: [[OCRFragment]] = [], row: [OCRFragment] = []
        for item in fragments.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            if let last = row.last {
                var a = last.rect, b = item.rect
                let right = max(a.maxX, b.maxX); a.size.width = right - a.minX; b.size.width = right - b.minX
                if a.height > b.height { a = a.insetBy(dx: 0, dy: (a.height - b.height) * 0.7) }
                else { b = b.insetBy(dx: 0, dy: (b.height - a.height) * 0.7) }
                if !a.intersects(b) { rows.append(row); row = [] }
            }
            row.append(item)
        }
        if !row.isEmpty { rows.append(row) }
        let table = rows.map { $0.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: "\t") }.joined(separator: "\r")
        return OCRTextPair(plain: plain.trimmingCharacters(in: .whitespacesAndNewlines), table: table.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @MainActor static func verifyLayout() throws {
        let controller = OCRController()
        defer { controller.window?.close() }
        guard let root = controller.window?.contentView,
              root.bounds.size == NSSize(width: 710, height: 446),
              controller.window?.titleVisibility == .hidden,
              controller.window?.standardWindowButton(.zoomButton)?.isHidden == true,
              ["color-view-bg", "color-title-color", "color-line-bg", "color-btn-bg", "color_purchase_bg", "color-toggle-bg"].allSatisfy({ NSColor(named: NSColor.Name($0)) != nil }) else {
            throw NSError(domain: "OCRVerification", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recovered OCR window or catalog colors failed"])
        }
        let sample = NSImage(size: NSSize(width: 300, height: 180))
        sample.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 300, height: 180).fill()
        ("LOCAL OCR 123" as NSString).draw(at: NSPoint(x: 20, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]); sample.unlockFocus()
        controller.model.image = sample
        controller.result = OCRTextPair(plain: "LOCAL OCR 123", table: "LOCAL\tOCR\t123")
        controller.model.table = false; controller.applyResult()
        guard controller.model.text == "LOCAL OCR 123" else { throw NSError(domain: "OCRVerification", code: 5) }
        try writeParityRender(root, name: "ocr-complete")
        controller.model.error = true; controller.model.text = "Text recognition failed!"
        try writeParityRender(root, name: "ocr-error")
    }

    @MainActor static func verifyRecognition() async throws {
        let cells = [OCRFragment(rect: CGRect(x: 120, y: 10, width: 70, height: 20), text: "B"), OCRFragment(rect: CGRect(x: 10, y: 10, width: 70, height: 20), text: "A"), OCRFragment(rect: CGRect(x: 10, y: 50, width: 70, height: 20), text: "C")]
        guard format(cells).table == "A\tB\rC" else { throw NSError(domain: "OCRVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "OCR table row order failed"]) }
        let image = NSImage(size: NSSize(width: 640, height: 140))
        image.lockFocus(); NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 140)).fill()
        ("LOCAL OCR 123" as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw NSError(domain: "OCRVerification", code: 2) }
        let pair: OCRTextPair = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try read(cg, language: "en-US")) } catch { continuation.resume(throwing: error) }
            }
        }
        guard pair.plain.contains("LOCAL"), pair.plain.contains("123") else { throw NSError(domain: "OCRVerification", code: 3, userInfo: [NSLocalizedDescriptionKey: "Synthetic image OCR failed: \(pair.plain)"]) }
    }
}
