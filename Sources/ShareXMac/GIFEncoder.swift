import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum GIFEncoder {
    static func encode(movie: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CaptureError.message("The recording has no frames to convert.") }
        let fps = 10.0
        let count = max(1, Int(ceil(min(duration, 60) * fps)))
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CaptureError.message("Couldn't create the GIF file. The original recording is kept in InProgress.")
        }
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps,
                                                        kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary
        for index in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: min(Double(index) / fps, max(0, duration - 0.01)), preferredTimescale: 600)
            let frame = try await generator.image(at: time)
            CGImageDestinationAddImage(output, frame.image, properties)
        }
        guard CGImageDestinationFinalize(output) else {
            throw CaptureError.message("Couldn't finish the GIF. The original recording is kept in InProgress.")
        }
    }
}
