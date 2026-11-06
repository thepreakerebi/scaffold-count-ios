import CoreGraphics
import CoreML
import CoreVideo
import Foundation

enum DetectorError: LocalizedError {
    case modelMissing
    case inputFailed
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The counting model is missing from the app."
        case .inputFailed: "Couldn't prepare the photo."
        case .predictionFailed: "The counting model didn't return a result."
        }
    }
}

/// Runs the plank model on the marked area, entirely on the phone.
///
/// The steps match the Python pipeline the model was trained and tested with:
/// 1. grey out everything outside the marked area (YOLO's grey, 114)
/// 2. crop to the area plus a 3% margin
/// 3. pad the crop to a square (stretching it instead broke photos 2 and 4) and scale to 640
/// 4. model with built-in NMS (IoU 0.5, confidence 0.25)
/// 5. drop half-boxes inside fuller boxes, keep boxes centred in the area, join side-by-side halves
final class PlankDetector: @unchecked Sendable {
    static let inputSide = 640
    private static let grey: CGFloat = 114 / 255

    private let model: MLModel

    init() throws {
        guard let url = Bundle.main.url(forResource: "PlankModel", withExtension: "mlmodelc") else {
            throw DetectorError.modelMissing
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: config)
    }

    /// Plank boxes in photo pixels.
    func detect(in image: CGImage, quad: Quad) throws -> [CGRect] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let pad = 0.03 * max(width, height)
        let area = quad.bounds
        let x0 = floor(max(area.minX - pad, 0)), y0 = floor(max(area.minY - pad, 0))
        let x1 = floor(min(area.maxX + pad, width)), y1 = floor(min(area.maxY + pad, height))
        let cropW = x1 - x0, cropH = y1 - y0
        guard cropW > 4, cropH > 4 else { return [] }

        let side = max(cropW, cropH)
        let padX = floor((side - cropW) / 2), padY = floor((side - cropH) / 2)
        let k = CGFloat(Self.inputSide) / side
        let toInput = { (p: CGPoint) in CGPoint(x: (p.x - x0 + padX) * k, y: (p.y - y0 + padY) * k) }

        let buffer = try makeInput(
            image: image,
            imageRect: CGRect(x: (padX - x0) * k, y: (padY - y0) * k, width: width * k, height: height * k),
            quad: quad.map(toInput),
            dilation: 7 * k
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: buffer),
            "iouThreshold": MLFeatureValue(double: 0.5),
            "confidenceThreshold": MLFeatureValue(double: 0.25),
        ])
        let output = try model.prediction(from: input)
        guard let confidence = output.featureValue(for: "confidence")?.multiArrayValue,
              let coordinates = output.featureValue(for: "coordinates")?.multiArrayValue
        else { throw DetectorError.predictionFailed }

        var boxes: [CGRect] = []
        var scores: [Float] = []
        let count = coordinates.shape.first?.intValue ?? 0
        for i in 0..<count {
            let score = confidence[[i, 0] as [NSNumber]].floatValue
            guard score >= 0.25 else { continue }
            let value = { (j: Int) in CGFloat(coordinates[[i, j] as [NSNumber]].floatValue) * side }
            let cx = value(0), cy = value(1), w = value(2), h = value(3)
            boxes.append(CGRect(x: cx - w / 2 - padX + x0, y: cy - h / 2 - padY + y0, width: w, height: h))
            scores.append(score)
        }

        let kept = PlankRules.dropContained(boxes, scores: scores)
            .filter { quad.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        return PlankRules.mergeSideBySide(kept)
    }

    private func makeInput(image: CGImage, imageRect: CGRect, quad: Quad, dilation: CGFloat) throws -> CVPixelBuffer {
        let side = Self.inputSide
        var created: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA, attributes, &created) == kCVReturnSuccess,
              let buffer = created
        else { throw DetectorError.inputFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: CVPixelBufferGetBaseAddress(buffer),
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw DetectorError.inputFailed }

        context.interpolationQuality = .high
        context.setFillColor(red: Self.grey, green: Self.grey, blue: Self.grey, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // Work top-down like the photo's pixel coordinates.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)

        // The area itself, then a thin band around its edge (the Python mask is dilated by 3 px).
        for edgeBand in [false, true] {
            context.saveGState()
            context.addPath(quad.path)
            if edgeBand {
                context.setLineWidth(dilation)
                context.setLineJoin(.round)
                context.replacePathWithStrokedPath()
            }
            context.clip()
            context.saveGState()
            context.translateBy(x: imageRect.minX, y: imageRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: imageRect.size))
            context.restoreGState()
            context.restoreGState()
        }
        return buffer
    }
}

