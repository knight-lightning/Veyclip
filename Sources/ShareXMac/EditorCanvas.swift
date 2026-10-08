import AppKit
import Combine
import CaptureCore
import SwiftUI

@MainActor
struct EditorCanvas: NSViewRepresentable {
    @ObservedObject var model: EditorModel
    func makeNSView(context: Context) -> CanvasView { CanvasView(model: model) }
    func updateNSView(_ view: CanvasView, context: Context) { view.refresh() }
}

@MainActor
final class CanvasView: NSView {
    private let model: EditorModel
    private var image: NSImage?
    private var renderDocument: EditorDocument?
    private var start: Point?
    private var moving: Annotation?
    private var resizing: Annotation?
    private var draft: Annotation?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: EditorModel) { self.model = model; super.init(frame: .zero); refresh() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var imageRect: CGRect {
        let rect = model.visibleRect
        let fitted = min(max(1, bounds.width - 60) / rect.width, max(1, bounds.height - 60) / rect.height)
        let scale = fitted * model.zoom
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + model.pan.width,
                      y: (bounds.height - size.height) / 2 + model.pan.height, width: size.width, height: size.height)
    }
    private func imagePoint(_ event: NSEvent, clamp: Bool = true) -> Point {
        let local = convert(event.locationInWindow, from: nil)
        let rect = imageRect, crop = model.visibleRect
        var point = Point(x: crop.x + (local.x - rect.minX) * crop.width / rect.width,
                          y: crop.y + (local.y - rect.minY) * crop.height / rect.height)
        if clamp {
            point.x = min(crop.x + crop.width, max(crop.x, point.x))
            point.y = min(crop.y + crop.height, max(crop.y, point.y))
        }
        return point
    }
    private func viewRect(_ rect: CGRect) -> CGRect {
        let crop = model.visibleRect, display = imageRect
        let scale = display.width / crop.width
        return CGRect(x: display.minX + (rect.minX - crop.x) * scale,
                      y: display.minY + (rect.minY - crop.y) * scale, width: rect.width * scale, height: rect.height * scale)
    }
    func refresh() {
        let document = model.effectiveDocument
        if document != renderDocument {
            do {
                let rendered = try AnnotationRenderer.render(original: model.original, document: document)
                image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
                renderDocument = document
            } catch { model.errorMessage = error.localizedDescription }
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: model.tool == .select ? .arrow : .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        image?.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let crop = model.cropPreview {
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: viewRect(crop.cgRect))
            path.lineWidth = 2; path.setLineDash([6, 4], count: 2, phase: 0); path.stroke()
        }
        if model.tool == .select, let annotation = model.preview ?? model.selected {
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: viewRect(AnnotationRenderer.bounds(of: annotation)))
            path.lineWidth = 1.5; path.stroke()
            if let handle = resizeHandle(annotation) {
                NSColor.systemBlue.setFill(); NSBezierPath(rect: handle).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        let point = imagePoint(event)
        start = point
        if model.tool == .select {
            if let selected = model.selected, let handle = resizeHandle(selected),
               handle.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) {
                resizing = selected; return
            }
            let annotation = model.history.document.annotations.reversed().first { AnnotationRenderer.bounds(of: $0).contains(point.cgPoint) }
            model.selectedID = annotation?.id
            if event.clickCount == 2, let annotation, [.text, .speechBubble].contains(annotation.tool) {
                model.requestText(at: point, replacing: annotation); start = nil; return
            }
            moving = annotation
        } else if model.tool.isArea || model.tool.isStroke || [.arrow, .line].contains(model.tool) {
            draft = model.draft(tool: model.tool, at: point)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = imagePoint(event)
        if var resizing, let first = resizing.points.first, let last = resizing.points.last {
            resizing.points = [Point(x: min(first.x, last.x), y: min(first.y, last.y)), point]
            model.preview = resizing
        } else if var moving {
            moving.translate(x: point.x - start.x, y: point.y - start.y)
            model.preview = moving
        } else if model.tool == .crop { model.cropPreview = Rect(from: start, to: point) }
        else if var draft {
            if draft.tool.isStroke { draft.points.append(point) }
            else { draft.points = [start, point] }
            self.draft = draft
            model.preview = draft
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let point = imagePoint(event)
        if model.tool == .text { model.requestText(at: point) }
        else if model.tool == .step { model.addStep(at: point) }
        else if model.tool == .image { model.addImage(at: point) }
        else if model.tool == .sticker { model.addSticker(at: point) }
        else if model.tool == .cursor { model.addCursor(at: point) }
        else if model.tool == .crop { model.crop(Rect(from: start, to: point)) }
        else if moving != nil || resizing != nil {
            if let preview = model.preview { model.commit(preview) }
        } else if var draft {
            if draft.tool.isStroke { draft.points.append(point) } else { draft.points = [start, point] }
            if hypot(point.x - start.x, point.y - start.y) > 2 || draft.tool.isStroke {
                if draft.tool == .speechBubble { model.completeBubble(draft) }
                else { model.commit(draft) }
            }
        }
        self.start = nil; moving = nil; resizing = nil; draft = nil
        model.preview = nil; model.cropPreview = nil
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { model.deleteSelected() }
        else if event.keyCode == 53 { start = nil; moving = nil; resizing = nil; draft = nil; model.preview = nil; model.cropPreview = nil; model.selectedID = nil }
        else { super.keyDown(with: event) }
    }
    private func resizeHandle(_ annotation: Annotation) -> CGRect? {
        guard annotation.tool.isArea || annotation.tool == .image,
              let first = annotation.points.first, let last = annotation.points.last else { return nil }
        let area = viewRect(Rect(from: first, to: last).cgRect)
        return CGRect(x: area.maxX - 4, y: area.maxY - 4, width: 8, height: 8)
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            model.zoom = min(3, max(0.3, model.zoom + event.scrollingDeltaY * 0.01))
        } else {
            model.pan.width += event.scrollingDeltaX
            model.pan.height += event.scrollingDeltaY
        }
    }
}
