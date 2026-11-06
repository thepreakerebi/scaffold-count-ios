import UIKit

/// The photo with numbered boxes and a count bar, for sharing or saving.
enum ShareRenderer {
    static func render(photo: UIImage, marks: [Mark], numbers: [UUID: Int], title: String) -> UIImage {
        let size = photo.size
        let unit = max(size.width, size.height) / 600
        let bar = max(64, 72 * unit)
        let canvas = CGSize(width: size.width, height: size.height + bar)
        let format = UIGraphicsImageRendererFormat()
        // Small photos are drawn larger so lines and numbers stay sharp.
        format.scale = max(1, 1400 / max(size.width, 1))
        format.opaque = true

        let ink = UIColor(hex: 0x1C2321)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            photo.draw(at: .zero)
            let cg = context.cgContext

            for mark in marks {
                let colour = mark.added ? UIColor(hex: 0x12A9C4) : UIColor(hex: 0xFF7A1A)
                cg.setFillColor(colour.withAlphaComponent(0.16).cgColor)
                cg.fill(mark.rect)
                cg.setStrokeColor(colour.cgColor)
                cg.setLineWidth(max(1, 1.2 * unit))
                cg.stroke(mark.rect)

                guard let number = numbers[mark.id] else { continue }
                let font = UIFont.systemFont(ofSize: max(5, min(mark.rect.height * 0.6, 13 * unit)), weight: .bold)
                let text = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: ink])
                let textSize = text.size()
                guard textSize.width + 4 <= mark.rect.width else { continue }
                let pill = CGRect(
                    x: mark.rect.midX - textSize.width / 2 - 2,
                    y: mark.rect.midY - textSize.height / 2,
                    width: textSize.width + 4,
                    height: textSize.height
                )
                colour.setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
                text.draw(at: CGPoint(x: pill.minX + 2, y: pill.minY))
            }

            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: size.height, width: size.width, height: bar))
            let titleFont = UIFont.systemFont(ofSize: bar * 0.36, weight: .bold)
            let heading = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: ink])
            heading.draw(at: CGPoint(x: bar * 0.3, y: size.height + (bar - heading.size().height) / 2))

            let date = Date().formatted(date: .abbreviated, time: .shortened)
            let note = NSAttributedString(string: date, attributes: [
                .font: UIFont.systemFont(ofSize: bar * 0.22, weight: .medium),
                .foregroundColor: UIColor(hex: 0x5D6663),
            ])
            note.draw(at: CGPoint(
                x: size.width - note.size().width - bar * 0.3,
                y: size.height + (bar - note.size().height) / 2
            ))
        }
    }
}
