import AppKit
import ImageIO
import CaptureCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    let original: CGImage
    let item: CaptureItem
    let library: CaptureLibrary
    @Published var history: EditHistory
    private var toolColors = ToolColors()
    @Published var tool: Tool = .arrow {
        didSet { if tool != oldValue { color = toolColors[tool] } }
    }
    @Published var color = InkColor.palette[0] {
        didSet { toolColors[tool] = color }
    }
    @Published var filled = false
    @Published var effectAmount = 16.0
    @Published var magnification = 2.0
    @Published var thickness = 4.0
    @Published var textSize = 28.0
    @Published var preview: Annotation?
    @Published var cropPreview: Rect?
    @Published var selectedID: UUID?
    @Published var zoom = 1.0
    @Published var pan = CGSize.zero
    @Published var message = "Edits preserve your original screenshot"
    @Published var errorMessage: String?

    init(item: CaptureItem, library: CaptureLibrary) throws {
        self.item = item; self.library = library
        original = try ImageFiles.load(library.url(for: item))
        history = EditHistory(document: try library.loadDocument(for: item))
    }
    var imageBounds: Rect { Rect(x: 0, y: 0, width: Double(original.width), height: Double(original.height)) }
    var visibleRect: Rect { history.document.crop ?? imageBounds }
    var selected: Annotation? { history.document.annotations.first { $0.id == selectedID } }
    var effectiveDocument: EditorDocument {
        var document = history.document
        if let preview {
            if let index = document.annotations.firstIndex(where: { $0.id == preview.id }) { document.annotations[index] = preview }
            else { document.annotations.append(preview) }
        }
        return document
    }
    func commit(_ annotation: Annotation) {
        var document = history.document
        document.version = 2
        if let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) { document.annotations[index] = annotation }
        else { document.annotations.append(annotation) }
        history.commit(document)
        selectedID = annotation.id
        preview = nil
        persist()
    }
    func crop(_ rect: Rect) {
        guard let clipped = imageBounds.intersection(rect), clipped.width >= 4, clipped.height >= 4 else { return }
        var document = history.document
        document.crop = Rect(clipped.cgRect.integral)
        history.commit(document)
        cropPreview = nil
        persist()
    }
    func resetCrop() {
        var document = history.document
        document.crop = nil
        history.commit(document)
        persist()
    }
    func undo() { history.undo(); preview = nil; cropPreview = nil; selectedID = nil; persist() }
    func redo() { history.redo(); preview = nil; cropPreview = nil; selectedID = nil; persist() }
    func deleteSelected() {
        guard let selectedID else { return }
        var document = history.document
        document.annotations.removeAll { $0.id == selectedID }
        history.commit(document)
        self.selectedID = nil
        persist()
    }
    func applyStyle() {
        guard var annotation = selected else { return }
        annotation.color = color; annotation.thickness = thickness; annotation.textSize = textSize
        annotation.filled = filled
        annotation.effectAmount = annotation.tool == .magnify ? magnification : effectAmount
        commit(annotation)
    }
    func draft(tool: Tool, at point: Point) -> Annotation {
        Annotation(tool: tool, points: [point, point], color: color, thickness: thickness,
                   textSize: textSize, filled: filled, effectAmount: tool == .magnify ? magnification : effectAmount)
    }
    func addStep(at point: Point) {
        let next = (history.document.annotations.compactMap(\.number).max() ?? 0) + 1
        commit(Annotation(tool: .step, points: [point], color: color, textSize: textSize, number: next))
    }
    func addCursor(at point: Point) {
        commit(Annotation(tool: .cursor, points: [point], color: color, textSize: max(30, textSize * 1.5)))
    }
    func addSticker(at point: Point) {
        let alert = NSAlert()
        alert.messageText = "Choose a sticker"
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        picker.addItems(withTitles: ["🙂", "🔥", "✅", "❌", "⭐️", "❤️", "💡", "👀", "🎯", "👍"])
        alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn, let sticker = picker.titleOfSelectedItem else { return }
        commit(Annotation(tool: .sticker, points: [point], color: color, text: sticker, textSize: max(48, textSize * 2)))
    }
    func addImage(at point: Point) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let image = try ImageFiles.load(url)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.message("Couldn't insert the image.") }
            let width = min(Double(image.width), visibleRect.width * 0.4)
            let height = width * Double(image.height) / Double(image.width)
            commit(Annotation(tool: .image, points: [point, Point(x: point.x + width, y: point.y + height)], color: color, imageData: data))
        } catch { errorMessage = error.localizedDescription }
    }
    func completeBubble(_ annotation: Annotation) {
        requestText(at: annotation.points[0], replacing: annotation)
    }
    func persist() {
        do { try library.saveDocument(history.document, for: item); message = "Edits saved · original preserved" }
        catch { errorMessage = error.localizedDescription }
    }
    func copy() {
        do {
            ImageFiles.copy(try AnnotationRenderer.render(original: original, document: history.document))
            message = "Copied edited screenshot"
        } catch { errorMessage = error.localizedDescription }
    }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = library.url(for: item).deletingPathExtension().lastPathComponent + "_edited.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep the source image immutable even if selected in the export dialog.
        guard url.standardizedFileURL != library.url(for: item).standardizedFileURL else {
            errorMessage = "Choose another filename to preserve the original screenshot."; return
        }
        do {
            let image = try AnnotationRenderer.render(original: original, document: history.document)
            if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    throw CaptureError.message("Couldn't encode the JPEG.")
                }
                try data.write(to: url, options: .atomic)
            } else { try ImageFiles.writePNG(image, to: url) }
            message = "Saved \(url.lastPathComponent)"
        } catch { errorMessage = error.localizedDescription }
    }
    func requestText(at point: Point, replacing: Annotation? = nil) {
        let alert = NSAlert()
        alert.messageText = replacing == nil ? "Add text" : "Edit text"
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 70))
        input.stringValue = replacing?.text ?? ""
        input.placeholderString = "Type your annotation"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
        if var replacing { replacing.text = input.stringValue; commit(replacing) }
        else { commit(Annotation(tool: .text, points: [point], color: color, thickness: thickness, text: input.stringValue, textSize: textSize)) }
    }
}
