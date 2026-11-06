import SwiftUI

/// Step 2: drag four corners around the plank ends.
struct MarkView: View {
    @Environment(Session.self) private var session
    @State private var dragging: Int?
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Mark the stack") {
                RoundIconButton(systemName: "chevron.left", label: "Back") { session.newPhoto() }
            } trailing: {
                HeaderSpacer()
            }

            if let photo = session.photo {
                editor(photo)
            } else {
                Spacer()
            }

            Text("Drag the corners to the edges of the plank ends. Leave other stacks outside.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)

            if let message = session.errorMessage {
                Banner(systemName: "exclamationmark.triangle", message: message)
                    .padding(.bottom, 8)
            }

            Footer {
                Button("Reset") {
                    withAnimation(.snappy) { session.resetQuad() }
                }
                .buttonStyle(TextButtonStyle())
                .disabled(session.counting)

                Button {
                    Task { await session.runCount() }
                } label: {
                    if session.counting {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.onPrimary)
                            Text("Counting")
                        }
                    } else {
                        Text("Count planks")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.counting)
            }
        }
        .background(Palette.surface)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: session.errorMessage)
        .sensoryFeedback(.selection, trigger: dragging) { _, new in new != nil }
    }

    private func editor(_ photo: UIImage) -> some View {
        GeometryReader { geo in
            let fit = Fit(image: photo.size, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 24, dy: 8))
            let corners = session.quad.points.map(fit.view)

            ZStack(alignment: .topLeading) {
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: fit.rect.width, height: fit.rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .position(x: fit.rect.midX, y: fit.rect.midY)

                // Dim everything outside the area.
                Path { path in
                    path.addRoundedRect(in: fit.rect, cornerSize: CGSize(width: 6, height: 6))
                    path.addLines(corners)
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Path { path in
                    path.addLines(corners)
                    path.closeSubpath()
                }
                .stroke(Palette.mark, lineWidth: 2)
                .allowsHitTesting(false)

                ForEach(0..<4, id: \.self) { index in
                    handle(active: dragging == index)
                        .position(corners[index])
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("editor"))
                                .onChanged { value in
                                    if dragStart == nil {
                                        dragStart = session.quad[index]
                                        dragging = index
                                    }
                                    guard let start = dragStart else { return }
                                    session.quad[index] = fit.clamp(CGPoint(
                                        x: start.x + value.translation.width / fit.scale,
                                        y: start.y + value.translation.height / fit.scale
                                    ))
                                }
                                .onEnded { _ in
                                    dragStart = nil
                                    dragging = nil
                                }
                        )
                        .accessibilityLabel(["Top left corner", "Top right corner", "Bottom right corner", "Bottom left corner"][index])
                }

                if let index = dragging {
                    let corner = corners[index]
                    Loupe(image: photo, quad: session.quad, centre: session.quad[index], zoom: fit.scale * 3)
                        .position(
                            x: corner.x < geo.size.width / 2 ? geo.size.width - 84 : 84,
                            y: 72
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "editor")
            .animation(.snappy(duration: 0.2), value: dragging)
        }
    }

    private func handle(active: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Palette.mark, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .scaleEffect(active ? 1.25 : 1)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}

/// Magnified view under the finger while a corner moves, since the corner covers the spot.
struct Loupe: View {
    let image: UIImage
    let quad: Quad
    let centre: CGPoint
    let zoom: CGFloat

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let toView = { (p: CGPoint) in CGPoint(x: c.x + (p.x - centre.x) * zoom, y: c.y + (p.y - centre.y) * zoom) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.ink))
            context.draw(
                Image(uiImage: image),
                in: CGRect(origin: toView(.zero), size: CGSize(width: image.size.width * zoom, height: image.size.height * zoom))
            )
            var edges = Path()
            edges.addLines(quad.points.map(toView))
            edges.closeSubpath()
            context.stroke(edges, with: .color(Palette.mark), lineWidth: 2)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - 8, y: c.y))
            cross.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - 8))
            cross.addLine(to: CGPoint(x: c.x, y: c.y + 8))
            context.stroke(cross, with: .color(.white), lineWidth: 1.5)
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}
