import AppKit
import CaptureCore

struct RegionSelection {
    let displayID: CGDirectDisplayID
    let region: Rect
}

@MainActor
final class SelectionController {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var previousApp: NSRunningApplication?

    func select(light: Bool = false) async -> RegionSelection? {
        guard continuation == nil, !Task.isCancelled else { return nil }
        previousApp = NSWorkspace.shared.frontmostApplication
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless],
                                           backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.isReleasedWhenClosed = false
                let view = RegionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.light = light
                view.onCancel = { [weak self] in self?.finish(nil) }
                view.onSelect = { [weak self] rect in
                    let region = Rect.captureRegion(local: Rect(rect), displayHeight: screen.frame.height)
                    self?.finish(RegionSelection(displayID: number.uint32Value, region: region))
                }
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
            }
            guard !panels.isEmpty else { finish(nil); return }
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let target = panels.first { $0.frame.contains(mouse) } ?? panels[0]
            target.makeKey()
            target.makeFirstResponder(target.contentView)
        }
    }

    func cancel() { finish(nil) }

    private func finish(_ selection: RegionSelection?) {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        previousApp?.activate(options: [])
        previousApp = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: selection)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionView: NSView {
    var light = false
    var onCancel: (() -> Void)?
    var onSelect: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = Rect(from: Point(start), to: Point(end)).cgRect.intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let selection, selection.width >= 4, selection.height >= 4 { onSelect?(selection) }
        else { start = nil; selection = nil; needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(light ? 0.01 : 0.28).setFill()
        bounds.fill()
        if let selection {
            NSGraphicsContext.current?.cgContext.clear(selection)
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 2
            outline.stroke()
            let label = "\(Int(selection.width)) × \(Int(selection.height)) pt"
            (label as NSString).draw(at: CGPoint(x: selection.minX + 8, y: max(8, selection.minY - 25)),
                                    withAttributes: [.foregroundColor: NSColor.white,
                                                     .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)])
        }
        ("Drag to select a region · Esc to cancel" as NSString).draw(
            at: CGPoint(x: 28, y: bounds.height - 50),
            withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 18, weight: .medium)])
    }
}
