import SwiftUI

@main
struct ScaffoldCountApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.light)
                #if DEBUG
                .task { await DebugLaunch.run(session) }
                #endif
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $session.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .mark: MarkView()
                    case .result: ResultView()
                    }
                }
        }
        .tint(Palette.primary)
    }
}

/// Every screen draws its own fixed header, so the system bar is hidden.
/// Hiding it switches off swipe-back; this turns it on again.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
