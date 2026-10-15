import AppKit

// Every verification/demo process gets fresh preferences and storage. Never point
// fixtures at a user's real screenshots, export folder, or preference domain.
enum AppEnvironment {
    static let isTesting = CommandLine.arguments.contains("--verify") || CommandLine.arguments.contains("--render-demo")
    private static let suite = "org.hari.screenshoter.open.fixture." + UUID().uuidString
    static let defaults: UserDefaults = isTesting ? UserDefaults(suiteName: suite)! : .standard
    static let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    static var cacheDirectory: URL {
        isTesting ? workspace.appendingPathComponent("History", isDirectory: true) : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.hari.screenshoter.open", isDirectory: true)
    }
    static var defaultExportDirectory: URL {
        isTesting ? workspace.appendingPathComponent("Exports", isDirectory: true) : FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Screen Shoter Open", isDirectory: true)
    }
    static func prepare() throws {
        guard isTesting else { return }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defaults.register(defaults: ["saveDirectory": defaultExportDirectory.path, "captureModifiers": UInt32(768), "ocrModifiers": UInt32(768)])
    }
    static func cleanup() {
        guard isTesting else { return }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: workspace)
    }
    static func verifyIsolation() throws {
        guard isTesting, cacheDirectory.path.hasPrefix(workspace.path + "/"),
              defaultExportDirectory.path.hasPrefix(workspace.path + "/"),
              defaults !== UserDefaults.standard,
              defaults.stringArray(forKey: "savedImagePaths") == nil else {
            throw NSError(domain: "FixtureIsolation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Verification must use an isolated preference and history namespace"])
        }
    }
}
