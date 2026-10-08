import AppKit
import ApplicationServices
import CaptureCore

@MainActor
enum ScrollingCapture {
    struct Result { let image: CGImage; let reachedLimit: Bool }

    static func requestAccess() throws {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw CaptureError.message("Scrolling capture needs Accessibility access to scroll the selected app. Enable ShareX Mac in System Settings → Privacy & Security → Accessibility, then try again.")
        }
    }

    static func run(source: CaptureSource, service: CaptureService, recovery: URL,
                    progress: (Int) -> Void) async throws -> Result {
        guard let region = source.region else { throw CaptureError.message("Select the scrollable content area first.") }
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        var frames: [(CGImage, Int)] = []
        var previous: ScrollFrame?
        var totalHeight = 0
        let location = CGPoint(x: source.displayFrame.minX + region.x + region.width / 2,
                               y: source.displayFrame.minY + region.y + region.height / 2)
        let previousLocation = CGEvent(source: nil)?.location
        CGWarpMouseCursorPosition(location)
        defer { if let previousLocation { CGWarpMouseCursorPosition(previousLocation) } }
        for index in 0..<20 {
            try Task.checkCancellation()
            let image = try await service.screenshot(source: source, cursor: false)
            try ImageFiles.writePNG(image, to: recovery.appendingPathComponent("frame-\(index + 1).png"))
            let current = try normalized(image)
            var offset = 0
            if let previous {
                let match = await Task.detached { ScrollMatcher.match(previous: previous, next: current) }.value
                try Task.checkCancellation()
                switch match {
                case .unchanged: return Result(image: try stitch(frames), reachedLimit: false)
                case .offset(let amount): offset = amount
                case .noMatch:
                    throw CaptureError.message("Couldn't align the scrolling frames. Select only moving content, excluding fixed headers and sidebars. Captured frames are preserved at \(recovery.path).")
                }
            }
            let addition = frames.isEmpty ? image.height : offset
            guard Double(image.width) * Double(totalHeight + addition) <= 50_000_000 else {
                throw CaptureError.message("The scrolling image reached its size limit. Captured frames are preserved at \(recovery.path).")
            }
            frames.append((image, offset)); totalHeight += addition
            previous = current
            progress(frames.count)
            if index == 19 { return Result(image: try stitch(frames), reachedLimit: true) }
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: -Int32(region.height * 0.65), wheel2: 0, wheel3: 0) else {
                throw CaptureError.message("Couldn't send a scroll event. Captured frames are preserved at \(recovery.path).")
            }
            event.location = location
            // Route to the window under the region without activating the capture UI.
            event.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(700))
        }
        throw CaptureError.message("No scrolling frames were captured.")
    }

    private static func normalized(_ image: CGImage) throws -> ScrollFrame {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CaptureError.message("Couldn't read the scrolling frame.") }
        return ScrollFrame(width: width, height: height, bytes: bytes)
    }

    private static func stitch(_ frames: [(CGImage, Int)]) throws -> CGImage {
        guard let first = frames.first else { throw CaptureError.message("No frames to combine.") }
        let height = first.0.height + frames.dropFirst().reduce(0) { $0 + $1.1 }
        guard let context = CGContext(data: nil, width: first.0.width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.message("Couldn't prepare the scrolling image.")
        }
        var top = 0
        for (index, frame) in frames.enumerated() {
            let amount = index == 0 ? frame.0.height : frame.1
            guard let tail = frame.0.cropping(to: CGRect(x: 0, y: frame.0.height - amount, width: frame.0.width, height: amount)) else {
                throw CaptureError.message("Couldn't crop the scrolling seam.")
            }
            context.draw(tail, in: CGRect(x: 0, y: height - top - amount, width: tail.width, height: amount))
            top += amount
        }
        guard let image = context.makeImage() else { throw CaptureError.message("Couldn't combine the scrolling frames.") }
        return image
    }
}
