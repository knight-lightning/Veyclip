import AppKit
import AVFoundation
import CaptureCore
import ImageIO

struct CaptureItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case screenshot, video, gif }
    let id: UUID
    let kind: Kind
    let date: Date
    let filename: String
    let filePath: String?
    var thumbnailName: String { "\(id.uuidString).png" }
}

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    let root: URL
    var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    var documents: URL { root.appendingPathComponent("Edits", isDirectory: true) }
    var media: URL { root.appendingPathComponent("Captures", isDirectory: true) }
    var temporary: URL { root.appendingPathComponent("InProgress", isDirectory: true) }
    private var index: URL { root.appendingPathComponent("history.json") }
    private let manager = FileManager.default
    var outputFolder: URL {
        if let path = UserDefaults.standard.string(forKey: "outputFolder") { return URL(fileURLWithPath: path, isDirectory: true) }
        return media
    }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShareXMac", isDirectory: true)
    }
    func load() throws {
        for directory in [root, thumbnails, documents, media, temporary] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if manager.fileExists(atPath: index.path) {
            // Leave unreadable history intact: don't replace it with an empty index.
            items = try JSONDecoder().decode([CaptureItem].self, from: Data(contentsOf: index))
        }
    }
    func url(for item: CaptureItem) -> URL {
        item.filePath.map { URL(fileURLWithPath: $0) } ?? media.appendingPathComponent(item.filename)
    }
    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolder
        panel.prompt = "Choose Captures Folder"
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        UserDefaults.standard.set(selected.path, forKey: "outputFolder")
        objectWillChange.send()
    }
    func editURL(for item: CaptureItem) -> URL { documents.appendingPathComponent("\(item.id.uuidString).json") }
    func thumbnail(for item: CaptureItem) -> NSImage? {
        NSImage(contentsOf: thumbnails.appendingPathComponent(item.thumbnailName))
    }
    func save(_ image: CGImage) throws -> CaptureItem {
        try manager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let item = newItem(kind: .screenshot)
        try ImageFiles.writePNG(image, to: url(for: item))
        try add(item, thumbnail: image)
        return item
    }
    func recordingURL() -> URL { temporary.appendingPathComponent("\(UUID().uuidString).mp4") }
    func importRecording(_ recording: URL) async throws -> CaptureItem {
        try manager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let item = newItem(kind: .video)
        try manager.moveItem(at: recording, to: url(for: item))
        var frame: CGImage?
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url(for: item)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)
        if let generated = try? await generator.image(at: .zero) { frame = generated.image }
        try add(item, thumbnail: frame)
        return item
    }
    func saveDocument(_ document: EditorDocument, for item: CaptureItem) throws {
        try JSONEncoder().encode(document).write(to: editURL(for: item), options: .atomic)
    }
    func importGIF(_ gif: URL) throws -> CaptureItem {
        try manager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let item = newItem(kind: .gif)
        try manager.moveItem(at: gif, to: url(for: item))
        let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil)
        let image = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        try add(item, thumbnail: image)
        return item
    }
    func loadDocument(for item: CaptureItem) throws -> EditorDocument {
        let url = editURL(for: item)
        if !manager.fileExists(atPath: url.path) { return EditorDocument() }
        let document = try JSONDecoder().decode(EditorDocument.self, from: Data(contentsOf: url))
        guard (1...2).contains(document.version) else { throw CaptureError.message("This edit was created by a newer app version.") }
        return document
    }
    func removeFromHistory(_ item: CaptureItem) throws {
        let next = items.filter { $0.id != item.id }
        try persist(next)
        items = next
    }
    func trash(_ item: CaptureItem) throws {
        if manager.fileExists(atPath: url(for: item).path) {
            try manager.trashItem(at: url(for: item), resultingItemURL: nil)
        }
        try removeFromHistory(item)
    }
    private func newItem(kind: CaptureItem.Kind) -> CaptureItem {
        let id = UUID()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let date = Date()
        let ext = kind == .screenshot ? "png" : (kind == .gif ? "gif" : "mp4")
        let filename = "ShareX_\(formatter.string(from: date))_\(id.uuidString.prefix(8)).\(ext)"
        return CaptureItem(id: id, kind: kind, date: date, filename: filename,
                           filePath: outputFolder.appendingPathComponent(filename).path)
    }
    private func persist(_ next: [CaptureItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: index, options: .atomic)
    }
    private func add(_ item: CaptureItem, thumbnail: CGImage?) throws {
        if let thumbnail {
            let scale = min(1, 640 / Double(thumbnail.width))
            let size = CGSize(width: max(1, Double(thumbnail.width) * scale), height: max(1, Double(thumbnail.height) * scale))
            if let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(thumbnail, in: CGRect(origin: .zero, size: size))
                if let reduced = context.makeImage() {
                    try ImageFiles.writePNG(reduced, to: thumbnails.appendingPathComponent(item.thumbnailName))
                }
            }
        }
        let next = [item] + items
        try persist(next)
        items = next
    }
}
