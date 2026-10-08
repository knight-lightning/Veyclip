import Foundation

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(from a: Point, to b: Point) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width >= 1 && height >= 1
    }
    public func intersection(_ other: Rect) -> Rect? {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(x + width, other.x + other.width)
        let bottom = min(y + height, other.y + other.height)
        let result = Rect(x: left, y: top, width: right - left, height: bottom - top)
        return result.isValid ? result : nil
    }
    /// Local AppKit coordinates have a bottom-left origin. Capture coordinates are top-left.
    public static func captureRegion(local: Rect, displayHeight: Double) -> Rect {
        Rect(x: local.x, y: displayHeight - local.y - local.height, width: local.width, height: local.height)
    }
    public func pixels(scale: Double, even: Bool = false) -> (width: Int, height: Int) {
        func dimension(_ value: Double) -> Int {
            let pixels = max(1, Int((value * scale).rounded()))
            return even ? max(2, pixels - pixels % 2) : pixels
        }
        return (dimension(width), dimension(height))
    }
}
