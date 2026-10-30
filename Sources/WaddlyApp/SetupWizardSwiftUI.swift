import AppKit
import SwiftUI
import WaddlyCore

@MainActor
struct SetupWizardScreen: View {
    @ObservedObject var controller: SetupWizardController

    var body: some View {
        VStack(spacing: 0) {
            if !controller.isMonitoringSettings, controller.currentStep != .completed {
                HStack(spacing: 10) {
                    step(.setupStepPet, index: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    step(.setupStepMonitoring, index: 1)
                    Spacer()
                }
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.top, 22)
            }

            if controller.isComposingCharacter {
                characterImport
            } else {
                HStack(alignment: .top, spacing: LayoutMetrics.columnGap) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Window-wide drops stay live on every step, so the failure has to be visible
                        // here too; `setStep` clears it when the user moves on.
                        if controller.didFailImport {
                            errorMessage(.petImportErrorMessage)
                        }
                        page
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    // The permission guide parks beside System Settings, so it drops the preview
                    // column: the pet it would show is asleep, and the list must stay visible.
                    if !controller.isCompactGuide {
                        SetupPreviewHost(pane: controller.previewPane)
                            .frame(width: LayoutMetrics.previewWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.top, LayoutMetrics.sectionGap)
                .padding(.bottom, LayoutMetrics.sectionGap)
                .frame(maxHeight: .infinity)

                // The footer belongs to the window, not to the scrollable content above it.
                Divider()
                footer
                    .padding(.horizontal, LayoutMetrics.contentInset)
                    .padding(.vertical, LayoutMetrics.footerInset)
            }
        }
        .frame(width: controller.contentSize.width, height: controller.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(MotionPreference.isReduced ? nil : .easeInOut(duration: 0.18), value: controller.currentStep)
    }

    @ViewBuilder private var page: some View {
        switch controller.currentStep {
        case .pet: petPage
        case .monitoring: monitoringPage
        case .completed: completedPage
        }
    }
}

@MainActor
private extension SetupWizardScreen {
    var petPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(petTitleKey)
            if controller.hasImage || controller.didRegisterPet {
                registeredPetContent
            } else if controller.isShowingChatGPTGuide {
                chatGPTGuideContent
            } else {
                petImportOptions
            }
        }
    }

    private var registeredPetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            bodyText(.setupRegisteredBody)
            if controller.didUseSamplePet {
                caption(.setupSampleActive)
            }
            if let importedFileName = controller.importedFileName {
                caption(String(format: controller.localizedString(.setupImageImported), importedFileName))
            }
            if let image = controller.currentPetImages()[.idle].first, image.size.width > 0 {
                caption(String(
                    format: controller.localizedString(.setupImageDetails),
                    Int(image.size.width) * 3,
                    Int(image.size.width)
                ))
            }
            actionButton(
                controller.localizedString(.setupChangeImage),
                identifier: "changeImage"
            ) { controller.beginCharacterImport() }
        }
    }

    private var chatGPTGuideContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            bodyText(.setupChatGPTPromptBody)
            numbered([.setupChatGPTStep1, .setupChatGPTStep2, .setupChatGPTStep3])
            Button(action: controller.openPromptInChatGPT) {
                Label(controller.localizedString(.setupOpenChatGPT), systemImage: "arrow.up.right.square")
                    .actionLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(controller.localizedString(.setupOpenChatGPT))
            .accessibilityIdentifier("openPromptInChatGPT")
            Text(controller.promptFeedbackKey.map { controller.localizedString($0) } ?? " ")
                .font(.caption)
                .foregroundStyle(controller.promptFeedbackIsError ? DesignTokens.Status.critical : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            bodyText(.setupWhenReady)
            actionButton(
                controller.localizedString(.setupChoosePNG),
                identifier: "importFromPanel"
            ) { controller.beginCharacterImport() }
            Button(controller.localizedString(.setupChangeMethod), action: controller.changeMethod)
                .buttonStyle(.link)
                .accessibilityLabel(controller.localizedString(.setupChangeMethod))
                .accessibilityIdentifier("changeMethod")
        }
    }

    private var petImportOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            bodyText(.setupPetBody)
            option(
                .setupMethodChatGPT,
                detail: .setupMethodChatGPTDetail,
                symbol: "sparkles",
                action: controller.showChatGPTGuide
            )
            .accessibilityIdentifier("showChatGPTGuide")
            option(
                .setupMethodChoosePNG,
                detail: .setupMethodChoosePNGDetail,
                symbol: "square.and.arrow.down",
                action: { controller.beginCharacterImport() }
            )
            .accessibilityIdentifier("importFromPanel")
            sampleOption
            caption(.setupDropHint)
        }
    }

    /// The one-click path to a visible pet. It is a plain choice, not a required step, and it only
    /// appears while no pet is stored.
    @ViewBuilder private var sampleOption: some View {
        if controller.canTrySample {
            actionButton(
                controller.localizedString(.setupTrySample),
                identifier: "trySamplePet"
            ) { _ = controller.trySamplePet() }
        }
    }

    private var petTitleKey: LocalizationKey {
        if controller.hasImage || controller.didRegisterPet {
            return .setupRegisteredTitle
        }
        return controller.isShowingChatGPTGuide ? .setupChatGPTPromptTitle : .setupPetTitle
    }
}

@MainActor
private struct SetupPreviewHost: NSViewRepresentable {
    let pane: SetupPreviewPane

    func makeNSView(context: Context) -> SetupPreviewPane {
        pane
    }

    func updateNSView(_ nsView: SetupPreviewPane, context: Context) {}
}
