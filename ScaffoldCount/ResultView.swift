import SwiftUI

/// Step 3: numbered boxes and the count. Tap to fix, pinch to zoom, share the marked photo.
struct ResultView: View {
    @Environment(Session.self) private var session
    @State private var zoom = Zoom()
    @State private var fitTick = 0
    @State private var shareImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Count") {
                RoundIconButton(systemName: "chevron.left", label: "Adjust area") {
                    session.path.removeLast()
                }
            } trailing: {
                RoundIconButton(systemName: "arrow.uturn.backward", label: "Undo", disabled: session.history.isEmpty) {
                    session.undo()
                }
                .tourTarget("undo")
            }

            summary
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            if let photo = session.photo {
                ResultCanvas(photo: photo, zoom: $zoom, fitTick: fitTick)
                    .overlay(alignment: .topTrailing) {
                        if zoom.scale > 1.01 {
                            RoundIconButton(systemName: "arrow.down.right.and.arrow.up.left", label: "Fit photo") {
                                fitTick += 1
                            }
                            .tourTarget("fit")
                            .padding(12)
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if session.marks.isEmpty { emptyCard }
                    }
                    .animation(.snappy, value: zoom.scale > 1.01)
            } else {
                Spacer()
            }

            Footer {
                Button("New photo") { session.newPhoto() }
                    .buttonStyle(TextButtonStyle())
                    .tourTarget("newPhoto")
                if session.marks.isEmpty {
                    Button("Adjust area") { session.path.removeLast() }
                        .buttonStyle(PrimaryButtonStyle())
                } else if let shareImage {
                    ShareLink(
                        item: Image(uiImage: shareImage),
                        preview: SharePreview(countLabel, image: Image(uiImage: shareImage))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .background(Palette.surface)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .light), trigger: session.editTick)
        .sensoryFeedback(.success, trigger: session.resultDate)
        .onAppear(perform: renderShare)
        .onChange(of: session.editTick) { renderShare() }
        .onChange(of: session.resultDate) { renderShare() }
    }

    private var countLabel: String {
        "\(session.count) \(session.count == 1 ? "plank" : "planks")"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(session.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(session.count)))
                    .animation(.snappy, value: session.count)
                Text(session.count == 1 ? "plank" : "planks")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                edits
            }
            Text(session.marks.isEmpty ? " " : "Tap a box to remove it, or a missed plank to add it. Pinch to zoom.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder private var edits: some View {
        let parts = [
            session.removedCount > 0 ? "\(session.removedCount) removed" : nil,
            session.addedCount > 0 ? "\(session.addedCount) added" : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.muted)
                .transition(.opacity)
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No planks found")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("The marked area may miss the plank ends. Adjust the corners, or tap each plank to add it.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line))
        .padding(16)
    }

    private func renderShare() {
        guard let photo = session.photo else { return }
        shareImage = ShareRenderer.render(
            photo: photo,
            marks: session.active,
            numbers: session.numbers,
            title: countLabel
        )
    }
}

struct Zoom: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
}

/// The photo with boxes, drawn in one Canvas so it stays sharp at any zoom.
struct ResultCanvas: View {
    @Environment(Session.self) private var session
    let photo: UIImage
    @Binding var zoom: Zoom
    let fitTick: Int
    @State private var gestureStart: Zoom?
    @State private var revealing = true
    @State private var pulsing = false
    /// Zoom glides back to fit instead of jumping.
    @State private var glide: (from: Zoom, start: Date)?

    private static let revealDuration = 0.7
    private static let pulseDuration = 0.35
    private static let glideDuration = 0.32

