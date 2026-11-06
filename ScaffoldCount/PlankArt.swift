import SwiftUI

/// Fine-line drawing of a stack of plank ends, the first few boxed and numbered,
/// showing what the app does before anything is photographed.
struct PlankArt: View {
    private let columns = 3
    private let rows = 5
    private let counted = 7

    var body: some View {
        Canvas { context, size in
            let plankW: CGFloat = 58, plankH: CGFloat = 22, gapX: CGFloat = 6, gapY: CGFloat = 4
            let totalW = CGFloat(columns) * plankW + CGFloat(columns - 1) * gapX
            let totalH = CGFloat(rows) * plankH + CGFloat(rows - 1) * gapY
            let origin = CGPoint(x: (size.width - totalW) / 2, y: (size.height - totalH) / 2)
            let line = Palette.faint
            var index = 0

            for c in 0..<columns {
                for r in 0..<rows {
                    let rect = CGRect(
                        x: origin.x + CGFloat(c) * (plankW + gapX),
                        y: origin.y + CGFloat(r) * (plankH + gapY),
                        width: plankW,
                        height: plankH
                    )
                    index += 1
                    // plank end: outline, the top flange, two holes
                    context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(line), lineWidth: 1)
                    var flange = Path()
                    flange.move(to: CGPoint(x: rect.minX + 3, y: rect.minY + 5))
                    flange.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 5))
                    context.stroke(flange, with: .color(line.opacity(0.7)), lineWidth: 0.8)
                    for hx in [rect.minX + plankW * 0.3, rect.minX + plankW * 0.7] {
                        let hole = CGRect(x: hx - 3, y: rect.midY - 1, width: 6, height: 6)
                        context.stroke(Path(ellipseIn: hole), with: .color(line), lineWidth: 0.8)
                    }

                    guard index <= counted else { continue }
                    let box = rect.insetBy(dx: -2, dy: -2)
                    context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(Palette.mark.opacity(0.14)))
                    context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(Palette.mark), lineWidth: 1.4)
                    let label = context.resolve(
                        Text("\(index)").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.ink)
                    )
                    let textSize = label.measure(in: rect.size)
                    let pill = CGRect(
                        x: rect.midX - textSize.width / 2 - 4,
                        y: rect.midY - textSize.height / 2,
                        width: textSize.width + 8,
                        height: textSize.height
                    )
                    context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(Palette.mark))
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Small app mark: three plank ends, one counted.
struct AppGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: s * 0.26), with: .color(Palette.primary))
            let w = s * 0.56, h = s * 0.15, x = (s - w) / 2
            for (i, y) in [s * 0.22, s * 0.425, s * 0.63].enumerated() {
                let rect = CGRect(x: x, y: y, width: w, height: h)
                if i == 1 {
                    context.fill(Path(roundedRect: rect, cornerRadius: h * 0.3), with: .color(Palette.mark))
                } else {
                    context.stroke(Path(roundedRect: rect, cornerRadius: h * 0.3), with: .color(.white.opacity(0.85)), lineWidth: max(1, s * 0.045))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
