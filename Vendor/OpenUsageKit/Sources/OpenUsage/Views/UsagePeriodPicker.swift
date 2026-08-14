import SwiftUI

/// The shared Today / Yesterday / 30 Days switch used by cross-provider usage cards.
struct UsagePeriodPicker: View {
    @Binding var selection: UsagePeriod
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsagePeriod.allCases) { candidate in
                segment(candidate)
            }
        }
        .padding(3)
        .background(.quinary, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func segment(_ candidate: UsagePeriod) -> some View {
        let isSelected = candidate == selection
        return Button {
            selection = candidate
        } label: {
            Text(verbatim: L10n.string(candidate.shortLabel))
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(.background)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .matchedGeometryEffect(id: "usagePeriod", in: selectionNamespace)
            }
        }
        .animation(Motion.spring, value: selection)
    }
}
