import AppKit
import ImageIO
import CaptureCore

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
extension Point {
    init(_ point: CGPoint) { self.init(x: point.x, y: point.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
extension InkColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var cgColor: CGColor { nsColor.cgColor }
}

enum ImageFiles {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CaptureError.message("Couldn't encode the screenshot.")
        }
        try data.write(to: url, options: .atomic)
    }
    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureError.message("Couldn't open \(url.lastPathComponent). The file may have moved.")
        }
        return image
    }
    static func copy(_ image: CGImage) {
        let image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
