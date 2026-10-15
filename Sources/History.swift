import AppKit
import ImageIO

/// Only app-owned cache entries are deleted by retention or history removal.
/// Explicit exports are references and always survive those operations.
final class HistoryStore {
    static let shared = HistoryStore()
    static let retentionDays = 7
    static let maximumCount = 200
    static let maximumBytes = 100 * 1024 * 1024
    private struct Entry: Codable {
        let path: String
        let added: Date
        let owned: Bool
    }
    let directory: URL
    private let defaults: UserDefaults
    private var entries: [Entry]
    private let now: () -> Date
    var historyEnabled: Bool { defaults.bool(forKey: "historyEnabled") }

    init(directory: URL = AppEnvironment.cacheDirectory.appendingPathComponent("Image", isDirectory: true), defaults: UserDefaults = AppEnvironment.defaults, now: @escaping () -> Date = Date.init) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath(); self.defaults = defaults; self.now = now
        entries = (defaults.data(forKey: "historyIndex").flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []).map { Entry(path: Self.canonicalPath($0.path), added: $0.added, owned: $0.owned) }
        // Upgrade once. Saved exports are references even if the old save folder was the cache.
        if !defaults.bool(forKey: "historyIndexMigrated") {
            let exported = Set((defaults.stringArray(forKey: "savedImagePaths") ?? []).map(Self.canonicalPath))
            for path in exported where FileManager.default.fileExists(atPath: path) {
                entries.append(Entry(path: path, added: (try? URL(fileURLWithPath:path).resourceValues(forKeys:[.creationDateKey]).creationDate) ?? now(), owned: false))
            }
            let oldFiles = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys:[.creationDateKey])) ?? []
            for url in oldFiles.map({ $0.standardizedFileURL.resolvingSymlinksInPath() }) where !exported.contains(url.path) && url.lastPathComponent.hasPrefix("Screen Shoter Open - ") && url.pathExtension == "jpg" {
                entries.append(Entry(path: url.path, added: (try? url.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? now(), owned: true))
            }
            defaults.set(true, forKey: "historyIndexMigrated"); defaults.removeObject(forKey: "savedImagePaths")
            persist()
        }
        prune()
    }
    private static func canonicalPath(_ path: String) -> String { URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath().path }
    private func persist() { if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey:"historyIndex") } }
    private func changed() { persist(); NotificationCenter.default.post(name:Notification.Name("HistoryChanged"),object:nil) }
    private func deleteCache(_ entry: Entry) {
        let url = URL(fileURLWithPath:entry.path).standardizedFileURL
        guard entry.owned, Self.canonicalPath(url.deletingLastPathComponent().path) == Self.canonicalPath(directory.path) else { return }
        try? FileManager.default.removeItem(at:url)
    }
    private func prune() {
        let previous = entries.count
        let cutoff = now().addingTimeInterval(-Double(Self.retentionDays * 24 * 60 * 60))
        var bytes = 0, kept = 0, seen = Set<String>()
        entries = entries.sorted { $0.added > $1.added }.filter { entry in
            guard seen.insert(entry.path).inserted else { return false }
            let url = URL(fileURLWithPath:entry.path)
            let size = (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            let withinBudget = !entry.owned || bytes + size <= Self.maximumBytes
            let keep = historyEnabled && entry.added >= cutoff && kept < Self.maximumCount && withinBudget && FileManager.default.fileExists(atPath:entry.path)
            if keep { kept += 1; if entry.owned { bytes += size } }
            if !keep { deleteCache(entry) }
            return keep
        }
        if entries.count != previous { persist() }
    }
    var files: [URL] { prune(); return entries.map { URL(fileURLWithPath:$0.path) } }
    func setEnabled(_ enabled: Bool) { defaults.set(enabled, forKey:"historyEnabled"); if !enabled { clear() } else { changed() } }
    func recordSaved(url: URL) {
        guard historyEnabled else { return }
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        entries.removeAll { $0.path == url.path }
        entries.insert(Entry(path:url.path,added:now(),owned:false),at:0); prune(); changed()
    }
    @discardableResult func add(_ image: NSImage) -> URL? {
        guard historyEnabled else { return nil }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil), let data = NSBitmapImageRep(cgImage:cg).representation(using:.jpeg,properties:[.compressionFactor:1]), data.count <= Self.maximumBytes else { return nil }
            let url = directory.appendingPathComponent("Screen Shoter Open - " + UUID().uuidString + ".jpg")
            try data.write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            entries.insert(Entry(path:url.path,added:now(),owned:true),at:0); prune(); changed(); return url
        } catch { alert("Could not save screenshot history: \(error.localizedDescription)"); return nil }
    }
    func removeFromHistory(_ urls: [URL]) {
        let paths = Set(urls.map { Self.canonicalPath($0.path) })
        for entry in entries where paths.contains(entry.path) { deleteCache(entry) }
        entries.removeAll { paths.contains($0.path) }; changed()
    }
    func clear() { entries.forEach(deleteCache); entries.removeAll(); changed() }
    /// Explicit destructive action. Callers must label it as Move to Trash.
    func trash(_ url: URL) throws {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.trashItem(at:url,resultingItemURL:nil)
        entries.removeAll { $0.path == url.path }; changed()
    }
    static func thumbnail(at url: URL, maximumPixels: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:maximumPixels,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }
    static func verifyBehavior() throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("history-verification-" + UUID().uuidString)
        let suite = "history-verification-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:fixture); defaults.removePersistentDomain(forName:suite) }
        var time = Date()
        let store = HistoryStore(directory:fixture.appendingPathComponent("cache"),defaults:defaults,now:{time})
        let image = NSImage(size:NSSize(width:1200,height:800)); image.lockFocus(); NSColor.red.setFill(); NSRect(x:0,y:0,width:1200,height:800).fill(); image.unlockFocus()
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw NSError(domain:"HistoryVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message]) } }
        try require(store.add(image) == nil && store.files.isEmpty,"New installations must not persist clipboard captures")
        store.setEnabled(true)
        let export = fixture.appendingPathComponent("export.jpg")
        let data = NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!).representation(using:.jpeg,properties:[:])!
        try data.write(to:export); store.recordSaved(url:export)
        guard let cache = store.add(image), let thumb = thumbnail(at:export) else { throw NSError(domain:"HistoryVerification",code:2) }
        try require(max(thumb.size.width,thumb.size.height) <= 160,"Thumbnail decoding must be bounded")
        store.removeFromHistory([export,cache])
        try require(FileManager.default.fileExists(atPath:export.path) && !FileManager.default.fileExists(atPath:cache.path),"History removal must preserve exports")
        store.recordSaved(url:export); let expired = store.add(image)!
        time = time.addingTimeInterval(Double((retentionDays + 1) * 86400))
        try require(store.files.isEmpty && !FileManager.default.fileExists(atPath:expired.path) && FileManager.default.fileExists(atPath:export.path),"Retention must remove cache only")
        store.recordSaved(url:export); _ = store.add(image); store.clear()
        try require(store.files.isEmpty && FileManager.default.fileExists(atPath:export.path),"Clear history must preserve exports")
        // Actual export fixtures test the count cap without source-image decoding.
        for index in 0...maximumCount {
            let file = fixture.appendingPathComponent("export-\(index).jpg")
            try Data([UInt8(index % 256)]).write(to:file); store.recordSaved(url:file)
        }
        try require(store.files.count == maximumCount,"History must enforce the item cap")
        store.clear()
        // Sparse files exercise the byte cap without allocating screenshot-sized memory.
        try FileManager.default.createDirectory(at:store.directory,withIntermediateDirectories:true)
        var hugeEntries: [Entry] = []
        for index in 0..<2 {
            let file = store.directory.appendingPathComponent("large-\(index).jpg")
            FileManager.default.createFile(atPath:file.path,contents:nil)
            let handle = try FileHandle(forWritingTo:file)
            try handle.truncate(atOffset:UInt64(maximumBytes * 3 / 5)); try handle.close()
            hugeEntries.append(Entry(path:file.path,added:time.addingTimeInterval(-Double(index)),owned:true))
        }
        store.entries = hugeEntries
        try require(store.files.count == 1 && !FileManager.default.fileExists(atPath:hugeEntries[1].path),"History must enforce cache byte cap")
        store.clear()
        store.recordSaved(url:export); store.setEnabled(false)
        try require(store.files.isEmpty && store.add(image) == nil && FileManager.default.fileExists(atPath:export.path),"Opt-out must clear history without deleting exports")
        // The old version allowed exports inside its cache directory. Migration
        // must recognize those explicit saves before removing any old captures.
        let legacy = fixture.appendingPathComponent("legacy",isDirectory:true)
        try FileManager.default.createDirectory(at:legacy,withIntermediateDirectories:true)
        let legacyExport = legacy.appendingPathComponent("Screen Shoter Open - saved.jpg")
        let legacyCache = legacy.appendingPathComponent("Screen Shoter Open - cached.jpg")
        try data.write(to:legacyExport); try data.write(to:legacyCache)
        defaults.removeObject(forKey:"historyIndex"); defaults.set(false,forKey:"historyIndexMigrated")
        defaults.set([legacyExport.path],forKey:"savedImagePaths")
        _ = HistoryStore(directory:legacy,defaults:defaults)
        try require(FileManager.default.fileExists(atPath:legacyExport.path) && !FileManager.default.fileExists(atPath:legacyCache.path),"Upgrade must preserve exports saved inside the legacy cache")
        print("History verified: opt-in persistence, seven-day expiry, export-safe removal and clear, count and byte caps, bounded thumbnail decoding")
    }
}
