import SwiftUI

enum Route: Hashable {
    case mark
    case result
}

/// One box on the result: found by the model, or added by the user.
/// The last box the user changed, for the tap pulse.
struct Touch: Equatable {
    let rect: CGRect
    let added: Bool
    let date = Date()
}

struct Mark: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
    let added: Bool
    var removed = false
}

@Observable
@MainActor
final class Session {
    var path: [Route] = []
    private(set) var photo: UIImage?
    var quad = Quad.inset(CGSize(width: 1, height: 1), by: 0.12)
    private(set) var marks: [Mark] = []
    private(set) var history: [[Mark]] = []
    private(set) var counting = false
    var errorMessage: String?
    /// Changes on every edit, to drive haptics and the share image.
    private(set) var editTick = 0
    /// When the current result arrived, for the reveal animation.
    private(set) var resultDate = Date.distantPast
    private(set) var touch: Touch?
    /// Corner being dragged on the Mark screen (shows the magnifier).
    var activeCorner: Int?

    private var detector: PlankDetector?
    private var loadTask: Task<PlankDetector, Error>?

    init() {
        // Load the model in the background at launch, so the first count is instant.
        loadTask = Task.detached(priority: .utility) { try PlankDetector() }
    }

    var active: [Mark] { marks.filter { !$0.removed } }
    var count: Int { active.count }
    var removedCount: Int { marks.filter { $0.removed && !$0.added }.count }
    var addedCount: Int { marks.filter { $0.added }.count }

    /// Active marks in counting order, with their 1-based numbers.
    var numbers: [UUID: Int] {
        let ordered = PlankRules.readingOrder(active) { $0.rect }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0 + 1) })
    }

    func start(with image: UIImage) {
        let upright = image.normalizedForCounting()
        photo = upright
        quad = .inset(upright.size, by: 0.12)
        marks = []
        history = []
        errorMessage = nil
        path = [.mark]
    }

    func resetQuad() {
        guard let photo else { return }
        quad = .inset(photo.size, by: 0.12)
    }

    func newPhoto() {
        path = []
        errorMessage = nil
    }

    func runCount() async {
        guard let photo, let image = photo.cgImage, !counting else { return }
        counting = true
        errorMessage = nil
        let quad = self.quad
        do {
            let detector = try await loadedDetector()
            let rects = try await Task.detached(priority: .userInitiated) {
                try detector.detect(in: image, quad: quad)
            }.value
            marks = rects.map { Mark(rect: $0, added: false) }
            history = []
            resultDate = Date()
            counting = false
            if path.last != .result { path.append(.result) }
        } catch {
            counting = false
            errorMessage = (error as? DetectorError)?.errorDescription.map { "\($0) Try again." }
                ?? "Couldn't count this photo. Try again."
        }
    }

    private func loadedDetector() async throws -> PlankDetector {
        if let detector { return detector }
        do {
            let loaded = try await (loadTask ?? Task.detached { try PlankDetector() }).value
            detector = loaded
            return loaded
        } catch {
            loadTask = nil // retry from scratch next time
            throw error
        }
    }

    /// A tap on the result, in photo pixels. `tolerance` widens thin boxes so they are easy to hit.
    func tap(at point: CGPoint, tolerance: CGFloat) {
        let hits = marks.indices
            .filter { marks[$0].rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            .sorted { distance(marks[$0].rect, point) < distance(marks[$1].rect, point) }
        if let i = hits.first {
            history.append(marks)
            touch = Touch(rect: marks[i].rect, added: marks[i].added)
            if marks[i].added {
                marks.remove(at: i)
            } else {
                marks[i].removed.toggle()
            }
        } else if quad.contains(point), let photo {
            history.append(marks)
            let size = typicalSize
            var rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            rect.origin.x = min(max(rect.minX, 0), photo.size.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), photo.size.height - rect.height)
            marks.append(Mark(rect: rect, added: true))
            touch = Touch(rect: rect, added: true)
        } else {
            return
        }
        editTick += 1
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        marks = previous
        editTick += 1
    }

    /// Size for a plank the user adds: the median found plank, or a guess from the area.
    private var typicalSize: CGSize {
        let found = marks.filter { !$0.added }.map(\.rect)
        if !found.isEmpty {
            return CGSize(width: PlankRules.median(found.map(\.width)), height: PlankRules.median(found.map(\.height)))
        }
        let area = quad.bounds
        return CGSize(width: area.width * 0.25, height: max(area.height * 0.06, 8))
    }

    private func distance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(rect.midX - p.x, rect.midY - p.y)
    }
}
