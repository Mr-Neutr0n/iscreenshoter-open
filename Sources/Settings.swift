import AppKit
import SwiftUI
import ServiceManagement
import Carbon

private enum SettingsSection: Int, CaseIterable {
    case general, shortcuts, about
    var title: String { ["General", "Shortcuts", "About"][rawValue] }
}
private final class SettingsModel: ObservableObject {
    @Published var section: SettingsSection = .general
    @Published var folder = ProcessInfo.processInfo.environment["ISCREENSHOTER_RENDER_DIR"] != nil ? "/Users/demo/Pictures" : (UserDefaults.standard.string(forKey:"saveDirectory") ?? HistoryStore.shared.directory.path)
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var recordingPreference: String?
    weak var controller: SettingsController?
    var recorders: [ShortcutRecorder] = []
    func select(_ next: SettingsSection) { finishRecording(); section = next }
    func finishRecording() { recorders.forEach { $0.finish() } }
}
private struct SettingsShortcutField: NSViewRepresentable {
    let model: SettingsModel
    let preference: String
    let fallback: UInt32
    func makeNSView(context: Context) -> ShortcutRecorder {
        let recorder = ShortcutRecorder(frame:.zero)
        recorder.preference = preference; recorder.fallback = fallback
        recorder.owner = model.controller?.appDelegate
        recorder.changed = { [weak model] in model?.controller?.appDelegate?.dashboard.refresh() }
        recorder.font = .systemFont(ofSize:16); recorder.layer?.backgroundColor = NSColor.clear.cgColor
        recorder.recordingChanged = { [weak model] recording in model?.recordingPreference = recording ? preference : nil }
        recorder.updateTitle(); model.recorders.append(recorder)
        return recorder
    }
    func updateNSView(_ view: ShortcutRecorder, context: Context) { if !view.recording { view.updateTitle() } }
    static func dismantleNSView(_ view: ShortcutRecorder, coordinator: ()) { view.finish() }
}
private struct CurrentSettingsView: View {
    @ObservedObject var model: SettingsModel
    private let gray = Color(nsColor:parityColor(0x6B6B6B))
    var body: some View {
        HStack(spacing:0) {
            VStack(spacing:15) {
                ForEach(SettingsSection.allCases,id:\.rawValue) { section in
                    Button { model.select(section) } label: {
                        Text(section.title).font(.system(size:16))
                            .foregroundStyle(model.section == section ? Color.black : gray)
                            .padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading).frame(height:32)
                            .background(model.section == section ? Color(nsColor:parityColor(0xE7FE66)) : .clear,in:RoundedRectangle(cornerRadius:10,style:.continuous))
                    }
                        .buttonStyle(.plain)
                }
                Spacer()
                Button { model.finishRecording(); model.controller?.appDelegate?.quit() } label: {
                    Text("Quit").font(.system(size:16)).foregroundStyle(gray)
                        .padding(.horizontal,12).frame(minWidth:99)
                        .frame(height:28)
                        .background(Color(nsColor:parityColor(0x484848)),in:RoundedRectangle(cornerRadius:14,style:.continuous))
                }.buttonStyle(.plain)
            }.fixedSize(horizontal:true,vertical:false)
                .padding(.top,62).padding(.bottom,16).padding(.horizontal,16)
            Color(nsColor:parityColor(0x505050)).frame(width:1)
            VStack(alignment:.leading,spacing:0) {
                Text(model.section.title).font(.system(size:14)).foregroundStyle(gray)
                    .frame(height:30).padding(.leading,16)
                Color(nsColor:parityColor(0x505050)).frame(height:1)
                content
            }
        }.frame(width:520,height:306)
            .background(Color("323232"))
    }
    private func shortcutField(_ preference:String,fallback:UInt32) -> some View {
        SettingsShortcutField(model:model,preference:preference,fallback:fallback)
            .frame(width:222,height:32)
            .background(Color("color-btn-bg1"),in:RoundedRectangle(cornerRadius:4,style:.continuous))
            .overlay { RoundedRectangle(cornerRadius:4,style:.continuous).stroke(model.recordingPreference == preference ? Color("color_purchase_bg") : .clear,lineWidth:1) }
    }
    @ViewBuilder private var content: some View {
        switch model.section {
        case .general:
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:5) {
                    Text("Open the app when I log into my Mac").font(.system(size:16)).foregroundStyle(.white)
                    Spacer(minLength:5)
                    Toggle("",isOn:Binding(get:{ model.login },set:{ model.controller?.setLogin($0) }))
                        .labelsHidden().tint(Color(nsColor:parityColor(0x8A75EA))).environment(\.colorScheme,.dark)
                }
                Text("Save location").font(.system(size:16)).foregroundStyle(.white).padding(.top,24)
                Button { model.controller?.chooseFolder() } label: {
                    Text(model.folder).font(.system(size:16,weight:.light)).foregroundStyle(.white).truncationMode(.middle)
                        .padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading).frame(height:32)
                        .background(Color(nsColor:parityColor(0x484848)),in:RoundedRectangle(cornerRadius:4,style:.continuous))
                }
                    .buttonStyle(.plain).padding(.top,16)
                Spacer()
            }.padding(.horizontal,16).padding(.vertical,24)
        case .shortcuts:
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    Text("Screenshot").font(.system(size:16)).foregroundStyle(.white)
                    Spacer()
                    shortcutField("capture",fallback:0)
                }.padding(.bottom,16)
                HStack {
                    Text("OCR").font(.system(size:16)).foregroundStyle(.white)
                    Spacer()
                    shortcutField("ocr",fallback:17)
                }
                Text("⭐️ Choose a new shortcut if the one you set isn't working, as it may conflict with another shortcut.")
                    .font(.system(size:12)).foregroundStyle(.white).lineSpacing(3).padding(.top,20)
                Spacer()
            }.padding(16)
        case .about:
            VStack(alignment:.leading,spacing:0) {
                Text("Version: \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.system(size:16)).foregroundStyle(.white)
                // External support and website links are omitted from the local edition.
                Spacer()
            }.padding(.horizontal,16).padding(.vertical,24)
        }
    }
}

