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
                    SetupPreviewHost(pane: controller.previewPane)
                        .frame(width: LayoutMetrics.previewWidth)
                        .frame(maxHeight: .infinity)
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
        .frame(width: SetupMetrics.contentSize.width, height: SetupMetrics.contentSize.height)
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
            Button(action: controller.copyPromptAndOpenChatGPT) {
                Label(controller.localizedString(.setupCopyAndOpen), systemImage: "doc.on.doc")
                    .actionLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(controller.localizedString(.setupCopyAndOpen))
            .accessibilityIdentifier("copyPromptAndOpenChatGPT")
            Text(controller.promptFeedbackKey.map { controller.localizedString($0) } ?? " ")
                .font(.caption)
                .foregroundStyle(controller.promptFeedbackIsError ? .red : .secondary)
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
                action: controller.beginCharacterImport
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

    private var monitoringPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch controller.monitoringReadiness {
            case .permissionMissing:
                missingPermissionContent
            case .tapUnavailable:
                restartRequiredContent
            case .awaitingReaction:
                awaitingReactionContent
            case .reactionObserved:
                readyMonitoringContent
            }
        }
    }

    /// The tap is live but no key has reached the app yet: the pet is awake, reactions are unproven.
    private var awaitingReactionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupMonitoringWaitingTitle)
            bodyText(.setupMonitoringWaitingBody)
            status(.setupMonitoringStatusWaiting, positive: false)
            bodyText(.setupTryTyping)
            actionButton(
                controller.localizedString(.setupNotWorking),
                identifier: "toggleTroubleshooting"
            ) { controller.toggleTroubleshooting() }
            if controller.isShowingTroubleshooting {
                troubleshootingContent
            }
        }
    }

    private var readyMonitoringContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupMonitoringGrantedTitle)
            bodyText(.setupMonitoringGrantedBody)
            status(.setupMonitoringStatusGranted, positive: true)
            bodyText(.setupTryTyping)
            actionButton(
                controller.localizedString(.setupNotWorking),
                identifier: "toggleTroubleshooting"
            ) { controller.toggleTroubleshooting() }
            if controller.isShowingTroubleshooting {
                troubleshootingContent
            }
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupTroubleshootingTitle)
            bodyText(.setupTroubleshootingBody)
            actionButton(
                controller.localizedString(.setupRestartNow),
                identifier: "relaunchApp"
            ) { controller.relaunchApp() }
            actionButton(
                controller.localizedString(.setupRevealInFinder),
                identifier: "revealInFinder"
            ) { controller.revealInFinder() }
            actionButton(
                controller.localizedString(.setupOpenSystemSettings),
                identifier: "openInputMonitoringSettings"
            ) { controller.openInputMonitoringSettings() }
        }
    }

    private var restartRequiredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupRestartRequiredTitle)
            bodyText(.setupRestartRequiredBody)
            status(.setupMonitoringStatusGranted, positive: true)
            actionButton(
                controller.localizedString(.setupRestartNow),
                identifier: "relaunchApp"
            ) { controller.relaunchApp() }
                .buttonStyle(.borderedProminent)
            actionButton(
                controller.localizedString(.setupRetryWithoutRestart),
                identifier: "retryMonitoring"
            ) { controller.retryMonitoring() }
            actionButton(
                controller.localizedString(.setupRevealInFinder),
                identifier: "revealInFinder"
            ) { controller.revealInFinder() }
        }
    }

    private var missingPermissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupMonitoringTitle)
            bodyText(.setupMonitoringBody)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label(controller.localizedString(.setupPrivacyTitle), systemImage: "lock.shield")
                        .font(.headline)
                    bodyText(.setupPrivacyNote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            status(.setupMonitoringStatusOff, positive: false)
            permissionActionContent
        }
    }

    @ViewBuilder private var permissionActionContent: some View {
        if controller.isShowingManualSteps {
            manualPermissionSteps
        } else if controller.isShowingGuide {
            permissionGuideActions
        } else {
            actionButton(
                controller.localizedString(.setupEnableMonitoring),
                identifier: "enableMonitoring"
            ) { controller.enableMonitoring() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var manualPermissionSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            numbered([.setupManualStep1, .setupManualStep2, .setupManualStep3])
            actionButton(
                controller.localizedString(.setupOpenSystemSettings),
                identifier: "openInputMonitoringSettings"
            ) { controller.openInputMonitoringSettings() }
            actionButton(
                controller.localizedString(.setupDragInstead),
                identifier: "dragInstead"
            ) { controller.toggleManualSteps() }
        }
    }

    private var permissionGuideActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The drag source lives in the page column, not over the preview: the pet stays visible,
            // and the only thing being dragged is the icon the instruction names.
            HStack(spacing: 12) {
                AppIconDragSource(localization: controller.localization)
                    .frame(width: 40, height: 40)
                Text(controller.localizedString(.setupDropGuideBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
            caption(.setupMonitoringWatching)
            actionButton(
                controller.localizedString(.setupReopenSettings),
                identifier: "reopenSettings"
            ) { controller.openInputMonitoringSettings() }
            actionButton(
                controller.localizedString(.setupHelperAlternative),
                identifier: "helperAlternative"
            ) { controller.toggleManualSteps() }
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

/// The draggable Waddly icon, in the page column. Reuses the AppKit drag source so the pasteboard
/// item keeps the file-URL flavours System Settings accepts.
@MainActor
private struct AppIconDragSource: NSViewRepresentable {
    let localization: LocalizationController

    func makeNSView(context: Context) -> DraggableAppIconView {
        DraggableAppIconView(localization: localization)
    }

    func updateNSView(_ nsView: DraggableAppIconView, context: Context) {
        nsView.updateLocalization(localization)
    }
}
