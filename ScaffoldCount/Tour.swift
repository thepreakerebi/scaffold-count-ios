import SwiftUI

/// State for the debug demo walkthrough (`-tour`): where the on-screen fingertips are,
/// and where buttons and the photo sit, so a scripted run can press them.
/// Inert in normal use: nothing drives it, and the overlay draws nothing.
@Observable
@MainActor
final class Tour {
    static let shared = Tour()

    var fingers: [CGPoint] = []
    var pressed = false
    var zoomRequest: ZoomRequest?
    @ObservationIgnored var targets: [String: CGRect] = [:]
    @ObservationIgnored var imageRect: CGRect = .zero
}

struct ZoomRequest: Equatable {
    var scale: CGFloat
    var anchor: CGPoint
    var fit = false
    let id = UUID()
}

extension View {
    func tourTarget(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { Tour.shared.targets[id] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in Tour.shared.targets[id] = frame }
            }
        )
    }
}

/// Fingertip markers, like the touch dots in a screen recording.
struct TouchOverlay: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Tour.shared.fingers.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1.5))
                    .frame(width: 38, height: 38)
                    .scaleEffect(Tour.shared.pressed ? 0.8 : 1)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                    .position(point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: Tour.shared.pressed)
    }
}
