import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

/// Progressive disclosure of the existing per-frame editor over the parent screen's staged draft.
///
/// It reuses `AnimationSettingsView` and only redirects its callbacks: nothing here commits, so
/// closing the sheet returns to the parent preview with the staged modifications intact.
@MainActor
struct CharacterFrameEditor: View {
    @ObservedObject var importModel: CharacterImportModel
    @ObservedObject var editor: AnimationSettingsModel
    let localization: LocalizationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnimationSettingsView(model: editor)
            HStack {
                Spacer()
                Button(localization.string(for: .characterEditFramesDone)) { importModel.isEditingFrames = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AnimationSettingsMetrics.contentInset)
        .frame(minWidth: 660, minHeight: 520)
        .onAppear { refreshThumbnails() }
        .onChange(of: importModel.draftVersion) { _, _ in refreshThumbnails() }
    }

    /// Builds the editor model once per host, wired to the import model's staged draft.
    static func makeModel(
        importModel: CharacterImportModel,
        localization: LocalizationController
    ) -> AnimationSettingsModel {
        let editor = AnimationSettingsModel(thumbnailsByCategory: [:], localization: localization)
        editor.onAdd = { category in
            let picker = NSOpenPanel()
            picker.allowedContentTypes = [.png]
            picker.allowsMultipleSelection = true
            picker.canChooseDirectories = false
            picker.prompt = localization.string(for: .imagesAdd)
            guard picker.runModal() == .OK else { return }
            Task { await importModel.addFrames(picker.urls, to: category) }
        }
        editor.onDrop = { category, urls in
            Task { await importModel.addFrames(urls, to: category) }
        }
        editor.onRemove = { category, index in importModel.removeFrame(at: index, from: category) }
        editor.onMove = { category, source, destination in
            importModel.moveFrame(from: source, to: destination, in: category)
        }
        editor.setThumbnails(thumbnails(from: importModel.stagedFrames))
        return editor
    }

    private func refreshThumbnails() {
        editor.setThumbnails(Self.thumbnails(from: importModel.stagedFrames))
    }

    static func thumbnails(
        from frames: PetImageSet?
    ) -> [PetImageCategory: [AnimationSettingsThumbnail]] {
        var result: [PetImageCategory: [AnimationSettingsThumbnail]] = [:]
        guard let frames else { return result }
        for category in PetImageCategory.allCases {
            result[category] = frames[category].map(AnimationSettingsThumbnail.init)
        }
        return result
    }
}
