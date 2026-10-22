import AppKit
import SwiftUI
import WaddlyCore

/// Hosts the existing AppKit preview pane so the shared screen uses the app's one reaction preview.
@MainActor
struct CharacterPreviewHost: NSViewRepresentable {
    let localization: LocalizationController
    let frames: PetImageSet?
    let placeholder: String
    let onDrop: ([URL]) -> Void
    let isActive: () -> Bool
    let onPaneCreated: (SetupPreviewPane) -> Void

    func makeNSView(context: Context) -> SetupPreviewPane {
        let pane = SetupPreviewPane(frame: .zero)
        pane.configure(localization: localization, showsControls: true)
        pane.shouldPreserveUnsupportedDropURLs = { true }
        pane.onDrop = onDrop
        onPaneCreated(pane)
        return pane
    }

    func updateNSView(_ pane: SetupPreviewPane, context: Context) {
        guard isActive() else {
            pane.stopPlayback()
            return
        }
        pane.onDrop = onDrop
        if let frames, frames.isComplete {
            pane.showPet(frames, caption: "", sleeping: false)
        } else {
            pane.showPlaceholder(symbol: "pawprint", message: placeholder, caption: "")
        }
    }

    static func dismantleNSView(_ pane: SetupPreviewPane, coordinator: ()) {
        pane.stopPlayback()
        pane.onDrop = nil
    }
}
