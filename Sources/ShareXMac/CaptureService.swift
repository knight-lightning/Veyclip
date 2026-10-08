import AppKit
import ScreenCaptureKit
import CaptureCore

enum CaptureMode: String, CaseIterable, Identifiable {
    case allDisplays = "Entire Screen (All Displays)"
    case window = "Window", display = "Monitor", region = "Region"
    case regionLight = "Region (Light)", regionTransparent = "Region (Transparent Background)"
    var id: Self { self }
    static let recordingModes: [Self] = [.region, .display, .window]
    var isRegion: Bool { [.region, .regionLight, .regionTransparent].contains(self) }
}

struct CaptureSource {
    let filter: SCContentFilter
    let region: Rect?
    let scale: Double
    let bounds: Rect
    var displayFrame: CGRect = .zero
    var transparent = false

    func configuration(recording: Bool, cursor: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let dimensions = (region ?? bounds).pixels(scale: scale, even: recording)
        config.width = dimensions.width
        config.height = dimensions.height
        if let region { config.sourceRect = region.cgRect }
        config.showsCursor = cursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        if transparent { config.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0) }
        return config
    }
}

@MainActor
final class CaptureService {
    let selector = SelectionController()
    private(set) var lastRegion: RegionSelection?

    func source(for mode: CaptureMode, repeatLast: Bool = false) async throws -> CaptureSource? {
        // Query first: macOS owns the permission prompt and reports denial here.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownPID }
        if mode == .window {
            let windows = content.windows.filter {
                $0.owningApplication?.processID != ownPID && $0.frame.width > 40 && $0.frame.height > 40
                    && $0.windowLayer == 0
            }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            guard !windows.isEmpty else { throw CaptureError.message("No capturable windows were found.") }
            let alert = NSAlert()
            alert.messageText = "Choose a window"
            alert.informativeText = "Capture only this window."
            alert.addButton(withTitle: "Choose")
            alert.addButton(withTitle: "Cancel")
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 28))
            for window in windows {
                popup.addItem(withTitle: "\(window.owningApplication?.applicationName ?? "App") — \(window.title ?? "Untitled window")")
            }
            alert.accessoryView = popup
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let window = windows[popup.indexOfSelectedItem]
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return CaptureSource(filter: filter, region: nil, scale: Double(filter.pointPixelScale), bounds: Rect(filter.contentRect))
        }
        let display: SCDisplay
        var region: Rect?
        if mode.isRegion {
            let selected: RegionSelection?
            if repeatLast { selected = lastRegion } else { selected = await selector.select(light: mode == .regionLight) }
            guard let selected else { return nil }
            guard let match = content.displays.first(where: { $0.displayID == selected.displayID }) else {
                throw CaptureError.message("The selected display is no longer connected. Select a new region.")
            }
            display = match
            let bounds = Rect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
            guard bounds.intersection(selected.region) == selected.region else {
                throw CaptureError.message("The display layout changed. Select a new region.")
            }
            region = selected.region
            lastRegion = selected
        } else {
            guard !content.displays.isEmpty else { throw CaptureError.message("No displays were found.") }
            if content.displays.count == 1 { display = content.displays[0] }
            else {
                let alert = NSAlert()
                alert.messageText = "Choose a display"
                alert.addButton(withTitle: "Choose"); alert.addButton(withTitle: "Cancel")
                let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
                for (index, item) in content.displays.enumerated() {
                    popup.addItem(withTitle: "Display \(index + 1) · \(item.width) × \(item.height)")
                }
                alert.accessoryView = popup
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }
                display = content.displays[popup.indexOfSelectedItem]
            }
        }
        let filter: SCContentFilter
        if mode == .regionTransparent {
            let windows = content.windows.filter {
                $0.owningApplication?.processID != ownPID && $0.windowLayer == 0 && $0.frame.intersects(display.frame)
            }
            guard !windows.isEmpty else { throw CaptureError.message("No windows intersect this display.") }
            filter = SCContentFilter(display: display, including: windows)
        } else {
            filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        }
        return CaptureSource(filter: filter, region: region, scale: Double(filter.pointPixelScale),
                             bounds: Rect(x: 0, y: 0, width: display.frame.width, height: display.frame.height),
                             displayFrame: display.frame, transparent: mode == .regionTransparent)
    }

    func screenshot(source: CaptureSource, cursor: Bool) async throws -> CGImage {
        let size = (source.region ?? source.bounds).pixels(scale: source.scale)
        guard Double(size.width) * Double(size.height) <= 100_000_000 else {
            throw CaptureError.message("This screenshot is too large. Select a smaller region.")
        }
        // Allow the selection panels to leave the window compositor before capture.
        try await Task.sleep(for: .milliseconds(180))
        return try await SCScreenshotManager.captureImage(contentFilter: source.filter,
                                                          configuration: source.configuration(recording: false, cursor: cursor))
    }

    func allDisplays(cursor: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw CaptureError.message("No displays were found.") }
        let applications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let frames = content.displays.map(\.frame)
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let filters = content.displays.map { SCContentFilter(display: $0, excludingApplications: applications, exceptingWindows: []) }
        let scale = Double(filters.map(\.pointPixelScale).max() ?? 1)
        let width = Int((union.width * scale).rounded()), height = Int((union.height * scale).rounded())
        guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.message("The combined display image is too large. Capture one monitor instead.")
        }
        for (index, display) in content.displays.enumerated() {
            try Task.checkCancellation()
            let source = CaptureSource(filter: filters[index], region: nil, scale: Double(filters[index].pointPixelScale),
                                       bounds: Rect(x: 0, y: 0, width: display.frame.width, height: display.frame.height))
            let image = try await screenshot(source: source, cursor: cursor)
            let frame = display.frame
            context.draw(image, in: CGRect(x: (frame.minX - union.minX) * scale,
                                          y: (union.maxY - frame.maxY) * scale,
                                          width: frame.width * scale, height: frame.height * scale))
        }
        guard let image = context.makeImage() else { throw CaptureError.message("Couldn't combine the displays.") }
        return image
    }
}
