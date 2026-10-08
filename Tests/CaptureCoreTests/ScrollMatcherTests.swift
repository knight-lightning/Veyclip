import XCTest
@testable import CaptureCore

final class ScrollMatcherTests: XCTestCase {
    private func frame(start: Int, uniform: Bool = false) -> ScrollFrame {
        var bytes: [UInt8] = []
        for y in start..<(start + 128) {
            for x in 0..<96 {
                bytes.append(contentsOf: uniform ? [255, 255, 255, 255] :
                    [UInt8((y * 37 + x * 19) % 256), UInt8((y * 13 + x * 71) % 256), UInt8((y * 91 + x * 7) % 256), 255])
            }
        }
        return ScrollFrame(width: 96, height: 128, bytes: bytes)
    }
    func testFindsScrollingOverlapAtExactPixelOffset() {
        XCTAssertEqual(ScrollMatcher.match(previous: frame(start: 0), next: frame(start: 51)), .offset(51))
    }
    func testUnchangedPageStopsInsteadOfAddingDuplicateContent() {
        XCTAssertEqual(ScrollMatcher.match(previous: frame(start: 0), next: frame(start: 0)), .unchanged)
        XCTAssertEqual(ScrollMatcher.match(previous: frame(start: 0, uniform: true), next: frame(start: 0, uniform: true)), .unchanged)
    }
    func testUnrelatedOrMalformedFramesAreRejected() {
        XCTAssertEqual(ScrollMatcher.match(previous: frame(start: 0), next: frame(start: 0, uniform: true)), .noMatch)
        XCTAssertEqual(ScrollMatcher.match(previous: frame(start: 0), next: ScrollFrame(width: 96, height: 128, bytes: [])), .noMatch)
    }
}
