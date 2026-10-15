import AppKit
import ScreenCaptureKit
import AVFoundation
import UniformTypeIdentifiers

final class RecorderController: NSWindowController, NSWindowDelegate, SCStreamDelegate, SCStreamOutput {
    static var shared: RecorderController?
    static let stateDidChange = Notification.Name("RecordingStateChanged")
    static var isActive: Bool { shared?.hasActiveRecording ?? false }
    static func stopActiveRecording() { shared?.requestStop() }
    static func present() {
        if shared == nil { shared = RecorderController() }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let source = NSPopUpButton()
    private let audio = NSButton(checkboxWithTitle: "Record system audio", target: nil, action: nil)
    private let cursor = NSButton(checkboxWithTitle: "Show pointer", target: nil, action: nil)
    private let start = NSButton(title: "Start recording", target: nil, action: nil)
    private let stop = NSButton(title: "Stop and save", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "Choose a screen or window to record.")
    private let duration = NSTextField(labelWithString: "00:00")
    private let queue = DispatchQueue(label: "local.iscreenshoter.recorder")
    private var displays: [SCDisplay] = []
    private var windows: [SCWindow] = []
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var acceptingSamples = false
    private var outputURL: URL?
    private var temporaryURL: URL?
    private var startedAt: Date?
    private var timer: Timer?
    private var busy = false
    private var recording = false
    private var stopCompletion: (() -> Void)?
    private var stopRequested = false
    var hasActiveRecording: Bool { recording || busy }

    func stopForTermination(completion: @escaping () -> Void) {
        if !hasActiveRecording { completion(); return }
        stopCompletion = completion
        requestStop()
    }

    /// Stop requests also work while ScreenCaptureKit is still starting.
    func requestStop() {
        guard hasActiveRecording else { return }
        stopRequested = true
        if recording && !busy { stopRecording() }
    }

    private init(loadSources: Bool = true) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 310),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Screen recording"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        let view = NSView(frame: window.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.95, blue: 1, alpha: 1).cgColor
        window.contentView = view
        let title = NSTextField(labelWithString: "Record your screen")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.frame = NSRect(x: 24, y: 251, width: 290, height: 30)
        view.addSubview(title)
        duration.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        duration.alignment = .right
        duration.frame = NSRect(x: 331, y: 251, width: 94, height: 29)
        view.addSubview(duration)
        source.frame = NSRect(x: 24, y: 205, width: 402, height: 30)
        source.addItem(withTitle: "Loading screens and windows…")
        source.isEnabled = false
        view.addSubview(source)
        audio.frame = NSRect(x: 24, y: 167, width: 270, height: 24)
        audio.state = .on
        view.addSubview(audio)
        cursor.frame = NSRect(x: 24, y: 137, width: 270, height: 24)
        cursor.state = .on
        view.addSubview(cursor)
        status.frame = NSRect(x: 24, y: 86, width: 402, height: 37)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byWordWrapping
        view.addSubview(status)
        start.frame = NSRect(x: 24, y: 28, width: 195, height: 34)
        start.bezelStyle = .rounded
        start.contentTintColor = NSColor(calibratedRed: 0.49, green: 0.32, blue: 0.84, alpha: 1)
        start.target = self
        start.action = #selector(startRecording)
        start.isEnabled = false
        view.addSubview(start)
        stop.frame = NSRect(x: 231, y: 28, width: 195, height: 34)
        stop.bezelStyle = .rounded
        stop.target = self
        stop.action = #selector(stopRecording)
        stop.isEnabled = false
        view.addSubview(stop)
        if loadSources { Task { await self.loadSources() } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func loadSources() async {
        guard CGPreflightScreenCaptureAccess() else {
            await MainActor.run {
                self.source.removeAllItems()
                self.source.addItem(withTitle: "Screen Recording permission required")
                self.source.isEnabled = false
                self.start.title = "Allow screen access"
                self.start.isEnabled = true
                self.status.stringValue = "Allow screen access to list screens and windows."
            }
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            await MainActor.run {
                self.displays = content.displays
                self.windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width > 100 && $0.frame.height > 60 && !($0.title ?? "").isEmpty }
                self.start.title = "Start recording"
                self.source.removeAllItems()
                for (index, display) in self.displays.enumerated() {
                    self.source.addItem(withTitle: "Screen \(index + 1) · \(display.width) × \(display.height)")
                }
                for window in self.windows {
                    self.source.addItem(withTitle: "\(window.owningApplication?.applicationName ?? "App") · \(window.title ?? "Window")")
                }
                self.source.isEnabled = !self.displays.isEmpty || !self.windows.isEmpty
                self.start.isEnabled = self.source.isEnabled
            }
        } catch {
            await MainActor.run { self.showError(error, context: "Screen access is unavailable. Allow Screen Recording in System Settings, then reopen this window.") }
        }
    }

