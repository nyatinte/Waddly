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

            HStack(alignment: .top, spacing: 24) {
                page
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
            Button(action: controller.importFromPanel) {
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
            Text(controller.didAttemptCopy
                ? controller.localizedString(controller.didFailCopy ? .setupCopyFailed : .setupPromptCopied)
                : " ")
                .font(.caption).foregroundStyle(controller.didFailCopy ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            bodyText(.setupWhenReady)
            Button(controller.localizedString(.setupChoosePNG), action: controller.importFromPanel)
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
                action: controller.importFromPanel
            )
            .accessibilityIdentifier("importFromPanel")
            caption(.setupDropHint)
        }
    }

    private var monitoringPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.isMonitoringGranted {
                grantedMonitoringContent
            } else {
                missingPermissionContent
            }
        }
    }

    @ViewBuilder private var grantedMonitoringContent: some View {
        if controller.isMonitoringReady {
            readyMonitoringContent
        } else {
            restartRequiredContent
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
            bodyText(.setupTroubleshootingTitle)
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
            bodyText(controller.isShowingGuide ? .setupDropGuideBody : .setupMonitoringBody)
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
        if controller.isMonitoringReady {
            return .setupCheckMonitoring
        }
        return controller.isMonitoringGranted ? .setupCheckMonitoringRestart : .setupCheckMonitoringOff
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
                caption(.setupCompleteWarning).multilineTextAlignment(.center)
                Button(controller.localizedString(.setupSetUpMonitoring), action: controller.showMonitoringStep)
                    .accessibilityLabel(controller.localizedString(.setupSetUpMonitoring))
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
            .disabled(controller.currentStep == .pet && !controller.hasImage)
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
