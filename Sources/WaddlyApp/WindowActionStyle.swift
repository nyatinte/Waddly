import AppKit
import SwiftUI

extension NSButton {
    func applyPreviewActionStyle() {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                bezelStyle = .glass
            } else {
                bezelStyle = .rounded
            }
        #else
            bezelStyle = .rounded
        #endif
    }
}

@ViewBuilder
func legacyActionDivider() -> some View {
    if #available(macOS 26.0, *) {
        EmptyView()
    } else {
        Divider()
    }
}

extension View {
    @ViewBuilder
    func promptCardSurface() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            )
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).stroke(Color(nsColor: .separatorColor)))
        }
    }

    /// System glass is reserved for the primary and secondary actions in window action bars.
    /// Older systems and toolchains keep the equivalent native bordered styles.
    @ViewBuilder
    func windowActionStyle(prominent: Bool) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                if prominent {
                    buttonStyle(.glassProminent)
                        .tint(.accentColor)
                } else {
                    buttonStyle(.glass)
                }
            } else {
                legacyWindowActionStyle(prominent: prominent)
            }
        #else
            legacyWindowActionStyle(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func legacyWindowActionStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
