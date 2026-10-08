import Foundation

public enum Tool: String, CaseIterable, Codable, Hashable, Sendable {
    case select, rectangle, ellipse, line, arrow, freehand, text, speechBubble, step
    case image, sticker, cursor, highlight, eraser, blur, pixelate, magnify, crop
    public var title: String {
        switch self {
        case .speechBubble: return "Speech bubble"
        case .step: return "Numbered step"
        case .image: return "Insert image"
        case .sticker: return "Sticker"
        case .cursor: return "Insert cursor"
        default: return rawValue.capitalized
        }
    }
    public var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .speechBubble: return "text.bubble"
        case .step: return "number.circle"
        case .image: return "photo"
        case .sticker: return "face.smiling"
        case .cursor: return "cursorarrow.rays"
        case .eraser: return "eraser"
        case .blur: return "drop"
        case .pixelate: return "square.grid.3x3"
        case .magnify: return "magnifyingglass"
        case .text: return "textformat"
        case .crop: return "crop"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .freehand: return "pencil.tip"
        }
    }
    public var isStroke: Bool { self == .freehand || self == .eraser }
    public var isArea: Bool { [.rectangle, .ellipse, .speechBubble, .highlight, .blur, .pixelate, .magnify].contains(self) }
    public var usesColor: Bool { ![.select, .crop, .image, .sticker, .cursor, .eraser, .blur, .pixelate, .magnify].contains(self) }
    public var defaultColor: InkColor { self == .highlight ? .highlightYellow : InkColor.palette[0] }
}

public struct InkColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    public static let highlightYellow = InkColor(red: 1, green: 1, blue: 0)
    public static let palette: [InkColor] = [
        .init(red: 1, green: 0.28, blue: 0.32), .highlightYellow,
        .init(red: 0.24, green: 0.82, blue: 0.53), .init(red: 0.25, green: 0.6, blue: 1),
        .init(red: 0.7, green: 0.48, blue: 1), .init(red: 1, green: 1, blue: 1)
    ]
}

public struct ToolColors: Sendable {
    private var values: [Tool: InkColor] = [:]
    public init() {}
    public subscript(tool: Tool) -> InkColor {
        get { values[tool] ?? tool.defaultColor }
        set { values[tool] = newValue }
    }
}

public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var tool: Tool
    public var points: [Point]
    public var color: InkColor
    public var thickness: Double
    public var text: String
    public var textSize: Double
    public var number: Int?
    public var imageData: Data?
    public var filled: Bool?
    public var effectAmount: Double?
    public init(tool: Tool, points: [Point], color: InkColor, thickness: Double = 4,
                text: String = "", textSize: Double = 28, id: UUID = UUID(), number: Int? = nil,
                imageData: Data? = nil, filled: Bool? = nil, effectAmount: Double? = nil) {
        self.id = id; self.tool = tool; self.points = points; self.color = color
        self.thickness = thickness; self.text = text; self.textSize = textSize
        self.number = number; self.imageData = imageData; self.filled = filled; self.effectAmount = effectAmount
    }
    public mutating func translate(x: Double, y: Double) {
        points = points.map { Point(x: $0.x + x, y: $0.y + y) }
    }
}

public struct EditorDocument: Codable, Equatable, Sendable {
    public var version: Int = 2
    public var annotations: [Annotation] = []
    public var crop: Rect?
    public init() {}
}

public struct EditHistory: Sendable {
    public private(set) var document: EditorDocument
    private var past: [EditorDocument] = []
    private var future: [EditorDocument] = []
    public init(document: EditorDocument = EditorDocument()) { self.document = document }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func commit(_ next: EditorDocument) {
        guard next != document else { return }
        past.append(document)
        if past.count > 100 { past.removeFirst() }
        document = next; future.removeAll()
    }
    public mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(document); document = previous
    }
    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(document); document = next
    }
}
