import SwiftUI

@MainActor
extension SetupWizardScreen {
    /// The shared import screen owns the pet step's primary action while it is open, so setup never
    /// shows two competing primary buttons.
    var characterImport: some View {
        CharacterImportView(
            model: controller.characterImportModel,
            localization: controller.localization,
            titleKey: .characterSetupTitle,
            primaryKey: .setupNext,
            onPrimary: { _ = controller.commitCharacterImportAndContinue() },
            onCancel: controller.cancelCharacterImport,
            onPreviewPaneCreated: { [weak controller] pane in controller?.embeddedCharacterPreviewPane = pane },
            isPreviewActive: { controller.isComposingCharacter },
            onPreviewHostDisappear: { [weak controller] in controller?.stopEmbeddedCharacterPreview() },
            pickFile: controller.chooseCharacterFile,
            pasteboard: controller.pasteboard,
            // Setup's Continue advances the wizard, so an already valid pet may be committed as is.
            primaryRequiresChange: false
        )
    }
}
