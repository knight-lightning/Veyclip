import AppKit
import CoreText
import CoreImage
import ImageIO
import CaptureCore

@MainActor
enum AnnotationRenderer {
    private static let effects = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    static func render(original: CGImage, document: EditorDocument) throws -> CGImage {
        let full = Rect(x: 0, y: 0, width: Double(original.width), height: Double(original.height))
        let crop: Rect
        if let requested = document.crop {
            guard let clipped = full.intersection(requested) else { throw CaptureError.message("The crop is outside the image.") }
            crop = clipped
        } else { crop = full }
        // Effects sample pixels outside their output rectangle. Render them before
        // cropping so a crop never shifts the pixelation grid or magnifier center.
        if document.crop != nil, document.annotations.contains(where: { [.blur, .pixelate, .magnify].contains($0.tool) }) {
            var uncropped = document
            uncropped.crop = nil
            let rendered = try render(original: original, document: uncropped)
            guard let result = rendered.cropping(to: crop.cgRect.integral) else {
                throw CaptureError.message("Couldn't crop the edited image.")
            }
            return result
        }
        let width = max(1, Int(crop.width.rounded())), height = max(1, Int(crop.height.rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.message("Couldn't prepare the image for export.")
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -crop.x, y: -crop.y)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(original.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
        context.restoreGState()
        for annotation in document.annotations { try draw(annotation, context: context, original: original, crop: crop) }
        guard let image = context.makeImage() else { throw CaptureError.message("Couldn't render the image.") }
        return image
    }

    private static func draw(_ annotation: Annotation, context: CGContext, original: CGImage, crop: Rect) throws {
        guard let first = annotation.points.first else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.thickness)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.tool {
        case .text, .sticker:
            for (index, line) in annotation.text.components(separatedBy: "\n").enumerated() {
                context.saveGState()
                context.translateBy(x: first.x, y: first.y + annotation.textSize + Double(index) * annotation.textSize * 1.25)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                context.textPosition = .zero
                let text = NSAttributedString(string: line, attributes: [
                    .font: NSFont.systemFont(ofSize: annotation.textSize, weight: .semibold),
                    .foregroundColor: annotation.color.nsColor
                ])
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
                context.restoreGState()
            }
        case .highlight:
            guard let last = annotation.points.last else { return }
            // ShareX caps each channel at the highlight color: min(source, destination).
            context.setBlendMode(.darken)
            context.setAlpha(1)
            context.fill(Rect(from: first, to: last).cgRect)
        case .rectangle, .ellipse:
            guard let last = annotation.points.last else { return }
            let rect = Rect(from: first, to: last).cgRect
            if annotation.tool == .ellipse {
                if annotation.filled == true { context.fillEllipse(in: rect) } else { context.strokeEllipse(in: rect) }
            } else {
                if annotation.filled == true { context.fill(rect) } else { context.stroke(rect) }
            }
        case .speechBubble:
            guard let last = annotation.points.last else { return }
            let rect = Rect(from: first, to: last).cgRect
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            context.beginPath()
            context.move(to: CGPoint(x: rect.midX - 8, y: rect.maxY - 1))
            context.addLine(to: CGPoint(x: rect.midX + 10, y: rect.maxY - 1))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + min(24, rect.height * 0.25)))
            context.closePath(); context.fillPath()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let string = NSAttributedString(string: annotation.text, attributes: [
                .font: NSFont.systemFont(ofSize: annotation.textSize, weight: .semibold),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph
            ])
            context.translateBy(x: rect.minX + 10, y: rect.maxY - 10)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            let textBounds = CGRect(x: 0, y: 0, width: max(1, rect.width - 20), height: max(1, rect.height - 20))
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(string), CFRange(location: 0, length: 0),
                                                 CGPath(rect: textBounds, transform: nil), nil)
            CTFrameDraw(frame, context)
        case .step:
            let size = max(30, annotation.textSize * 2)
            context.fillEllipse(in: CGRect(x: first.x - size / 2, y: first.y - size / 2, width: size, height: size))
            let string = NSAttributedString(string: String(annotation.number ?? 1), attributes: [
                .font: NSFont.systemFont(ofSize: annotation.textSize, weight: .bold), .foregroundColor: NSColor.white
            ])
            let line = CTLineCreateWithAttributedString(string)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.translateBy(x: first.x - width / 2, y: first.y + annotation.textSize * 0.35)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity; context.textPosition = .zero
            CTLineDraw(line, context)
        case .image:
            guard let last = annotation.points.last, let data = annotation.imageData,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.message("An inserted image could not be loaded.")
            }
            drawImage(image, in: Rect(from: first, to: last).cgRect, context: context)
        case .cursor:
            guard let image = NSCursor.arrow.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CaptureError.message("The cursor image could not be loaded.")
            }
            let size = annotation.textSize
            drawImage(image, in: CGRect(x: first.x, y: first.y, width: size, height: size * Double(image.height) / Double(image.width)), context: context)
        case .eraser:
            if annotation.points.allSatisfy({ $0 == first }) {
                context.addEllipse(in: CGRect(x: first.x - annotation.thickness / 2, y: first.y - annotation.thickness / 2,
                                               width: annotation.thickness, height: annotation.thickness))
            } else {
                let path = CGMutablePath()
                path.move(to: first.cgPoint)
                annotation.points.dropFirst().forEach { path.addLine(to: $0.cgPoint) }
                context.addPath(path.copy(strokingWithWidth: annotation.thickness, lineCap: .round, lineJoin: .round, miterLimit: 10))
            }
            context.clip()
            context.setBlendMode(.copy)
            drawImage(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height), context: context)
        case .blur, .pixelate, .magnify:
            guard let last = annotation.points.last else { return }
            try drawEffect(annotation, rect: Rect(from: first, to: last), context: context, crop: crop)
        case .line, .arrow, .freehand:
            context.beginPath()
            context.move(to: first.cgPoint)
            annotation.points.dropFirst().forEach { context.addLine(to: $0.cgPoint) }
            context.strokePath()
            if annotation.tool == .arrow, annotation.points.count >= 2, let last = annotation.points.last {
                let previous = annotation.points[annotation.points.count - 2]
                let angle = atan2(last.y - previous.y, last.x - previous.x)
                let length = max(16, annotation.thickness * 4)
                context.beginPath()
                context.move(to: last.cgPoint)
                context.addLine(to: CGPoint(x: last.x - length * cos(angle - .pi / 6), y: last.y - length * sin(angle - .pi / 6)))
                context.addLine(to: CGPoint(x: last.x - length * cos(angle + .pi / 6), y: last.y - length * sin(angle + .pi / 6)))
                context.closePath(); context.fillPath()
            }
        case .select, .crop: break
        }
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func drawEffect(_ annotation: Annotation, rect: Rect, context: CGContext, crop: Rect) throws {
        guard let clipped = rect.intersection(crop) else { return }
        guard let snapshot = context.makeImage() else { throw CaptureError.message("Couldn't prepare the image effect.") }
        let local = clipped.cgRect.offsetBy(dx: -crop.x, dy: -crop.y)
        if annotation.tool == .magnify {
            let factor = max(1, annotation.effectAmount ?? 2)
            let sample = CGRect(x: local.midX - local.width / factor / 2, y: local.midY - local.height / factor / 2,
                                width: local.width / factor, height: local.height / factor).integral
            guard let image = snapshot.cropping(to: sample) else { throw CaptureError.message("Couldn't magnify that region.") }
            context.addEllipse(in: clipped.cgRect); context.clip()
            drawImage(image, in: clipped.cgRect, context: context)
            return
        }
        let input = CIImage(cgImage: snapshot)
        let filterName = annotation.tool == .blur ? "CIGaussianBlur" : "CIPixellate"
        guard let filter = CIFilter(name: filterName) else { throw CaptureError.message("This image effect is unavailable.") }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(2, annotation.effectAmount ?? 16), forKey: annotation.tool == .blur ? kCIInputRadiusKey : kCIInputScaleKey)
        let region = CGRect(x: local.minX, y: CGFloat(snapshot.height) - local.maxY, width: local.width, height: local.height)
        guard let output = filter.outputImage, let image = effects.createCGImage(output, from: region) else {
            throw CaptureError.message("Couldn't render the privacy effect.")
        }
        context.clip(to: clipped.cgRect)
        drawImage(image, in: clipped.cgRect, context: context)
    }

    static func bounds(of annotation: Annotation) -> CGRect {
        guard let first = annotation.points.first else { return .zero }
        if annotation.tool == .step {
            let size = max(30, annotation.textSize * 2)
            return CGRect(x: first.x - size / 2, y: first.y - size / 2, width: size, height: size)
        }
        if annotation.tool == .cursor {
            return CGRect(x: first.x, y: first.y, width: annotation.textSize, height: annotation.textSize * 1.5)
        }
        if annotation.tool == .text || annotation.tool == .sticker {
            let lines = annotation.text.components(separatedBy: "\n")
            let width = lines.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: annotation.textSize, weight: .semibold)]).width }.max() ?? 0
            return CGRect(x: first.x, y: first.y, width: max(width, 12), height: annotation.textSize * 1.25 * Double(lines.count))
        }
        let xs = annotation.points.map(\.x), ys = annotation.points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: max(1, xs.max()! - xs.min()!), height: max(1, ys.max()! - ys.min()!))
            .insetBy(dx: -max(6, annotation.thickness), dy: -max(6, annotation.thickness))
    }
}
