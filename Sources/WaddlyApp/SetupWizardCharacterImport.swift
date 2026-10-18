import SwiftUI

@MainActor
extension SetupWizardScreen {
    /// The shared import screen owns the pet step's primary action while it is open, so setup never
    /// shows two competing primary buttons.
    var characterImport: some View {
        CharacterImportView(
            model: controller.characterImportModel,
            editor: controller.frameEditorModel,
            localization: controller.localization,
            titleKey: .characterSetupTitle,
            primaryKey: .setupNext,
            onPrimary: { _ = controller.commitCharacterImportAndContinue() },
            onCancel: controller.cancelCharacterImport,
            pickFile: controller.chooseCharacterFile,
            pasteboard: controller.pasteboard
        )
    }
}
