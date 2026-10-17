import SwiftUI
import UIKit
import FirstPressCore

/// Covers the screen in black while First Press has blanked it, to protect the
/// OLED panel. The first touch on the black overlay only wakes the screen;
/// every other touch restarts the blank-after time.
///
/// Touches are seen by a recogniser on the window rather than by SwiftUI
/// gestures. A SwiftUI gesture on a sheet whose Close button dismisses it
/// leaves the next touch on the screen underneath swallowed, so the gear or
/// speaker icon took a second tap.
struct ScreenBlanker: ViewModifier {
    let firstPress: FirstPress

    func body(content: Content) -> some View {
        content
            .background { TouchObserver { firstPress.screenTouched() } }
            .overlay {
                if firstPress.state.screen.isBlanked {
                    // Opaque, so it takes the touch and no control underneath
                    // gets it; the window's recogniser wakes the screen.
                    Color.black
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .statusBarHidden()
                        .persistentSystemOverlays(.hidden)
                }
            }
    }
}

extension View {
    func screenBlanker(_ firstPress: FirstPress) -> some View {
        modifier(ScreenBlanker(firstPress: firstPress))
    }
}

/// Puts a `TouchRecognizer` on the window this view is in. Sheets are in the
/// same window, so one sees every touch in the app; the extra copies a sheet
/// adds only see the same touches again.
private struct TouchObserver: UIViewRepresentable {
    let touched: @MainActor () -> Void

    func makeUIView(context: Context) -> WindowAttacher {
        WindowAttacher(recognizer: context.coordinator)
    }

    func updateUIView(_ view: WindowAttacher, context: Context) {
        context.coordinator.touched = touched
    }

    func makeCoordinator() -> TouchRecognizer {
        TouchRecognizer(touched: touched)
    }

    static func dismantleUIView(_ view: WindowAttacher, coordinator: TouchRecognizer) {
        coordinator.view?.removeGestureRecognizer(coordinator)
    }

    final class WindowAttacher: UIView {
        let recognizer: TouchRecognizer

        init(recognizer: TouchRecognizer) {
            self.recognizer = recognizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }
}

/// Reports each touch as it ends and never recognises, so it takes nothing
/// away from the controls the touch was meant for.
private final class TouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var touched: @MainActor () -> Void

    init(touched: @escaping @MainActor () -> Void) {
        self.touched = touched
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touched()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
