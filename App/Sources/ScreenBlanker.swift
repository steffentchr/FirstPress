import SwiftUI
import PressingCore

/// Covers the screen in black while Pressing has blanked it, to protect the
/// OLED panel. The first touch on the black overlay only wakes the screen;
/// every other touch restarts the blank-after time.
struct ScreenBlanker: ViewModifier {
    let pressing: Pressing

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onEnded { _ in pressing.screenTouched() }
            )
            .overlay {
                if pressing.state.screen.isBlanked {
                    Color.black
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        // The overlay swallows the touch, so no control underneath gets it.
                        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in pressing.screenTouched() })
                        .statusBarHidden()
                        .persistentSystemOverlays(.hidden)
                }
            }
    }
}

extension View {
    func screenBlanker(_ pressing: Pressing) -> some View {
        modifier(ScreenBlanker(pressing: pressing))
    }
}
