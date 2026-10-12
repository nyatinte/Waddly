import AppKit
import WaddlyCore

// MARK: - Step 1: pet

extension SetupWizardController {
    func makePetPage() -> NSView {
        if hasImage || didRegisterPet {
            return makeRegisteredPetPage()
        }
        return isShowingChatGPTGuide ? makeChatGPTGuidePage() : makePetOptionsPage()
    }

    private func makePetOptionsPage() -> NSView {
        let body = makeBody(.setupPetBody)
        let chatGPT = SetupOptionCard(
            symbol: "sparkles",
            title: localizedString(.setupMethodChatGPT),
            detail: localizedString(.setupMethodChatGPTDetail),
            target: self,
            action: #selector(showChatGPTGuide)
        )
        let choose = SetupOptionCard(
            symbol: "square.and.arrow.down",
            title: localizedString(.setupMethodChoosePNG),
            detail: localizedString(.setupMethodChoosePNGDetail),
            target: self,
            action: #selector(importFromPanel)
        )
        let hint = makeCaption(.setupDropHint)
        let page = makeStack(
            [makeTitle(.setupPetTitle), body, chatGPT, choose, hint],
            fullWidth: [body, chatGPT, choose, hint]
        )
        page.spacing = 12
        page.setCustomSpacing(24, after: body)
        page.setCustomSpacing(24, after: choose)
        return page
    }

