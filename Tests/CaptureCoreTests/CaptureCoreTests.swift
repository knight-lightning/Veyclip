import XCTest
@testable import CaptureCore

final class CaptureCoreTests: XCTestCase {
    func testHighlightAndDrawingColorsAreRememberedSeparately() {
        var colors = ToolColors()
        XCTAssertEqual(colors[.highlight], .highlightYellow)
        let arrow = colors[.arrow]
        colors[.highlight] = InkColor.palette[2]
        XCTAssertEqual(colors[.arrow], arrow)
        colors[.arrow] = InkColor.palette[3]
        XCTAssertEqual(colors[.highlight], InkColor.palette[2])
    }
    func testVersionOneDocumentsDecodeWithoutNewAnnotationFields() throws {
        var document = EditorDocument()
        document.version = 1
        document.annotations = [Annotation(tool: .text, points: [Point(x: 1, y: 2)], color: .highlightYellow, text: "Legacy")]
        let decoded = try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertNil(decoded.annotations[0].number)
        XCTAssertNil(decoded.annotations[0].imageData)
        XCTAssertNil(decoded.annotations[0].filled)
    }
    func testNewAnnotationPayloadsSurviveUndoAndPersistence() throws {
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .step, points: [Point(x: 20, y: 30)], color: .highlightYellow, number: 4),
                                Annotation(tool: .image, points: [Point(x: 0, y: 0), Point(x: 40, y: 40)],
                                           color: .highlightYellow, imageData: Data([1, 2, 3]))]
        var history = EditHistory()
        history.commit(document); history.undo(); history.redo()
        XCTAssertEqual(history.document, document)
        XCTAssertEqual(try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(document)), document)
    }
    func testSelectionDraggedBackwards() {
        XCTAssertEqual(Rect(from: Point(x: 180, y: 120), to: Point(x: 20, y: 30)),
                       Rect(x: 20, y: 30, width: 160, height: 90))
    }
    func testBottomLeftSelectionConvertsToTopLeft() {
        let region = Rect(x: 40, y: 100, width: 200, height: 300)
        XCTAssertEqual(Rect.captureRegion(local: region, displayHeight: 900),
                       Rect(x: 40, y: 500, width: 200, height: 300))
    }
    func testRetinaDimensionsAndEvenVideoDimensions() {
        let region = Rect(x: 0, y: 0, width: 101, height: 53)
        XCTAssertEqual(region.pixels(scale: 2).width, 202)
        XCTAssertEqual(region.pixels(scale: 2).height, 106)
        XCTAssertEqual(region.pixels(scale: 1, even: true).width, 100)
        XCTAssertEqual(region.pixels(scale: 1, even: true).height, 52)
    }
    func testCropCannotExtendBeyondImageOrBecomeEmpty() {
        let image = Rect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(image.intersection(Rect(x: -20, y: 20, width: 200, height: 700)),
                       Rect(x: 0, y: 20, width: 180, height: 580))
        XCTAssertNil(image.intersection(Rect(x: 900, y: 0, width: 100, height: 100)))
        XCTAssertFalse(Rect(x: .nan, y: 0, width: 5, height: 5).isValid)
    }
    func testNewEditAfterUndoDropsRedoBranch() {
        var history = EditHistory()
        var first = history.document
        first.crop = Rect(x: 10, y: 20, width: 100, height: 90)
        history.commit(first)
        history.undo()
        XCTAssertTrue(history.canRedo)
        var second = history.document
        second.annotations.append(Annotation(tool: .text, points: [Point(x: 40, y: 60)],
                                             color: InkColor.palette[0], text: "Пример"))
        history.commit(second)
        XCTAssertFalse(history.canRedo)
        history.undo(); history.redo()
        XCTAssertEqual(history.document, second)
    }
    func testCropDoesNotRewriteOriginalAnnotationCoordinates() throws {
        var document = EditorDocument()
        document.annotations = [Annotation(tool: .arrow, points: [Point(x: 20, y: 30), Point(x: 90, y: 100)],
                                            color: InkColor.palette[3])]
        document.crop = Rect(x: 10, y: 20, width: 100, height: 100)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(EditorDocument.self, from: data), document)
        XCTAssertEqual(document.annotations[0].points[0], Point(x: 20, y: 30))
    }
}
