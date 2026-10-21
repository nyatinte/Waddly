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
        HStack(spacing: 3) {
            if let label {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 46, alignment: .leading)
            }
            TextField("", value: clamped, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: width)
                .labelsHidden()
                .accessibilityLabel(fieldAccessibilityLabel)
            Stepper("", value: clamped, in: range)
                .labelsHidden()
                .controlSize(.mini)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
            let base = dark ? Color(white: 0.17) : Color(white: 0.93)
            let alternate = dark ? Color(white: 0.23) : Color(white: 0.98)
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
