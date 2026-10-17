import AppKit
import SwiftUI

/// The panel's window, which SwiftUI's MenuBarExtra keeps to itself.
enum PanelWindow {
    /// Opens the panel, as clicking the menu-bar icon does. SwiftUI has no
    /// call for that, so this clicks Pressing Menu's own status-bar button.
    @MainActor
    static func open() {
        for window in NSApplication.shared.windows {
            guard let button = statusButton(in: window.contentView) else { continue }
            button.performClick(nil)
            return
        }
    }

    @MainActor
    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}

/// Reports whether the window this view sits in is showing: the panel is
/// open while its window is key, and closes when it stops being key.
struct PanelVisibility: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: WatchingView, context: Context) {
        view.onChange = onChange
    }

    final class WatchingView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else {
                onChange?(false)
                return
            }
            for (name, open) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange?(open) }
                })
            }
            onChange?(window.isKeyWindow)
        }
    }
}

/// Catches a right-click (or a Control-click) on what it overlays, with no
/// context menu. A left-click does nothing.
struct RightClickArea: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
    }

    final class ClickView: NSView {
        var action: (@MainActor () -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { action?() }
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

extension View {
    /// Right-clicking this opens `action` straight away, with no menu.
    func onRightClick(_ action: @escaping @MainActor () -> Void) -> some View {
        overlay(RightClickArea(action: action))
    }
}
