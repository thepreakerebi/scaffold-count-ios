import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    /// Text is never pure black.
    static let ink = Color(hex: 0x1C2321)
    static let muted = Color(hex: 0x5D6663)
    static let faint = Color(hex: 0x9CA3A0)
    static let surface = Color(hex: 0xF2F3F1)
    static let card = Color.white
    static let line = Color(hex: 0xDFE2DF)
    static let primary = Color(hex: 0x0F4A45)
    static let onPrimary = Color.white
    /// Safety orange: boxes the model found.
    static let mark = Color(hex: 0xFF7A1A)
    /// Boxes the user added.
    static let added = Color(hex: 0x12A9C4)
    static let error = Color(hex: 0xB3261E)
    static let errorWash = Color(hex: 0xFCEDEB)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