    var body: some View {
        GeometryReader { geo in
            let fit = Fit(image: photo.size, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 8))
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let transform = Transform(fit: fit, centre: centre, zoom: zoom)

            TimelineView(.animation(paused: !(revealing || pulsing || glide != nil))) { timeline in
                let now = timeline.date
                let progress = min(1, now.timeIntervalSince(session.resultDate) / Self.revealDuration)
                Canvas { context, _ in
                    let shown = Transform(fit: fit, centre: centre, zoom: glidingZoom(at: now))
                    draw(in: &context, transform: shown, progress: progress)
                    drawPulse(in: &context, transform: shown, now: now)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    session.tap(at: transform.image(value.location), tolerance: 6 / transform.scale)
                }
            )
            .simultaneousGesture(magnify(fit: fit, centre: centre, size: geo.size))
            .simultaneousGesture(pan(fit: fit, size: geo.size))
            .onAppear {
                let origin = geo.frame(in: .global).origin
                Tour.shared.imageRect = fit.rect.offsetBy(dx: origin.x, dy: origin.y)
            }
            .onChange(of: Tour.shared.zoomRequest) { _, request in
                guard let request else { return }
                if request.fit { animateToFit(); return }
                let origin = geo.frame(in: .global).origin
                let a = CGPoint(x: request.anchor.x - origin.x, y: request.anchor.y - origin.y)
                let offset = CGSize(width: (a.x - centre.x) * (1 - request.scale), height: (a.y - centre.y) * (1 - request.scale))
                zoom = clamped(Zoom(scale: request.scale, offset: offset), fit: fit, size: geo.size)
            }
        }
        .clipped()
        .task(id: session.resultDate) {
            revealing = true
            try? await Task.sleep(for: .seconds(Self.revealDuration + 0.1))
            revealing = false
        }
        .task(id: session.touch) {
            guard session.touch != nil else { return }
            pulsing = true
            try? await Task.sleep(for: .seconds(Self.pulseDuration + 0.05))
            pulsing = false
        }
        .onChange(of: fitTick) { animateToFit() }
    }

    private func animateToFit() {
        guard zoom != Zoom() else { return }
        glide = (zoom, Date())
        zoom = Zoom()
        Task {
            try? await Task.sleep(for: .seconds(Self.glideDuration + 0.05))
            glide = nil
        }
    }

    /// While gliding back to fit, the drawn zoom eases from where it was to 1x.
    private func glidingZoom(at now: Date) -> Zoom {
        guard let glide else { return zoom }
        let t = min(1, now.timeIntervalSince(glide.start) / Self.glideDuration)
        let e = 1 - pow(1 - t, 3) // ease out
        return Zoom(
            scale: glide.from.scale + (zoom.scale - glide.from.scale) * e,
            offset: CGSize(
                width: glide.from.offset.width + (zoom.offset.width - glide.from.offset.width) * e,
                height: glide.from.offset.height + (zoom.offset.height - glide.from.offset.height) * e
            )
        )
    }

    /// A ring that grows and fades from the box just tapped.
    private func drawPulse(in context: inout GraphicsContext, transform t: Transform, now: Date) {
        guard let touch = session.touch else { return }
        let age = now.timeIntervalSince(touch.date) / Self.pulseDuration
        guard age >= 0, age < 1 else { return }
        let grow = 2 + 10 * (1 - pow(1 - age, 2))
        let ring = t.view(touch.rect).insetBy(dx: -grow, dy: -grow)
        let colour = touch.added ? Palette.added : Palette.mark
        context.stroke(
            Path(roundedRect: ring, cornerRadius: 4),
            with: .color(colour.opacity(0.9 * (1 - age))),
            lineWidth: 2
        )
    }

    struct Transform {
        let fit: Fit
        let centre: CGPoint
        let zoom: Zoom

        var scale: CGFloat { fit.scale * zoom.scale }

        func view(_ p: CGPoint) -> CGPoint {
            let v = fit.view(p)
            return CGPoint(
                x: centre.x + (v.x - centre.x) * zoom.scale + zoom.offset.width,
                y: centre.y + (v.y - centre.y) * zoom.scale + zoom.offset.height
            )
        }

        func view(_ r: CGRect) -> CGRect {
            let o = view(r.origin)
            return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
        }

        func image(_ v: CGPoint) -> CGPoint {
            fit.image(CGPoint(
                x: centre.x + (v.x - centre.x - zoom.offset.width) / zoom.scale,
                y: centre.y + (v.y - centre.y - zoom.offset.height) / zoom.scale
            ))
        }
    }

    private func draw(in context: inout GraphicsContext, transform t: Transform, progress: Double) {
        let imageRect = t.view(CGRect(origin: .zero, size: photo.size))
        context.draw(Image(uiImage: photo), in: imageRect)

        var outside = Path()
        outside.addRect(imageRect)
        outside.addLines(session.quad.points.map(t.view))
        outside.closeSubpath()
        context.fill(outside, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))

        // Boxes appear top to bottom as a light sweep passes over the stack.
        let area = session.quad.bounds
        let sweepY = area.minY + area.height * progress
        let numbers = session.numbers
        // One label size for every box (sized to the typical box), so numbers read evenly.
        let typicalHeight = PlankRules.median(session.active.map { t.view($0.rect).height })
        let labelSize = min(max(typicalHeight * 0.55, 9), 13)
        var drawnLabels: [CGRect] = []

        for mark in session.marks {
            guard mark.added || mark.rect.midY <= sweepY || progress >= 1 else { continue }
            let rect = t.view(mark.rect)
            if mark.removed {
                context.stroke(
                    Path(rect),
                    with: .color(.white.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                continue
            }
            let colour = mark.added ? Palette.added : Palette.mark
            context.fill(Path(rect), with: .color(colour.opacity(0.16)))
            context.stroke(Path(rect), with: .color(colour), lineWidth: 1.5)

            guard let number = numbers[mark.id], rect.height >= labelSize else { continue }
            let fontSize = labelSize
            let label = context.resolve(
                Text("\(number)")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
            )
            let size = label.measure(in: CGSize(width: 200, height: 40))
            guard size.width + 6 <= rect.width, size.height <= rect.height + 1 else { continue } // too small: shows on zoom
            let pill = CGRect(x: rect.midX - size.width / 2 - 3, y: rect.midY - size.height / 2, width: size.width + 6, height: size.height)
            guard !drawnLabels.contains(where: { $0.intersects(pill) }) else { continue }
            drawnLabels.append(pill)
            context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(colour))
            context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
        }

        if progress < 1 {
            let y = t.view(CGPoint(x: 0, y: sweepY)).y
            let left = t.view(CGPoint(x: area.minX, y: 0)).x
            let right = t.view(CGPoint(x: area.maxX, y: 0)).x
            let band = CGRect(x: left, y: y - 18, width: right - left, height: 18)
            context.fill(
                Path(band),
                with: .linearGradient(
                    Gradient(colors: [Palette.mark.opacity(0), Palette.mark.opacity(0.45)]),
                    startPoint: CGPoint(x: 0, y: band.minY),
                    endPoint: CGPoint(x: 0, y: band.maxY)
                )
            )
        }
    }

    private func clamped(_ z: Zoom, fit: Fit, size: CGSize) -> Zoom {
        let maxX = max(0, (fit.rect.width * z.scale - size.width) / 2 + 40)
        let maxY = max(0, (fit.rect.height * z.scale - size.height) / 2 + 40)
        return Zoom(
            scale: z.scale,
            offset: CGSize(
                width: min(max(z.offset.width, -maxX), maxX),
                height: min(max(z.offset.height, -maxY), maxY)
            )
        )
    }

    private func magnify(fit: Fit, centre: CGPoint, size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = gestureStart ?? zoom
                if gestureStart == nil { gestureStart = zoom }
                let scale = min(max(start.scale * value.magnification, 1), 8)
                // Keep the spot under the fingers in place.
                let anchor = value.startLocation
                let unzoomed = CGPoint(
                    x: centre.x + (anchor.x - centre.x - start.offset.width) / start.scale,
                    y: centre.y + (anchor.y - centre.y - start.offset.height) / start.scale
                )
                let offset = CGSize(
                    width: anchor.x - centre.x - (unzoomed.x - centre.x) * scale,
                    height: anchor.y - centre.y - (unzoomed.y - centre.y) * scale
                )
                zoom = clamped(Zoom(scale: scale, offset: offset), fit: fit, size: size)
            }
            .onEnded { _ in
                gestureStart = nil
                if zoom.scale < 1.05 { animateToFit() }
            }
    }

    private func pan(fit: Fit, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard zoom.scale > 1.01 else { return }
                let start = gestureStart ?? zoom
                if gestureStart == nil { gestureStart = zoom }
                zoom = clamped(
                    Zoom(scale: zoom.scale, offset: CGSize(
                        width: start.offset.width + value.translation.width,
                        height: start.offset.height + value.translation.height
                    )),
                    fit: fit,
                    size: size
                )
            }
            .onEnded { _ in gestureStart = nil }
    }
}
