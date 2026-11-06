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
        if let i = args.firstIndex(of: "-demo"), i + 2 < args.count,
           let image = UIImage(contentsOfFile: args[i + 1]) {
            session.start(with: image)
            if let quad = quad(from: args[i + 2]) { session.quad = quad }
            if args.contains("-result") { await session.runCount() }
        }
    }

    private static func quad(from text: String) -> Quad? {
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
#endif