/// Clean-up rules after the model, plus numbering order. Pure functions, ported from yolo.py.
enum PlankRules {
    /// Share of the inner box's area that lies inside the outer box.
    static func containedShare(_ inner: CGRect, in outer: CGRect) -> CGFloat {
        let overlap = inner.intersection(outer)
        let area = inner.width * inner.height
        guard !overlap.isNull, area > 0 else { return 0 }
        return overlap.width * overlap.height / area
    }

    /// Remove half-plank boxes that sit inside a more confident box. Result is top-to-bottom.
    static func dropContained(_ boxes: [CGRect], scores: [Float], limit: CGFloat = 0.7) -> [CGRect] {
        var kept: [Int] = []
        for i in boxes.indices.sorted(by: { scores[$0] > scores[$1] })
        where kept.allSatisfy({ containedShare(boxes[i], in: boxes[$0]) < limit }) {
            kept.append(i)
        }
        return kept
            .sorted { (boxes[$0].minY, boxes[$0].minX) < (boxes[$1].minY, boxes[$1].minX) }
            .map { boxes[$0] }
    }

    /// Join two boxes that are halves of one plank: same rows, side by side and touching,
    /// and together still about one plank wide. Planks in neighbouring columns are each a
    /// full plank wide, so they are never joined.
    static func mergeSideBySide(_ input: [CGRect], widthLimit: CGFloat = 1.35) -> [CGRect] {
        guard input.count > 1 else { return input }
        let typicalWidth = median(input.map(\.width))
        var boxes = input
        var changed = true
        while changed {
            changed = false
            search: for i in boxes.indices {
                for j in boxes.indices where j > i {
                    let a = boxes[i], b = boxes[j]
                    let rows = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                    let across = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                    let sameRows = rows > 0.6 * min(a.height, b.height)
                    let sideBySide = across < 0.3 * min(a.width, b.width) && across > -0.15 * typicalWidth
                    let joined = a.union(b)
                    if sameRows, sideBySide, joined.width <= widthLimit * typicalWidth {
                        boxes[i] = joined
                        boxes.remove(at: j)
                        changed = true
                        break search
                    }
                }
            }
        }
        return boxes
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Number planks the way a person counts a stack: column by column, left to right,
    /// top to bottom within a column.
    static func readingOrder<T>(_ items: [T], rect: @escaping (T) -> CGRect) -> [T] {
        var columns: [[T]] = []
        for item in items.sorted(by: { rect($0).midX < rect($1).midX }) {
            let r = rect(item)
            let match = columns.firstIndex { column in
                let minX = column.map { rect($0).minX }.reduce(0, +) / CGFloat(column.count)
                let maxX = column.map { rect($0).maxX }.reduce(0, +) / CGFloat(column.count)
                return r.midX >= minX && r.midX <= maxX
            }
            if let match { columns[match].append(item) } else { columns.append([item]) }
        }
        let centre = { (column: [T]) in column.map { rect($0).midX }.reduce(0, +) / CGFloat(column.count) }
        return columns
            .sorted { centre($0) < centre($1) }
            .flatMap { $0.sorted { rect($0).minY < rect($1).minY } }
    }
}
