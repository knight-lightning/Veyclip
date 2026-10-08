import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", initial: .init(.r, modifiers: [.command, .option, .shift]))
    static let captureDisplay = Self("captureDisplay", initial: .init(.d, modifiers: [.command, .option, .shift]))
    static let captureWindow = Self("captureWindow", initial: .init(.w, modifiers: [.command, .option, .shift]))
    static let repeatRegion = Self("repeatRegion")
    static let toggleRecording = Self("toggleRecording", initial: .init(.v, modifiers: [.command, .option, .shift]))
    static let captureAll = Self("captureAll")
    static let captureLight = Self("captureLight")
    static let captureTransparent = Self("captureTransparent")
    static let recordGIF = Self("recordGIF")
    static let scrollingCapture = Self("scrollingCapture")
    static let autoCapture = Self("autoCapture")
    static let stopCapture = Self("stopCapture", initial: .init(.escape, modifiers: [.command, .option]))
}

@MainActor
enum Hotkeys {
    static let actions: [(String, KeyboardShortcuts.Name)] = [
        ("Capture region", .captureRegion), ("Capture display", .captureDisplay),
        ("Capture window", .captureWindow), ("Repeat last region", .repeatRegion),
        ("Start / stop region recording", .toggleRecording),
        ("Capture all displays", .captureAll), ("Light region", .captureLight),
        ("Transparent region", .captureTransparent), ("Start / stop GIF recording", .recordGIF),
        ("Scrolling capture", .scrollingCapture), ("Auto-capture", .autoCapture), ("Stop capture", .stopCapture)
    ]
    static func register(model: AppModel) {
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [weak model] in model?.takeScreenshot(.region) }
        KeyboardShortcuts.onKeyUp(for: .captureDisplay) { [weak model] in model?.takeScreenshot(.display) }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak model] in model?.takeScreenshot(.window) }
        KeyboardShortcuts.onKeyUp(for: .repeatRegion) { [weak model] in model?.takeScreenshot(.region, repeatLast: true) }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak model] in model?.toggleRecording(.region) }
        KeyboardShortcuts.onKeyUp(for: .captureAll) { [weak model] in model?.takeScreenshot(.allDisplays) }
        KeyboardShortcuts.onKeyUp(for: .captureLight) { [weak model] in model?.takeScreenshot(.regionLight) }
        KeyboardShortcuts.onKeyUp(for: .captureTransparent) { [weak model] in model?.takeScreenshot(.regionTransparent) }
        KeyboardShortcuts.onKeyUp(for: .recordGIF) { [weak model] in model?.toggleRecording(.region, gif: true) }
        KeyboardShortcuts.onKeyUp(for: .scrollingCapture) { [weak model] in model?.startScrollingCapture() }
        KeyboardShortcuts.onKeyUp(for: .autoCapture) { [weak model] in model?.startAutoCapture() }
        KeyboardShortcuts.onKeyUp(for: .stopCapture) { [weak model] in
            if model?.recorder.canStop == true { model?.stopRecording() }
            else { model?.cancelCapture() }
        }
    }
}
