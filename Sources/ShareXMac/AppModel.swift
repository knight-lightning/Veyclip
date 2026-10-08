import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let library = CaptureLibrary()
    let recorder = RecordingController()
    private let capture = CaptureService()
    private var subscriptions: Set<AnyCancellable> = []
    private var editorWindows: [NSWindowController] = []
    private var captureTask: Task<Void, Never>?
    private var gifDeadline: Task<Void, Never>?
    private var recordingGIF = false
    @Published private(set) var automationLabel: String?
    @Published var screenshotDelay = min(10, max(0, UserDefaults.standard.integer(forKey: "screenshotDelay"))) {
        didSet { UserDefaults.standard.set(screenshotDelay, forKey: "screenshotDelay") }
    }
    @Published var autoInterval = max(1, UserDefaults.standard.integer(forKey: "autoInterval") == 0 ? 5 : UserDefaults.standard.integer(forKey: "autoInterval")) {
        didSet { UserDefaults.standard.set(autoInterval, forKey: "autoInterval") }
    }
    @Published var autoCount = max(1, UserDefaults.standard.integer(forKey: "autoCount") == 0 ? 10 : UserDefaults.standard.integer(forKey: "autoCount")) {
        didSet { UserDefaults.standard.set(autoCount, forKey: "autoCount") }
    }
    @Published var isWorking = false
    @Published var status = "Ready to capture"
    @Published var errorMessage: String?
    @Published private(set) var libraryReady = false
    @Published var showCursor = UserDefaults.standard.object(forKey: "showCursor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showCursor, forKey: "showCursor") }
    }
    @Published var systemAudio = UserDefaults.standard.object(forKey: "systemAudio") as? Bool ?? true {
        didSet { UserDefaults.standard.set(systemAudio, forKey: "systemAudio") }
    }
    @Published var microphone = UserDefaults.standard.bool(forKey: "microphone") {
        didSet { UserDefaults.standard.set(microphone, forKey: "microphone") }
    }
    @Published var openEditor = UserDefaults.standard.object(forKey: "openEditor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(openEditor, forKey: "openEditor") }
    }
    @Published var copyAfterCapture = UserDefaults.standard.bool(forKey: "copyAfterCapture") {
        didSet { UserDefaults.standard.set(copyAfterCapture, forKey: "copyAfterCapture") }
    }
    var canCapture: Bool { libraryReady && !isWorking && !recorder.isActive }
    var canRepeat: Bool { canCapture && capture.lastRegion != nil }
    var canCancelCapture: Bool { captureTask != nil }

    private init() {
        do { try library.load(); libraryReady = true }
        catch { errorMessage = "Couldn't load the capture library: \(error.localizedDescription)" }
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        recorder.onFailure = { [weak self] error in
            self?.gifDeadline?.cancel(); self?.recordingGIF = false; self?.report(error)
        }
        recorder.onStarted = { [weak self] in
            guard let self, self.recordingGIF else { return }
            self.gifDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.stopRecording()
            }
        }
        recorder.onExternalFinish = { [weak self] url in
            guard let self else { return }
            self.isWorking = true
            Task { @MainActor in
                _ = await self.finishRecording(url)
                self.isWorking = false
            }
        }
        Hotkeys.register(model: self)
    }

    func takeScreenshot(_ mode: CaptureMode, repeatLast: Bool = false) {
        guard canCapture else { return }
        isWorking = true
        status = "Choose what to capture"
        captureTask = Task {
            defer { isWorking = false; captureTask = nil }
            do {
                let image: CGImage
                if mode == .allDisplays {
                    try await waitForDelay()
                    image = try await capture.allDisplays(cursor: showCursor)
                } else {
                guard let source = try await capture.source(for: mode, repeatLast: repeatLast) else {
                    status = "Capture cancelled"; return
                }
                    try await waitForDelay()
                    image = try await capture.screenshot(source: source, cursor: showCursor)
                }
                try Task.checkCancellation()
                try saveScreenshot(image)
            } catch is CancellationError { status = "Capture cancelled" }
            catch { report(error) }
        }
    }
    private func waitForDelay() async throws {
        if screenshotDelay > 0 {
            for second in (1...screenshotDelay).reversed() {
                status = "Capture in \(second)…"
                try await Task.sleep(for: .seconds(1))
            }
        }
        try Task.checkCancellation()
    }
    private func saveScreenshot(_ image: CGImage, editAfter: Bool? = nil) throws {
        let item = try library.save(image)
        if copyAfterCapture { ImageFiles.copy(image) }
        status = "Saved \(item.filename)"
        if editAfter ?? openEditor { edit(item) }
    }
    func cancelCapture() {
        captureTask?.cancel()
        capture.selector.cancel()
    }
    func startAutoCapture() {
        guard canCapture else { return }
        isWorking = true; automationLabel = "Auto-capture"
        let count = min(100, max(1, autoCount)), interval = min(3600, max(1, autoInterval))
        captureTask = Task {
            defer { isWorking = false; captureTask = nil; automationLabel = nil }
            do {
                guard let source = try await capture.source(for: .region) else { status = "Auto-capture cancelled"; return }
                try await waitForDelay()
                for index in 0..<count {
                    try Task.checkCancellation()
                    let image = try await capture.screenshot(source: source, cursor: showCursor)
                    try Task.checkCancellation()
                    try saveScreenshot(image, editAfter: false)
                    status = "Auto-capture \(index + 1) / \(count) saved"
                    if index + 1 < count { try await Task.sleep(for: .seconds(interval)) }
                }
                status = "Auto-capture finished · \(count) screenshots saved"
            } catch is CancellationError { status = "Auto-capture stopped · saved screenshots kept" }
            catch { report(error) }
        }
    }
    func startScrollingCapture() {
        guard canCapture else { return }
        do { try ScrollingCapture.requestAccess() } catch { report(error); return }
        let alert = NSAlert()
        alert.messageText = "Capture a scrolling page"
        alert.informativeText = "Start at the top and select only the moving content. Exclude fixed headers, sidebars, and scrollbars. Keep the target app visible while capture scrolls it. Maximum 20 frames. Stop from the menu bar or your Stop Capture hotkey."
        alert.addButton(withTitle: "Select Region"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isWorking = true; automationLabel = "Scrolling capture"
        let recovery = library.temporary.appendingPathComponent("Scroll-\(UUID().uuidString)", isDirectory: true)
        captureTask = Task {
            defer { isWorking = false; captureTask = nil; automationLabel = nil }
            do {
                guard let source = try await capture.source(for: .region) else { status = "Scrolling capture cancelled"; return }
                try await waitForDelay()
                let result = try await ScrollingCapture.run(source: source, service: capture, recovery: recovery) { index in
                    self.status = "Scrolling · \(index) frames captured"
                }
                try Task.checkCancellation()
                try saveScreenshot(result.image)
                if result.reachedLimit { status = "Saved scrolling capture · 20-frame limit reached" }
            } catch is CancellationError { status = "Scrolling stopped · frames kept at \(recovery.path)" }
            catch { report(CaptureError.message("\(error.localizedDescription)\nRecovery frames: \(recovery.path)")) }
        }
    }
    func toggleRecording(_ mode: CaptureMode, gif: Bool = false) {
        if recorder.canStop { stopRecording(); return }
        guard canCapture else { return }
        isWorking = true
        recordingGIF = gif
        captureTask = Task {
            defer { isWorking = false; captureTask = nil }
            do {
                guard let source = try await capture.source(for: mode) else { recordingGIF = false; status = "Recording cancelled"; return }
                status = "Starting recording"
                try await recorder.start(source: source, destination: library.recordingURL(),
                                         systemAudio: !gif && systemAudio, microphone: !gif && microphone, cursor: showCursor, gif: gif)
                status = gif ? "Recording GIF · silent · stops after 60 seconds" : "Recording · stop from the menu bar or your recording hotkey"
            } catch is CancellationError { recordingGIF = false; status = "Recording cancelled" }
            catch { recordingGIF = false; report(error) }
        }
    }
    func stopRecording(quitAfter: Bool = false) {
        guard recorder.canStop, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let url = try await recorder.stop()
                let imported = await finishRecording(url)
                if quitAfter && imported { isWorking = false; NSApp.terminate(nil) }
            } catch { report(error) }
        }
    }
    private func finishRecording(_ url: URL) async -> Bool {
        gifDeadline?.cancel(); gifDeadline = nil
        let gif = recordingGIF
        recordingGIF = false
        do {
            let item: CaptureItem
            if gif {
                status = "Converting recording to GIF…"
                let destination = url.deletingPathExtension().appendingPathExtension("gif")
                try await GIFEncoder.encode(movie: url, destination: destination)
                item = try library.importGIF(destination)
                // The finalized MP4 is retained in InProgress as a recovery source.
            } else { item = try await library.importRecording(url) }
            status = "Saved \(item.filename)"
            return true
        } catch { report(error); return false }
    }
    func edit(_ item: CaptureItem) {
        guard item.kind == .screenshot else { NSWorkspace.shared.open(library.url(for: item)); return }
        do {
            let model = try EditorModel(item: item, library: library)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = item.filename
            window.minSize = NSSize(width: 800, height: 560)
            window.contentView = NSHostingView(rootView: EditorView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            editorWindows.removeAll { $0.window?.isVisible == false }
            let controller = NSWindowController(window: window)
            editorWindows.append(controller)
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch { report(error) }
    }
    func copy(_ item: CaptureItem) {
        do {
            if item.kind == .screenshot {
                let original = try ImageFiles.load(library.url(for: item))
                let document = try library.loadDocument(for: item)
                ImageFiles.copy(try AnnotationRenderer.render(original: original, document: document))
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([library.url(for: item) as NSURL])
            }
            status = "Copied to clipboard"
        } catch { report(error) }
    }
    func remove(_ item: CaptureItem, trash: Bool) {
        do {
            if trash { try library.trash(item) } else { try library.removeFromHistory(item) }
        } catch { report(error) }
    }
    func revealLibrary() { NSWorkspace.shared.open(library.outputFolder) }
    func report(_ error: Error) {
        status = "Action failed"
        errorMessage = error.localizedDescription
    }
}
