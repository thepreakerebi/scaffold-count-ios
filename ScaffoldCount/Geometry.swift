import CoreGraphics
import UIKit

/// The marked stack area, in photo pixels. Corner order: top-left, top-right, bottom-right, bottom-left.
struct Quad: Equatable {
    var points: [CGPoint]

    init(_ points: [CGPoint]) {
        precondition(points.count == 4)
        self.points = points
    }

    static func inset(_ size: CGSize, by fraction: CGFloat) -> Quad {
        let dx = size.width * fraction, dy = size.height * fraction
        return Quad([
            CGPoint(x: dx, y: dy),
            CGPoint(x: size.width - dx, y: dy),
            CGPoint(x: size.width - dx, y: size.height - dy),
            CGPoint(x: dx, y: size.height - dy),
        ])
    }

    subscript(index: Int) -> CGPoint {
        get { points[index] }
        set { points[index] = newValue }
    }

    var path: CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    var bounds: CGRect { path.boundingBoxOfPath }

    func contains(_ point: CGPoint) -> Bool { path.contains(point) }

    func map(_ transform: (CGPoint) -> CGPoint) -> Quad { Quad(points.map(transform)) }
}

/// Aspect-fit placement of a photo inside a view rect, with conversions both ways.
struct Fit {
    let imageSize: CGSize
    let rect: CGRect

    init(image: CGSize, in container: CGRect) {
        imageSize = image
        let scale = min(container.width / max(image.width, 1), container.height / max(image.height, 1))
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        rect = CGRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var scale: CGFloat { rect.width / max(imageSize.width, 1) }

    func view(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * scale, y: rect.minY + p.y * scale)
    }

    func image(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - rect.minX) / scale, y: (p.y - rect.minY) / scale)
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), imageSize.width), y: min(max(p.y, 0), imageSize.height))
    }
}

extension UIImage {
    /// Upright pixels at scale 1 (so points equal pixels), capped in size.
    /// A photo that is already upright and small enough is returned untouched, so the
    /// app sees exactly the pixels the Python pipeline saw.
    func normalizedForCounting(maxSide: CGFloat = 2400) -> UIImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, maxSide / max(pixels.width, pixels.height))
        if imageOrientation == .up, scale == 1, factor == 1, cgImage != nil { return self }
        let target = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
