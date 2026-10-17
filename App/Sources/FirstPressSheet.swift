import SwiftUI

/// The chrome Settings and the Rooms sheet share: a centred title in the same
/// medium size, an X in the top right to close, and a Liquid Glass background
/// through which the screen behind still shows.
struct FirstPressSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .sheetPage(title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .modifier(GlassSheetBackground())
    }
}

extension View {
    /// A page inside a sheet (the sheet itself, or a submenu pushed in it):
    /// the title centred in the bar, and no opaque list background, so the
    /// glass shows through.
    func sheetPage(_ title: String) -> some View {
        scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// iOS 26 and later draw sheets in Liquid Glass. Earlier versions get the
/// closest material.
private struct GlassSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}