    /// Kept to the same height as the other pet states so the window never resizes.
    private func makeChatGPTGuidePage() -> NSView {
        let body = makeBody(.setupChatGPTPromptBody)
        let recipe = makeNumberedCard([.setupChatGPTStep1, .setupChatGPTStep2, .setupChatGPTStep3])
        let copy = makePrimaryButton(.setupCopyAndOpen, action: #selector(copyPromptAndOpenChatGPT))
        let status = copyStatusLabel()
        let ready = makeCaption(.setupWhenReady)
        let choose = makeSecondaryButton(.setupChoosePNG, action: #selector(importFromPanel))
        let change = makeLinkButton(.setupChangeMethod, action: #selector(changeMethod))
        let page = makeStack(
            [makeTitle(.setupChatGPTPromptTitle), body, recipe, copy, status, ready, choose, change],
            fullWidth: [body, recipe, ready]
        )
        page.spacing = 12
        page.setCustomSpacing(20, after: body)
        page.setCustomSpacing(16, after: recipe)
        page.setCustomSpacing(16, after: status)
        return page
    }

    /// Copy feedback sits directly under the button that triggers it; no modal or toast.
    /// Before the first attempt the line is reserved but empty, so it never claims a copy happened.
    private func copyStatusLabel() -> NSTextField {
        let label = makeCaption(didFailCopy ? .setupCopyFailed : .setupPromptCopied)
        if !didAttemptCopy {
            label.stringValue = " "
        }
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return label
    }

    private func makeRegisteredPetPage() -> NSView {
        let body = makeBody(.setupRegisteredBody)
        var views: [NSView] = [makeTitle(.setupRegisteredTitle), body]
        var fullWidth: [NSView] = [body]
        if let importedFileName {
            let file = makeCaptionValue(String(format: localizedString(.setupImageImported), importedFileName))
            views.append(file)
            fullWidth.append(file)
        }
        // The 3x3 facts belong next to the result, not in a separate confirmation step.
        if let detail = registeredImageDetail() {
            let details = makeCaptionValue(detail)
            views.append(details)
            fullWidth.append(details)
        }
        views.append(makeSecondaryButton(.setupChangeImage, action: #selector(importFromPanel)))
        let page = makeStack(views, fullWidth: fullWidth)
        page.spacing = 12
        page.setCustomSpacing(24, after: body)
        return page
    }

    /// The size facts a user needs to trust the 3x3 contract, in one compact line.
    private func imageDetailText(for images: PetImageSet) -> String? {
        guard let cell = images[.idle].first?.size.width, cell > 0 else { return nil }
        return String(format: localizedString(.setupImageDetails), Int(cell) * 3, Int(cell))
    }

    private func registeredImageDetail() -> String? {
        let images = currentPetImages()
        guard images.isComplete else { return nil }
        return imageDetailText(for: images)
    }

    private func makeCaptionValue(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - Step 2: input monitoring

extension SetupWizardController {
    /// Short by design: every variant occupies the same vertical rhythm so the window never resizes.
    /// "Allowed" and "actually receiving keys" are separate states and are never conflated.
    func makeMonitoringPage() -> NSView {
        if isMonitoringGranted {
            return isMonitoringReady ? makeMonitoringReadyPage() : makeMonitoringRestartPage()
        }
        return makeMonitoringRequestPage()
    }

    /// Granted, but the keyboard is not arriving: macOS reports this as "restart required".
    private func makeMonitoringRestartPage() -> NSView {
        let body = makeBody(.setupRestartRequiredBody)
        let page = makeStack(
            [
                makeTitle(.setupRestartRequiredTitle),
                body,
                makeStatus(.setupMonitoringStatusGranted, isPositive: true),
                makePrimaryButton(.setupRestartNow, action: #selector(relaunchApp)),
                makeLinkButton(.setupRetryWithoutRestart, action: #selector(retryMonitoring)),
                makeLinkButton(.setupRevealInFinder, action: #selector(revealInFinder))
            ],
            fullWidth: [body]
        )
        page.spacing = 12
        page.setCustomSpacing(24, after: body)
        return page
    }

    private func makeMonitoringReadyPage() -> NSView {
        let body = makeBody(.setupMonitoringGrantedBody)
        let hint = makeCaption(.setupTryTyping)
        var views: [NSView] = [
            makeTitle(.setupMonitoringGrantedTitle),
            body,
            makeStatus(.setupMonitoringStatusGranted, isPositive: true),
            hint,
            makeLinkButton(.setupNotWorking, action: #selector(toggleTroubleshooting))
        ]
        var fullWidth: [NSView] = [body, hint]
        if isShowingTroubleshooting {
            let help = makeTroubleshootingBlock()
            views.append(help)
            fullWidth.append(help)
        }
        let page = makeStack(views, fullWidth: fullWidth)
        page.spacing = 12
        page.setCustomSpacing(24, after: body)
        return page
    }

    /// Not granted yet. After the first attempt the wizard itself becomes the drag guide.
    private func makeMonitoringRequestPage() -> NSView {
        let isGuide = isShowingDropGuide
        // The manual card explains itself, so the guide body is only shown for the drag route.
        let showsBody = !isGuide || !isShowingManualSteps
        let body = makeBody(isGuide ? .setupDropGuideBody : .setupMonitoringBody)
        var views: [NSView] = [makeTitle(.setupMonitoringTitle)]
        var fullWidth: [NSView] = []
        if showsBody {
            views.append(body)
            fullWidth.append(body)
        }

        if !isGuide {
            // The privacy card matters most on the first ask; the guide state needs the room.
            let privacy = makeIconCard(
                symbol: "lock.shield",
                titleKey: .setupPrivacyTitle,
                detailKey: .setupPrivacyNote
            )
            views.append(privacy)
            fullWidth.append(privacy)
        }
        views.append(makeStatus(.setupMonitoringStatusOff, isPositive: false))

        if isGuide, isShowingManualSteps {
            let manual = makeManualCard()
            views.append(manual)
            fullWidth.append(manual)
            views.append(makeLinkButton(.setupDragInstead, action: #selector(toggleManualSteps)))
        } else if isGuide {
            let watching = makeCaption(.setupMonitoringWatching)
            views.append(watching)
            fullWidth.append(watching)
            views.append(makeSecondaryButton(.setupReopenSettings, action: #selector(openInputMonitoringSettings)))
            views.append(makeLinkButton(.setupHelperAlternative, action: #selector(toggleManualSteps)))
        } else {
            views.append(makePrimaryButton(.setupEnableMonitoring, action: #selector(enableMonitoring)))
        }

        let page = makeStack(views, fullWidth: fullWidth)
        page.spacing = 12
        if showsBody {
            page.setCustomSpacing(24, after: body)
        }
        return page
    }

    /// Manual route, for when the drag does not work or the app is not listed.
    private func makeManualCard() -> NSView {
        let content = makeStack([
            makeSectionTitle(.setupManualTitle),
            makeNumberedCard([.setupManualStep1, .setupManualStep2, .setupManualStep3]),
            makeSecondaryButton(.setupOpenSystemSettings, action: #selector(openInputMonitoringSettings)),
            makeLinkButton(.setupRevealInFinder, action: #selector(revealInFinder))
        ])
        return makeCard(content)
    }

    /// Restart first: macOS only applies Input Monitoring to a fresh process.
    private func makeTroubleshootingBlock() -> NSView {
        let body = makeCaption(.setupTroubleshootingBody)
        // Stacked, not in a row: the 410pt column truncates three links on one line.
        let actions = makeStack([
            makeLinkButton(.setupRestartNow, action: #selector(relaunchApp)),
            makeLinkButton(.setupRevealInFinder, action: #selector(revealInFinder)),
            makeLinkButton(.setupOpenSystemSettings, action: #selector(openInputMonitoringSettings))
        ])
        actions.spacing = 6
        let stack = makeStack([makeSectionTitle(.setupTroubleshootingTitle), body, actions], fullWidth: [body])
        stack.spacing = 8
        return makeCard(stack)
    }
}

// MARK: - Step 3: completion

extension SetupWizardController {
    /// Compact and centred: the pet is the subject, not a second column of text.
    func makeCompletedPage() -> NSView {
        let title = makeTitle(.setupCompleteTitle)
        title.alignment = .center
        let body = makeBody(.setupCompleteBody)
        body.alignment = .center

        var views: [NSView] = [title, body, completionStage, makeChecks()]
        if !isMonitoringReady {
            let warning = makeCaption(.setupCompleteWarning)
            warning.alignment = .center
            views.append(warning)
            // Without this the warning had no way forward except 戻る.
            views.append(makeSecondaryButton(.setupSetUpMonitoring, action: #selector(showMonitoringStep)))
        }
        let hint = makeCaption(.setupCompleteHint)
        hint.alignment = .center
        views.append(hint)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [body, hint] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.setCustomSpacing(18, after: body)
        stack.setCustomSpacing(12, after: completionStage)
        return stack
    }

    /// Reports the real state; it never claims success that was not granted and verified.
    private func makeChecks() -> NSStackView {
        let petCheck = makeSymbolRow(symbol: "checkmark.circle.fill", key: .setupCheckPet, tint: .controlAccentColor)
        let monitoringCheck: NSStackView
        if isMonitoringReady {
            monitoringCheck = makeSymbolRow(
                symbol: "checkmark.circle.fill",
                key: .setupCheckMonitoring,
                tint: .controlAccentColor
            )
        } else {
            let key: LocalizationKey = isMonitoringGranted ? .setupCheckMonitoringRestart : .setupCheckMonitoringOff
            monitoringCheck = makeSymbolRow(symbol: "circle", key: key, tint: .tertiaryLabelColor)
        }
        let stack = NSStackView(views: [petCheck, monitoringCheck])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}
