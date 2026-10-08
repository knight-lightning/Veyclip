import Foundation

/// Packed top-left RGBA bytes, independent of AppKit and display scaling.
public struct ScrollFrame: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]
    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }
    public var isValid: Bool { width > 0 && height > 0 && bytes.count == width * height * 4 }
}

public enum ScrollMatch: Equatable, Sendable { case unchanged, offset(Int), noMatch }

public enum ScrollMatcher {
    public static func match(previous: ScrollFrame, next: ScrollFrame) -> ScrollMatch {
        guard previous.isValid, next.isValid, previous.width == next.width, previous.height == next.height,
              previous.height >= 64 else { return .noMatch }
        let width = previous.width, height = previous.height
        func error(at shift: Int) -> Double {
            var failures = 0, total = 0
            let overlap = height - shift
            for y in stride(from: 2, to: overlap - 2, by: max(1, overlap / 64)) {
                for x in stride(from: 2, to: width - 2, by: max(1, width / 32)) {
                    let a = ((y + shift) * width + x) * 4, b = (y * width + x) * 4
                    for channel in 0..<3 {
                        if abs(Int(previous.bytes[a + channel]) - Int(next.bytes[b + channel])) > 6 { failures += 1 }
                        total += 1
                    }
                }
            }
            return total == 0 ? 1 : Double(failures) / Double(total)
        }
        if error(at: 0) < 0.005 { return .unchanged }
        let maximum = height - max(32, height / 5)
        guard maximum >= 4 else { return .noMatch }
        let candidates = (1...maximum).map { ($0, error(at: $0)) }
        guard let best = candidates.min(by: { $0.1 < $1.1 }), best.1 < 0.025 else { return .noMatch }
        // Repeated patterns and mostly blank pages must not create an arbitrary seam.
        let alternative = candidates.filter { abs($0.0 - best.0) > 12 }.map(\.1).min() ?? 1
        guard alternative - best.1 > 0.03 else { return .noMatch }
        return .offset(best.0)
    }
}
