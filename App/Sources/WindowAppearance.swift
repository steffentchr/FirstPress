import SwiftUI
import UIKit

/// Holds the app's window Light or Dark, and tells what iOS itself is set to.
///
/// The window is held dark on the start screen, whatever the appearance, so
/// its status bar stays white over the orange. The override goes on the
/// window rather than through `preferredColorScheme`, which overrides the
/// whole window scene: this way the scene still follows iOS, and `system`
/// can follow it too. Sheets inherit the window's override, so they set the
/// appearance themselves, with System resolved through `system`.
@MainActor @Observable
final class WindowAppearance {
    /// iOS's own Light or Dark setting.
    private(set) var system: ColorScheme = .dark
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private var held: ColorScheme?

    func attach(_ window: UIWindow) {
        guard self.window !== window else { return }
        self.window = window
        apply()
        guard let scene = window.windowScene else { return }
        update(from: scene)
        scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (scene: UIWindowScene, _: UITraitCollection) in
            self?.update(from: scene)
        }
    }

    /// Holds the window Light or Dark, or lets it follow iOS (nil).
    func hold(_ scheme: ColorScheme?) {
        held = scheme
        apply()
    }

    private func apply() {
        window?.overrideUserInterfaceStyle = switch held {
        case .light: .light
        case .dark: .dark
        default: .unspecified
        }
    }

    private func update(from scene: UIWindowScene) {
        system = scene.traitCollection.userInterfaceStyle == .light ? .light : .dark
    }
}

/// Hands over the window this view is shown in, once it's in one.
struct WindowReader: UIViewRepresentable {
    let found: @MainActor (UIWindow) -> Void

    func makeUIView(context: Context) -> WindowView {
        WindowView(found: found)
    }

    func updateUIView(_ view: WindowView, context: Context) {}

    final class WindowView: UIView {
        let found: @MainActor (UIWindow) -> Void

        init(found: @escaping @MainActor (UIWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { found(window) }
        }
    }
}
