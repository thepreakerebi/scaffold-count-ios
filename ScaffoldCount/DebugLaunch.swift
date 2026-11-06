#if DEBUG
import UIKit

/// Debug-only launch arguments, used to check the app against the Python results
/// and to open a given screen for screenshots. Not in release builds.
///
///   -selftest <file.json>   {"dir": "...", "photos": {"plank1": [x0,y0, x1,y1, x2,y2, x3,y3], ...}}
///                           prints "SELFTEST <name> <count>" per photo, then exits
///   -demo <photo> <8 comma-separated corner coordinates>   opens the Mark screen
///   -result                 with -demo: also runs the count and opens the result
enum DebugLaunch {
    @MainActor
    static func run(_ session: Session) async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-selftest"), i + 1 < args.count {
            selftest(file: args[i + 1])
        }
        if let i = args.firstIndex(of: "-tour"), i + 1 < args.count {
            await DemoTour(session: session).run(file: args[i + 1])
        }
        if let i = args.firstIndex(of: "-demo"), i + 2 < args.count,
           let image = UIImage(contentsOfFile: args[i + 1]) {
            session.start(with: image)
            if let quad = quad(from: args[i + 2]) { session.quad = quad }
            if args.contains("-result") { await session.runCount() }
        }
    }

    static func quad(from text: String) -> Quad? {
        let values = text.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        guard values.count == 8 else { return nil }
        return Quad(stride(from: 0, to: 8, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) })
    }

    private static func selftest(file: String) {
        struct Spec: Decodable {
            let dir: String
            let photos: [String: [Double]]
        }
        do {
            let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
            let detector = try PlankDetector()
            for name in spec.photos.keys.sorted() {
                guard let image = UIImage(contentsOfFile: "\(spec.dir)/\(name).png")?.normalizedForCounting().cgImage,
                      let quad = quad(from: spec.photos[name]!.map { String($0) }.joined(separator: ","))
                else { print("SELFTEST \(name) unreadable"); continue }
                let start = Date()
                let count = try detector.detect(in: image, quad: quad).count
                print("SELFTEST \(name) \(count) \(Int(Date().timeIntervalSince(start) * 1000))ms")
            }
        } catch {
            print("SELFTEST failed: \(error)")
        }
        fflush(stdout)
        exit(0)
    }
}
/// Scripted walkthrough for the demo video. It drives the real screens and the real
/// counting code; only the touches are scripted, shown as fingertip dots.
///   -tour <file.json>   same format as -selftest; plays "plank3" then "plank2"
@MainActor
struct DemoTour {
    let session: Session
    private var tour: Tour { Tour.shared }

    func run(file: String) async {
        struct Spec: Decodable {
            let dir: String
            let photos: [String: [Double]]
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
              let spec = try? JSONDecoder().decode(Spec.self, from: data)
        else { print("TOUR bad spec"); return }
        let load = { (name: String) -> (UIImage, Quad)? in
            guard let image = UIImage(contentsOfFile: "\(spec.dir)/\(name).png"),
                  let values = spec.photos[name],
                  let quad = DebugLaunch.quad(from: values.map { String($0) }.joined(separator: ","))
            else { return nil }
            return (image, quad)
        }
        guard let first = load("plank3"), let second = load("plank2") else { print("TOUR missing photos"); return }

        await wait(7.0)
        tour.fingers = [CGPoint(x: 200, y: 640)]
        await wait(0.4)

        // Photo 1: neat stack of 76
        await tap("library") { session.start(with: first.0) }
        await wait(1.0)
        await markCorners(to: first.1)
        await tap("count") { Task { await session.runCount() } }
        await wait(2.4)

        // Remove a plank, then undo
        if let mark = markNumbered(30) {
            await tapImage(CGPoint(x: mark.rect.midX, y: mark.rect.midY)) {
                session.tap(at: CGPoint(x: mark.rect.midX, y: mark.rect.midY), tolerance: 1)
            }
            await wait(1.3)
            await tap("undo") { session.undo() }
            await wait(1.0)
        }

        // Pinch to zoom into the stack, then fit again
        await pinch(at: imagePoint(CGPoint(x: session.quad.bounds.midX, y: session.quad.bounds.minY + session.quad.bounds.height * 0.3)), to: 3)
        await wait(1.4)
        await tap("fit") { tour.zoomRequest = ZoomRequest(scale: 1, anchor: .zero, fit: true) }
        await wait(1.2)

        // Photo 2: staggered planks of mixed thickness, 27
        await tap("newPhoto") { session.newPhoto() }
        await wait(1.0)
        await tap("library") { session.start(with: second.0) }
        await wait(1.0)
        await markCorners(to: second.1)
        await tap("count") { Task { await session.runCount() } }
        await wait(2.4)

        await wait(1.5)
        tour.fingers = []
        await wait(0.8)
        print("TOUR DONE")
        fflush(stdout)
    }

    // MARK: - Moves

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    /// Move one finger, calling `step` with the eased progress on every frame.
    private func glide(to target: CGPoint, duration: Double, step: ((Double) -> Void)? = nil) async {
        let start = tour.fingers.first ?? target
        let frames = max(Int(duration * 60), 1)
        for frame in 1...frames {
            let t = ease(Double(frame) / Double(frames))
            tour.fingers = [CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)]
            step?(t)
            await wait(1.0 / 60)
        }
    }

    private func press(_ action: () -> Void) async {
        tour.pressed = true
        await wait(0.12)
        action()
        tour.pressed = false
        await wait(0.2)
    }

    private func tap(_ target: String, action: () -> Void) async {
        guard let frame = tour.targets[target] else { print("TOUR no target \(target)"); return }
        await glide(to: CGPoint(x: frame.midX, y: frame.midY), duration: 0.55)
        await wait(0.15)
        await press(action)
    }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        let rect = tour.imageRect
        let scale = rect.width / max(session.photo?.size.width ?? 1, 1)
        return CGPoint(x: rect.minX + p.x * scale, y: rect.minY + p.y * scale)
    }

    private func tapImage(_ p: CGPoint, action: () -> Void) async {
        await glide(to: imagePoint(p), duration: 0.55)
        await wait(0.15)
        await press(action)
    }

    private func markCorners(to target: Quad) async {
        for index in 0..<4 {
            let from = session.quad[index]
            await glide(to: imagePoint(from), duration: 0.45)
            tour.pressed = true
            session.activeCorner = index
            await wait(0.15)
            let to = target[index]
            await glide(to: imagePoint(to), duration: 0.7) { t in
                session.quad[index] = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
            await wait(0.15)
            session.activeCorner = nil
            tour.pressed = false
            await wait(0.2)
        }
    }

    private func markNumbered(_ number: Int) -> Mark? {
        let numbers = session.numbers
        return session.marks.first { numbers[$0.id] == number }
    }

    /// Two fingers spreading apart around `anchor` while the photo zooms.
    private func pinch(at anchor: CGPoint, to scale: CGFloat) async {
        await glide(to: anchor, duration: 0.5)
        let frames = 60
        for frame in 0...frames {
            let t = ease(Double(frame) / Double(frames))
            let spread = 30 + 70 * t
            tour.fingers = [
                CGPoint(x: anchor.x - spread, y: anchor.y - spread * 0.6),
                CGPoint(x: anchor.x + spread, y: anchor.y + spread * 0.6),
            ]
            tour.zoomRequest = ZoomRequest(scale: 1 + (scale - 1) * t, anchor: anchor)
            await wait(1.0 / 60)
        }
        await wait(0.2)
        tour.fingers = [CGPoint(x: anchor.x + 60, y: anchor.y + 120)]
    }
}
#endif
