import AppKit
import XCTest
import CaptureCore
@testable import ShareXMac

final class AnnotationRendererTests: XCTestCase {
    private func fixture(size: Int = 4) throws -> CGImage {
        var pixels: [UInt8] = []
        for y in 0..<size {
            for x in 0..<size { pixels.append(contentsOf: [UInt8(truncatingIfNeeded: x * 50), UInt8(truncatingIfNeeded: y * 60), 40, 255]) }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        let index = y * image.bytesPerRow + x * 4
        return Array(bytes[index..<(index + 4)])
    }
    func testUneditedExportKeepsImageOrientation() async throws {
        let image = try fixture()
        let rendered = try await MainActor.run { try AnnotationRenderer.render(original: image, document: EditorDocument()) }
        for y in 0..<4 {
            for x in 0..<4 { XCTAssertEqual(try pixel(rendered, x: x, y: y), try pixel(image, x: x, y: y)) }
        }
    }
    func testCropUsesOriginalTopLeftPixelCoordinates() async throws {
        let image = try fixture()
        var document = EditorDocument()
        document.crop = Rect(x: 1, y: 0, width: 2, height: 2)
        let rendered = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        XCTAssertEqual(rendered.width, 2); XCTAssertEqual(rendered.height, 2)
        for y in 0..<2 {
            for x in 0..<2 { XCTAssertEqual(try pixel(rendered, x: x, y: y), try pixel(image, x: x + 1, y: y)) }
        }
    }
    func testHighlightStaysAlignedAfterCropping() async throws {
        let image = try fixture()
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .highlight, points: [Point(x: 2, y: 1), Point(x: 4, y: 3)], color: .highlightYellow)]
        let full = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        document.crop = Rect(x: 1, y: 1, width: 3, height: 2)
        let cropped = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        XCTAssertEqual(try pixel(cropped, x: 1, y: 0), try pixel(full, x: 2, y: 1))
        XCTAssertNotEqual(try pixel(cropped, x: 1, y: 0), try pixel(image, x: 2, y: 1))
    }
    func testYellowHighlightCapsBlueWithoutLighteningText() async throws {
        let image = try fixture()
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .highlight, points: [Point(x: 0, y: 0), Point(x: 4, y: 4)], color: .highlightYellow)]
        let once = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        document.annotations.append(document.annotations[0])
        let twice = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        for y in 0..<4 {
            for x in 0..<4 {
                let source = try pixel(image, x: x, y: y)
                XCTAssertEqual(try pixel(once, x: x, y: y), [source[0], source[1], 0, 255])
                XCTAssertEqual(try pixel(twice, x: x, y: y), try pixel(once, x: x, y: y))
            }
        }
    }
    func testFilledRectangleAndEraserRestoreSourcePixels() async throws {
        let image = try fixture()
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .rectangle, points: [Point(x: 0, y: 0), Point(x: 4, y: 4)],
                                           color: .highlightYellow, filled: true)]
        let filled = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        XCTAssertEqual(try pixel(filled, x: 2, y: 2), [255, 255, 0, 255])
        document.annotations.append(Annotation(tool: .eraser, points: [Point(x: 2, y: 2), Point(x: 2, y: 2)],
                                                color: .highlightYellow, thickness: 20))
        let erased = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        for y in 0..<4 { for x in 0..<4 { XCTAssertEqual(try pixel(erased, x: x, y: y), try pixel(image, x: x, y: y)) } }
    }
    func testEmbeddedImageKeepsTopLeftOrientation() async throws {
        let image = try fixture()
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .image, points: [Point(x: 0, y: 0), Point(x: 4, y: 4)],
                                           color: .highlightYellow, imageData: png)]
        let rendered = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
        for y in 0..<4 { for x in 0..<4 { XCTAssertEqual(try pixel(rendered, x: x, y: y), try pixel(image, x: x, y: y)) } }
    }
    func testEffectsChangeSelectedRegionAndStayAlignedAfterCrop() async throws {
        let image = try fixture(size: 64)
        for tool in [Tool.blur, .pixelate, .magnify] {
            var document = EditorDocument()
            document.annotations = [Annotation(tool: tool, points: [Point(x: 16, y: 16), Point(x: 40, y: 40)],
                                               color: .highlightYellow, effectAmount: tool == .pixelate ? 4 : 2)]
            let full = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
            document.crop = Rect(x: 8, y: 8, width: 48, height: 48)
            let crop = try await MainActor.run { try AnnotationRenderer.render(original: image, document: document) }
            XCTAssertEqual(try pixel(full, x: 24, y: 24), try pixel(crop, x: 16, y: 16), tool.rawValue)
            XCTAssertEqual(try pixel(full, x: 4, y: 4), try pixel(image, x: 4, y: 4), tool.rawValue)
            var changed = false
            for y in 20..<32 { for x in 20..<32 {
                if try pixel(full, x: x, y: y) != pixel(image, x: x, y: y) { changed = true }
            } }
            XCTAssertTrue(changed, tool.rawValue)
        }
    }
}
