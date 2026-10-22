import SwiftUI

/// One set of layout numbers for the setup-class windows, so the character screen and the setup
/// steps cannot drift apart again: the same insets, the same action height, and the same gaps.
enum LayoutMetrics {
    /// Window content inset for the header, the body, and the footer.
    static let contentInset: CGFloat = 24
    /// Gap between a heading block and the content below it.
    static let sectionGap: CGFloat = 16
    /// Gap between the body's two columns.
    static let columnGap: CGFloat = 20
    /// Gap between adjacent actions in one row.
    static let actionGap: CGFloat = 8
    /// Height of a normal action, so a footer button and an in-page button line up.
    static let actionHeight: CGFloat = 36
    /// Vertical padding around a pinned footer row.
    static let footerInset: CGFloat = 12
    /// Width of the preview column in the shared character screen.
    static let previewWidth: CGFloat = 360
}

extension View {
    /// The shared action size: exactly 36 pt tall, with the roomy 12 pt side padding the layout
    /// rule asks for. A `.controlSize(.large)` bordered button is 28 pt; the 4 pt label padding
    /// takes it to 36 without changing the native drawing.
    ///
    /// Apply to the button's label so the drawn control grows with it; a frame around the button
    /// would leave the background at its default height.
    func actionLabel() -> some View {
        padding(.vertical, 4)
            .padding(.horizontal, 6)
    }
}
