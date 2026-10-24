import AppKit
import SwiftUI
import WaddlyCore

// MARK: - Shared small views

/// A labelled numeric pixel field with steppers. The binding clamps to the valid source bounds so a
/// typed value can never leave a crop or offset out of range.
@MainActor
struct IntegerField: View {
    var label: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var fieldAccessibilityLabel: String
    var width: CGFloat = 54

    init(
        label: String? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityLabel: String,
        width: CGFloat = 54
    ) {
        self.label = label
        _value = value
        self.range = range
        fieldAccessibilityLabel = accessibilityLabel
        self.width = width
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let label {
                Text(label)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 20, alignment: .leading)
            }
            TextField("", value: clamped, format: .number)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .multilineTextAlignment(.trailing)
                .font(DesignTokens.Typography.mono)
                .frame(width: width)
                .labelsHidden()
                .accessibilityLabel(fieldAccessibilityLabel)
            Stepper("", value: clamped, in: range)
                .labelsHidden()
                .controlSize(.large)
                .accessibilityLabel(fieldAccessibilityLabel)
        }
    }

    private var clamped: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

/// A titled, lightly bordered settings section used by the inspector.
@MainActor
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }
}

/// The transparency checkerboard behind crop previews and thumbnails.
struct CheckerboardBackground: View {
    var square: CGFloat = 8
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let dark = colorScheme == .dark
            let base = dark ? Color(white: 0.22) : Color(white: 0.88)
            let alternate = dark ? Color(white: 0.30) : Color(white: 0.97)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0 ..< rows {
                for column in 0 ..< columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * square,
                            y: CGFloat(row) * square,
                            width: square,
                            height: square
                        )),
                        with: .color(alternate)
                    )
                }
            }
        }
    }
}
