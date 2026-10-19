import AppKit
import SwiftUI
import WaddlyCore

@MainActor
struct SetupWizardScreen: View {
    @ObservedObject var controller: SetupWizardController

    var body: some View {
        VStack(spacing: 0) {
            if controller.currentStep != .completed {
                HStack(spacing: 10) {
                    step(.setupStepPet, index: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    step(.setupStepMonitoring, index: 1)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
            }

            if controller.isComposingCharacter {
                characterImport
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Window-wide drops stay live on every step, so the failure has to be visible
                        // here too; `setStep` clears it when the user moves on.
                        if controller.didFailImport {
                            errorMessage(.petImportErrorMessage)
                        }
                        page
                    }
                    .frame(width: 410, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    SetupPreviewHost(pane: controller.previewPane)
                        .frame(width: 330)
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 18)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
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
            Button(action: controller.beginCharacterImport) {
                Text(verbatim: controller.localizedString(.setupChangeImage))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: controller.localizedString(.setupChangeImage)))
            .accessibilityIdentifier("changeImage")
        }
    }

    private var chatGPTGuideContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            bodyText(.setupChatGPTPromptBody)
            numbered([.setupChatGPTStep1, .setupChatGPTStep2, .setupChatGPTStep3])
            Button(action: controller.copyPromptAndOpenChatGPT) {
                Label(controller.localizedString(.setupCopyAndOpen), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(controller.localizedString(.setupCopyAndOpen))
            .accessibilityIdentifier("copyPromptAndOpenChatGPT")
            Text(controller.promptFeedbackKey.map { controller.localizedString($0) } ?? " ")
                .font(.caption)
                .foregroundStyle(controller.promptFeedbackIsError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            bodyText(.setupWhenReady)
            Button(controller.localizedString(.setupChoosePNG), action: controller.beginCharacterImport)
                .accessibilityLabel(controller.localizedString(.setupChoosePNG))
                .accessibilityIdentifier("importFromPanel")
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
            Button(controller.localizedString(.setupTrySample)) { _ = controller.trySamplePet() }
                .accessibilityLabel(controller.localizedString(.setupTrySample))
                .accessibilityIdentifier("trySamplePet")
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
            Button(controller.localizedString(.setupNotWorking), action: controller.toggleTroubleshooting)
                .accessibilityLabel(controller.localizedString(.setupNotWorking))
                .accessibilityIdentifier("toggleTroubleshooting")
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
            Button(controller.localizedString(.setupNotWorking), action: controller.toggleTroubleshooting)
                .accessibilityLabel(controller.localizedString(.setupNotWorking))
                .accessibilityIdentifier("toggleTroubleshooting")
            if controller.isShowingTroubleshooting {
                troubleshootingContent
            }
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupTroubleshootingTitle)
            bodyText(.setupTroubleshootingBody)
            Button(controller.localizedString(.setupRestartNow), action: controller.relaunchApp)
                .accessibilityLabel(controller.localizedString(.setupRestartNow))
                .accessibilityIdentifier("relaunchApp")
            Button(controller.localizedString(.setupRevealInFinder), action: controller.revealInFinder)
                .accessibilityLabel(controller.localizedString(.setupRevealInFinder))
                .accessibilityIdentifier("revealInFinder")
            Button(controller.localizedString(.setupOpenSystemSettings)) {
                controller.openInputMonitoringSettings()
            }
            .accessibilityLabel(controller.localizedString(.setupOpenSystemSettings))
            .accessibilityIdentifier("openInputMonitoringSettings")
        }
    }

    private var restartRequiredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupRestartRequiredTitle)
            bodyText(.setupRestartRequiredBody)
            status(.setupMonitoringStatusGranted, positive: true)
            Button(controller.localizedString(.setupRestartNow), action: controller.relaunchApp)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(controller.localizedString(.setupRestartNow))
                .accessibilityIdentifier("relaunchApp")
            Button(controller.localizedString(.setupRetryWithoutRestart), action: controller.retryMonitoring)
                .accessibilityLabel(controller.localizedString(.setupRetryWithoutRestart))
                .accessibilityIdentifier("retryMonitoring")
            Button(controller.localizedString(.setupRevealInFinder), action: controller.revealInFinder)
                .accessibilityLabel(controller.localizedString(.setupRevealInFinder))
                .accessibilityIdentifier("revealInFinder")
        }
    }

    private var missingPermissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupMonitoringTitle)
            bodyText(controller.isShowingGuide && !controller.isShowingManualSteps
                ? .setupDropGuideBody
                : .setupMonitoringBody)
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
            Button(action: controller.enableMonitoring) {
                Text(verbatim: controller.localizedString(.setupEnableMonitoring))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: controller.localizedString(.setupEnableMonitoring)))
            .accessibilityIdentifier("enableMonitoring")
        }
    }

    private var manualPermissionSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            numbered([.setupManualStep1, .setupManualStep2, .setupManualStep3])
            Button(controller.localizedString(.setupOpenSystemSettings)) {
                controller.openInputMonitoringSettings()
            }
            .accessibilityLabel(controller.localizedString(.setupOpenSystemSettings))
            .accessibilityIdentifier("openInputMonitoringSettings")
            Button(controller.localizedString(.setupDragInstead), action: controller.toggleManualSteps)
                .accessibilityLabel(controller.localizedString(.setupDragInstead))
        }
    }

    private var permissionGuideActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(.setupMonitoringWatching)
            Button(controller.localizedString(.setupReopenSettings)) {
                controller.openInputMonitoringSettings()
            }
            .accessibilityLabel(controller.localizedString(.setupReopenSettings))
            Button(controller.localizedString(.setupHelperAlternative), action: controller.toggleManualSteps)
                .accessibilityLabel(controller.localizedString(.setupHelperAlternative))
        }
    }

    private var petTitleKey: LocalizationKey {
        if controller.hasImage || controller.didRegisterPet {
            return .setupRegisteredTitle
        }
        return controller.isShowingChatGPTGuide ? .setupChatGPTPromptTitle : .setupPetTitle
    }

    private var monitoringCheckKey: LocalizationKey {
        controller.monitoringCheckKey
    }

    private var nextButtonKey: LocalizationKey {
        controller.currentStep == .completed ? .setupShowOnDesktop : .setupNext
    }

    private var completedPage: some View {
        VStack(spacing: 12) {
            title(.setupCompleteTitle).multilineTextAlignment(.center)
            bodyText(.setupCompleteBody).multilineTextAlignment(.center)
            Label(controller.localizedString(.setupCheckPet), systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(
                controller.localizedString(monitoringCheckKey),
                systemImage: controller.isMonitoringReady ? "checkmark.circle.fill" : "circle"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if !controller.isMonitoringReady {
                caption(controller.monitoringIncompleteWarningKey).multilineTextAlignment(.center)
                Button(
                    controller.localizedString(controller.monitoringIncompleteActionKey),
                    action: controller.showMonitoringStep
                )
                .accessibilityLabel(controller.localizedString(controller.monitoringIncompleteActionKey))
                .accessibilityIdentifier("showMonitoringStep")
            }
            caption(.setupCompleteHint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if controller.currentStep != .pet {
                Button(action: controller.goBack) {
                    Text(verbatim: controller.localizedString(.setupBack))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: controller.localizedString(.setupBack)))
                .accessibilityIdentifier("goBack")
            }
            Spacer()
            if controller.currentStep == .monitoring, !controller.isMonitoringReady {
                Button(action: controller.deferMonitoring) {
                    Text(verbatim: controller.localizedString(.setupLater))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: controller.localizedString(.setupLater)))
                .accessibilityIdentifier("deferMonitoring")
            }
            Button(action: controller.goNext) {
                Text(verbatim: controller.localizedString(nextButtonKey))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: controller.localizedString(nextButtonKey)))
            .buttonStyle(.borderedProminent)
            .disabled(
                (controller.currentStep == .pet && !controller.hasImage)
                    || (controller.currentStep == .monitoring && !controller.isMonitoringReady)
            )
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("goNext")
        }
        .frame(height: SetupMetrics.footerHeight)
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
