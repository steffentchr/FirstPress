import AppKit
import SwiftUI

extension View {
    /// Holds the window this view is shown in to the app's appearance, as
    /// Settings › Appearance sets it on `NSApp`.
    ///
    /// The panel needs this. The menu bar's windows don't follow
    /// `NSApp.appearance`: they take the menu bar's look, which macOS picks
    /// from the wallpaper, so with a dark menu bar the panel stayed dark
    /// whatever Settings said. A window's own appearance wins over that.
    /// System resolves through `NSApp.effectiveAppearance`, which follows
    /// macOS while `NSApp.appearance` is nil.
    func followsAppAppearance() -> some View {
        background(AppAppearanceReader())
    }
}

private struct AppAppearanceReader: NSViewRepresentable {
    func makeNSView(context: Context) -> FollowingView { FollowingView() }
    func updateNSView(_ view: FollowingView, context: Context) { view.apply() }

    final class FollowingView: NSView {
        private var appearanceObservation: NSKeyValueObservation?
        private var keyObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            appearanceObservation = nil
            keyObserver.map(NotificationCenter.default.removeObserver)
            keyObserver = nil
            guard let window else { return }
            // A change in Settings, or macOS switching while System is chosen.
            appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.apply() }
            }
            // MenuBarExtra may set its window's appearance again each time
            // the panel opens, so apply it again then.
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            apply()
        }

        func apply() {
            guard let window else { return }
            let name = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            if window.appearance?.name != name {
                window.appearance = NSAppearance(named: name)
            }
        }
    }
}
