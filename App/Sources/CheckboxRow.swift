import SwiftUI

/// A row with a name, an optional line under it, and a round checkbox on the
/// right: the Rooms sheet's Rooms and This iPhone, and Settings' kiosk mode.
/// Tapping the name or the checkbox switches it, at once.
struct CheckboxRow<Detail: View>: View {
    let name: String
    var nameFont: Font = .title3
    let isOn: Bool
    let toggle: () -> Void
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: toggle) {
                    Text(name)
                        .font(nameFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                detail
            }
            Button(action: toggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn ? "On" : "Off")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension CheckboxRow where Detail == EmptyView {
    init(name: String, nameFont: Font = .title3, isOn: Bool, toggle: @escaping () -> Void) {
        self.init(name: name, nameFont: nameFont, isOn: isOn, toggle: toggle) { EmptyView() }
    }
}