    @objc private func startRecording() {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            Task { await loadSources() }
            return
        }
        guard !busy, !recording, source.indexOfSelectedItem >= 0 else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Recording \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-" )).mp4"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.stopRequested = false
            self.busy = true
            self.updateControls()
            self.status.stringValue = "Starting recording…"
            let selected = self.source.indexOfSelectedItem
            let includeAudio = self.audio.state == .on
            let showCursor = self.cursor.state == .on
            Task {
                do {
                    try await self.begin(url: url, selected: selected, includeAudio: includeAudio, showCursor: showCursor)
                    await MainActor.run {
                        self.busy = false
                        self.recording = true
                        self.startedAt = Date()
                        self.status.stringValue = "Recording locally. Stop to finish and save the video."
                        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateDuration() }
                        self.updateControls()
                        if self.stopRequested { self.stopRecording() }
                    }
                } catch {
                    await self.abort()
                    await MainActor.run { self.busy = false; self.updateControls(); self.showError(error, context: "Could not start recording."); self.completePendingStop() }
                }
            }
        }
    }

    private func begin(url: URL, selected: Int, includeAudio: Bool, showCursor: Bool) async throws {
        let filter: SCContentFilter
        let width: Int
        let height: Int
        if selected < displays.count {
            let display = displays[selected]
            // Exclude this app's controls from full-display recordings.
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            width = display.width
            height = display.height
        } else {
            let window = windows[selected - displays.count]
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            width = Int(window.frame.width * scale)
            height = Int(window.frame.height * scale)
        }
        let config = SCStreamConfiguration()
        config.width = max(2, width / 2 * 2)
        config.height = max(2, height / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.showsCursor = showCursor
        config.capturesAudio = includeAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let stagingURL = url.deletingLastPathComponent().appendingPathComponent(".recording-\(UUID().uuidString).mp4")
        let assetWriter = try AVAssetWriter(outputURL: stagingURL, fileType: .mp4)
        let video = Self.makeVideoInput(width: config.width, height: config.height)
        guard assetWriter.canAdd(video) else { throw recordingError("The video encoder cannot record this screen size.") }
        assetWriter.add(video)
        var audioTrack: AVAssetWriterInput?
        if includeAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw recordingError("The audio encoder is unavailable.") }
            assetWriter.add(input)
            audioTrack = input
        }
        guard assetWriter.startWriting() else {
            let error = assetWriter.error ?? recordingError("The output file could not be opened.")
            assetWriter.cancelWriting()
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
        queue.sync {
            self.writer = assetWriter
            self.videoInput = video
            self.audioInput = audioTrack
            self.sessionStarted = false
            self.acceptingSamples = true
            self.outputURL = url
            self.temporaryURL = stagingURL
        }
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if includeAudio { try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        stream = capture
        try await capture.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard acceptingSamples, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer), let writer else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete else { return }
            if !sessionStarted {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                sessionStarted = true
            }
            if videoInput?.isReadyForMoreMediaData == true { _ = videoInput?.append(sampleBuffer) }
        case .audio:
            if sessionStarted, audioInput?.isReadyForMoreMediaData == true { _ = audioInput?.append(sampleBuffer) }
        default: break
        }
        if writer.status == .failed {
            acceptingSamples = false
            DispatchQueue.main.async { self.finishAfterFailure(writer.error ?? self.recordingError("The encoder stopped.")) }
        }
    }

    @objc private func stopRecording() {
        guard recording, !busy else { return }
        busy = true
        timer?.invalidate()
        timer = nil
        status.stringValue = "Finishing video…"
        updateControls()
        Task {
            var stopError: Error?
            do { try await stream?.stopCapture() } catch { stopError = error }
            let result: Result<URL, Error> = await withCheckedContinuation { continuation in
                queue.async {
                    self.acceptingSamples = false
                    guard let writer = self.writer, let url = self.outputURL, self.sessionStarted else {
                        self.writer?.cancelWriting()
                        if let temporary = self.temporaryURL { try? FileManager.default.removeItem(at: temporary) }
                        continuation.resume(returning: .failure(self.recordingError("No video frames were captured.")))
                        return
                    }
                    guard writer.status == .writing else {
                        continuation.resume(returning: .failure(writer.error ?? self.recordingError("The video encoder stopped before the recording finished.")))
                        return
                    }
                    self.videoInput?.markAsFinished()
                    self.audioInput?.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed, let temporary = self.temporaryURL {
                            do {
                                if FileManager.default.fileExists(atPath: url.path) {
                                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                                } else {
                                    try FileManager.default.moveItem(at: temporary, to: url)
                                }
                                continuation.resume(returning: .success(url))
                            } catch {
                                continuation.resume(returning: .failure(self.recordingError("The video was recorded but could not be moved to the chosen location. It remains at \(temporary.path). \(error.localizedDescription)")))
                            }
                        }
                        else { continuation.resume(returning: .failure(writer.error ?? self.recordingError("The recording could not be saved."))) }
                    }
                }
            }
            await MainActor.run {
                self.recording = false
                self.busy = false
                self.stream = nil
                self.updateControls()
                switch result {
                case .success(let url):
                    self.status.stringValue = "Saved \(url.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    if let stopError { self.showError(stopError, context: "The captured video was saved, but screen capture ended unexpectedly.") }
                case .failure(let error): self.showError(error, context: "Could not save recording.")
                }
                self.completePendingStop()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.finishAfterFailure(error) }
    }

    private func finishAfterFailure(_ error: Error) {
        guard !busy else { return }
        if recording { stopRecording() }
        showError(error, context: "Screen capture stopped.")
    }

    private func abort() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync {
            self.acceptingSamples = false
            self.writer?.cancelWriting()
            self.writer = nil
            if let url = self.temporaryURL { try? FileManager.default.removeItem(at: url) }
            self.outputURL = nil
        }
    }

    private func completePendingStop() {
        stopRequested = false
        let completion = stopCompletion
        stopCompletion = nil
        completion?()
    }

    private func updateDuration() {
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? Date()))
        duration.stringValue = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func updateControls() {
        source.isEnabled = !recording && !busy
        audio.isEnabled = !recording && !busy
        cursor.isEnabled = !recording && !busy
        start.isEnabled = !recording && !busy && source.numberOfItems > 0
        stop.isEnabled = recording && !busy
        NotificationCenter.default.post(name: Self.stateDidChange, object: self,
                                        userInfo: ["active": hasActiveRecording, "recording": recording, "busy": busy])
    }

    private func showError(_ error: Error, context: String) {
        status.stringValue = context
        let alert = NSAlert()
        alert.messageText = context
        alert.informativeText = error.localizedDescription
        if let window { alert.beginSheetModal(for: window) }
    }

    private func recordingError(_ description: String) -> Error {
        NSError(domain: "LocalScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private static func makeVideoInput(width: Int, height: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(30_000_000, width * height * 4), AVVideoExpectedSourceFrameRateKey: 30]
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }

    /// Checks the production H.264 encoder and MP4 container without screen capture.
    static func verifyEncoding() async throws {
        func failure(_ message: String) -> Error {
            NSError(domain: "RecorderVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iscreenshoter-verify-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = makeVideoInput(width: 320, height: 180)
        guard writer.canAdd(input) else { throw failure("H.264 input unavailable") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Cannot start MP4 writer") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            var pixel: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else {
                writer.cancelWriting()
                throw failure("Cannot create verification frame")
            }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let address = CVPixelBufferGetBaseAddress(pixel) {
                memset(address, Int32(frame * 7), CVPixelBufferGetBytesPerRow(pixel) * 180)
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            var description: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &description) == noErr, let description else {
                writer.cancelWriting()
                throw failure("Cannot create video description")
            }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(frame), timescale: 30), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else {
                writer.cancelWriting()
                throw failure("Cannot create video sample")
            }
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard input.isReadyForMoreMediaData, input.append(sample) else {
                writer.cancelWriting()
                throw writer.error ?? failure("Cannot encode verification sample")
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? failure("Cannot finalize MP4") }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds > 0.9 && duration.seconds < 1.1 else { throw failure("Unexpected MP4 duration: \(duration.seconds)") }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw failure("MP4 has no video track") }
        let descriptions = try await track.load(.formatDescriptions)
        guard let format = descriptions.first, CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264 else { throw failure("Output codec is not H.264") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("Cannot decode MP4") }
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetImageBuffer(sample) != nil else { throw failure("Decoded frame has no image") }
            count += 1
        }
        guard reader.status == .completed, count == 30 else { throw reader.error ?? failure("Expected 30 decoded frames, got \(count)") }
    }

    /// Exercises startup-stop handoff and state notifications without permission or capture.
    static func verifyControls() throws {
        let controller = RecorderController(loadSources: false)
        var states: [[String: Bool]] = []
        let observer = NotificationCenter.default.addObserver(forName: stateDidChange, object: controller, queue: nil) { note in
            states.append(note.userInfo as? [String: Bool] ?? [:])
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        func check(_ valid: Bool, _ message: String) throws {
            if !valid { throw NSError(domain: "RecorderVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        controller.requestStop()
        try check(!controller.stopRequested, "Idle recorder accepted a stop request")
        controller.busy = true
        controller.updateControls()
        try check(controller.hasActiveRecording, "Starting recorder must remain visible as active")
        controller.requestStop()
        try check(controller.stopRequested, "Stop during startup was lost")
        try check(!controller.windowShouldClose(controller.window!), "Closing during startup must wait for stop and save")
        controller.busy = false
        controller.completePendingStop()
        controller.updateControls()
        try check(!controller.stopRequested && !controller.hasActiveRecording, "Finished recorder did not clear pending stop")
        try check(states.count == 2 && states[0]["active"] == true && states[1]["active"] == false,
                  "Recording indicator did not receive startup and completion state")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if hasActiveRecording {
            requestStop()
            return false
        }
        Self.shared = nil
        return true
    }
}