final class SettingsController: NSWindowController, NSWindowDelegate {
    weak var appDelegate: AppDelegate?
    private let model: SettingsModel
    init(owner: AppDelegate) {
        let model = SettingsModel(); self.model = model
        let host = NSHostingController(rootView:CurrentSettingsView(model:model))
        let window = NSWindow(contentViewController:host)
        window.styleMask = NSWindow.StyleMask(rawValue:0x8007)
        window.title = ""; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(named:NSColor.Name("323232")) ?? parityColor(0x323232)
        window.level = .normal; window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width:520,height:306)); window.center()
        super.init(window:window); appDelegate = owner; model.controller = self; window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    fileprivate func chooseFolder() {
        model.finishRecording(); guard let parent = window else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.beginSheetModal(for:parent) { [weak self] response in
            if response == .OK,let url = panel.url { UserDefaults.standard.set(url.path,forKey:"saveDirectory"); self?.model.folder = url.path }
        }
    }
    fileprivate func setLogin(_ enabled: Bool) {
        model.finishRecording()
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { alert("Could not change login startup: \(error.localizedDescription)") }
        model.login = SMAppService.mainApp.status == .enabled
    }
    func windowWillClose(_ notification:Notification) { model.finishRecording() }
    static func verifyCurrentLayout() throws {
        let owner = AppDelegate(); let controller = SettingsController(owner:owner)
        guard let window = controller.window else { throw NSError(domain:"SettingsVerification",code:1) }
        guard window.styleMask.rawValue == 0x8007,window.level == .normal,window.titleVisibility == .hidden,window.titlebarAppearsTransparent,
              window.standardWindowButton(.miniaturizeButton)?.isHidden == true,window.standardWindowButton(.zoomButton)?.isHidden == true else { throw NSError(domain:"SettingsVerification",code:2,userInfo:[NSLocalizedDescriptionKey:"Current Settings window construction differs from REA"]) }
        for section in SettingsSection.allCases {
            controller.model.select(section)
            window.contentView?.layoutSubtreeIfNeeded()
            if let view = window.contentView { try writeParityRender(view, name: "settings-" + section.title.lowercased(), background: window.backgroundColor) }
            guard window.contentView?.bounds.size == NSSize(width:520,height:306),controller.model.section == section else { throw NSError(domain:"SettingsVerification",code:3,userInfo:[NSLocalizedDescriptionKey:"Current Settings branch or size changed"]) }
        }
        controller.close()
        print("Settings verified: recovered 520×306 SwiftUI root, three sections, titled normal-level window and hidden minimize/zoom")
    }
}

func shortcutTitle(_ preference: String, fallback: UInt32) -> String {
    let defaults = UserDefaults.standard
    let code = UInt16(defaults.object(forKey: preference + "Key") as? UInt32 ?? fallback)
    let mods = UInt32(defaults.integer(forKey: preference + "Modifiers"))
    let labels: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"Space",36:"Return",48:"Tab",51:"Delete",123:"←",124:"→",125:"↓",126:"↑",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
    return (mods & UInt32(controlKey) != 0 ? "⌃" : "") + (mods & UInt32(optionKey) != 0 ? "⌥" : "") + (mods & UInt32(shiftKey) != 0 ? "⇧" : "") + (mods & UInt32(cmdKey) != 0 ? "⌘" : "") + (labels[code] ?? "Key \(code)")
}
final class ShortcutRecorder: NSButton {
    var preference = "capture"
    var fallback: UInt32 = 0
    var changed: (() -> Void)?
    weak var owner: AppDelegate?
    var recording = false
    var recordingChanged: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); isBordered = false; font = .systemFont(ofSize: 12); contentTintColor = .white; wantsLayer = true; layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor; layer?.cornerRadius = 3; target = self; action = #selector(begin) }
    required init?(coder: NSCoder) { fatalError() }
    func updateTitle() { title = shortcutTitle(preference, fallback: fallback) }
    @objc func begin() { window?.makeFirstResponder(self); recording = true; recordingChanged?(true); owner?.setShortcutRecording(true); title = "Press shortcut…" }
    func finish() { guard recording else { return }; recording = false; recordingChanged?(false); updateTitle(); owner?.setShortcutRecording(false) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        let other = preference == "capture" ? "ocr" : "capture"
        let defaults = UserDefaults.standard
        let otherCode = defaults.object(forKey: other + "Key") as? UInt32 ?? (other == "ocr" ? 17 : 0)
        if otherCode == UInt32(event.keyCode), UInt32(defaults.integer(forKey: other + "Modifiers")) == mods { NSSound.beep(); title = "Already used by " + other; return }
        let previousCode = defaults.object(forKey: preference + "Key")
        let previousModifiers = defaults.object(forKey: preference + "Modifiers")
        defaults.set(UInt32(event.keyCode), forKey: preference + "Key"); defaults.set(mods, forKey: preference + "Modifiers")
        recording = false; recordingChanged?(false); owner?.setShortcutRecording(false)
        if owner?.dashboard.shortcutError != nil {
            defaults.set(previousCode, forKey: preference + "Key"); defaults.set(previousModifiers, forKey: preference + "Modifiers")
            owner?.installHotKeys(); NSSound.beep(); updateTitle(); toolTip = "That shortcut is already in use. Your previous shortcut is unchanged."
        } else { updateTitle(); toolTip = nil }
        changed?()
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
}
