import AppKit
import UniformTypeIdentifiers

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate {
    let localization: LocalizationController
    let promptResourcesURL: URL?
    var prompt: String {
        SetupWizardController.loadPrompt(for: localization, resourcesAt: promptResourcesURL)
    }

    private let onImportImage: @MainActor (URL) async -> Bool
    private let hasCustomImage: @MainActor () -> Bool
    private let hasInputMonitoringPermission: @MainActor () -> Bool
    private let requestInputMonitoringPermission: @MainActor () -> Bool
    private let onClose: @MainActor () -> Void
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let pageContainer = NSView()
    private let copyPromptButton = NSButton(title: "", target: nil, action: nil)
    private let imageStatusLabel = NSTextField(labelWithString: "")
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private var appDragCard: NSView?
    private let requestPermissionButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let skipButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private var currentStep = 0

    init(
        localization: LocalizationController,
        promptResourcesURL: URL? = Bundle.main.resourceURL,
        onImportImage: @escaping @MainActor (URL) async -> Bool,
        hasCustomImage: @escaping @MainActor () -> Bool,
        hasInputMonitoringPermission: @escaping @MainActor () -> Bool,
        requestInputMonitoringPermission: @escaping @MainActor () -> Bool,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.localization = localization
        self.promptResourcesURL = promptResourcesURL
        self.onImportImage = onImportImage
        self.hasCustomImage = hasCustomImage
        self.hasInputMonitoringPermission = hasInputMonitoringPermission
        self.requestInputMonitoringPermission = requestInputMonitoringPermission
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = localizedString(.setupWindowTitle)
        window.minSize = NSSize(width: 680, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildWindow()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    func refreshPermissionStatus() {
        let isGranted = hasInputMonitoringPermission()
        let statusKey: LocalizationKey = isGranted ? .setupPermissionGranted : .setupPermissionRequired
        permissionStatusLabel.stringValue = localizedString(statusKey)
        appDragCard?.isHidden = isGranted
        requestPermissionButton.isHidden = isGranted
        settingsButton.isHidden = isGranted
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

extension SetupWizardController {
    private func buildWindow() {
        let contentView = NSView()
        let navigation = makeNavigation()
        let progressRow = makeProgressRow()
        let stack = makeStack([progressRow, pageContainer, navigation])
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            progressRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pageContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pageContainer.heightAnchor.constraint(equalToConstant: 300),
            navigation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            navigation.heightAnchor.constraint(equalToConstant: 32)
        ])
        window?.contentView = contentView
        renderCurrentStep()
    }

    private func makeProgressRow() -> NSStackView {
        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 3
        progressIndicator.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [progressLabel, NSView(), progressIndicator])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeNavigation() -> NSStackView {
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.setAccessibilityLabel(localizedString(.setupBack))

        skipButton.title = localizedString(.setupSkip)
        skipButton.target = self
        skipButton.action = #selector(skipPrompt)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nextButton.target = self
        nextButton.action = #selector(goNext)

        let navigation = makeStack([backButton, skipButton, spacer, nextButton])
        navigation.orientation = .horizontal
        navigation.alignment = .centerY
        navigation.distribution = .fill
        return navigation
    }

    func renderCurrentStep() {
        let page: NSView = switch currentStep {
        case 0: makePromptPage()
        case 1: makeImagePage()
        default: makePermissionPage()
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.subviews.forEach { $0.removeFromSuperview() }
        pageContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            page.widthAnchor.constraint(equalTo: pageContainer.widthAnchor),
            page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        ])
        progressLabel.stringValue = String(
            format: localizedString(.setupProgress),
            currentStep + 1
        )
        progressIndicator.doubleValue = Double(currentStep + 1)
        backButton.title = localizedString(.setupBack)
        backButton.setAccessibilityLabel(localizedString(.setupBack))
        backButton.isEnabled = currentStep > 0
        skipButton.isHidden = currentStep != 0
        skipButton.title = localizedString(.setupSkip)
        nextButton.title = localizedString(currentStep == 2 ? .setupFinish : .setupNext)
        nextButton.isEnabled = currentStep != 1 || hasCustomImage()
        window?.defaultButtonCell = nextButton.cell as? NSButtonCell
        if currentStep == 2 {
            refreshPermissionStatus()
        }
    }
}

extension SetupWizardController {
    private func makePromptPage() -> NSView {
        let title = makeTitle(.setupPromptTitle)
        let description = makeDescription(.setupPromptDescription)
        let promptCard = makeInfoCard(
            symbol: "doc.text",
            titleKey: .setupPromptCardTitle,
            detailKey: .setupPromptCardDescription
        )
        copyPromptButton.title = localizedString(.setupCopyPrompt)
        copyPromptButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyPromptButton.imagePosition = .imageLeading
        copyPromptButton.target = self
        copyPromptButton.action = #selector(copyPrompt)
        copyPromptButton.isEnabled = !prompt.isEmpty
        let chatGPTButton = NSButton(
            title: localizedString(.setupOpenChatGPT),
            target: self,
            action: #selector(openChatGPT)
        )
        chatGPTButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        chatGPTButton.imagePosition = .imageLeading
        let actions = makeStack([copyPromptButton, chatGPTButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        return makeStack([title, description, promptCard, actions], fullWidth: [description, promptCard])
    }

    private func makeImagePage() -> NSView {
        let title = makeTitle(.setupImageTitle)
        let description = makeDescription(.setupImageDescription)
        let dropZone = PetImageDropView(frame: .zero)
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        dropZone.layer?.cornerRadius = 12
        dropZone.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let dropLabel = NSTextField(wrappingLabelWithString: localizedString(.setupImageDrop))
        dropLabel.translatesAutoresizingMaskIntoConstraints = false
        dropLabel.alignment = .center
        dropLabel.setAccessibilityLabel(localizedString(.setupImageDrop))
        let chooseButton = NSButton(
            title: localizedString(.setupChooseImage),
            target: self,
            action: #selector(chooseImage)
        )
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        dropZone.addSubview(dropLabel)
        dropZone.addSubview(chooseButton)
        NSLayoutConstraint.activate([
            dropLabel.centerXAnchor.constraint(equalTo: dropZone.centerXAnchor),
            dropLabel.centerYAnchor.constraint(equalTo: dropZone.centerYAnchor, constant: -22),
            dropLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dropZone.leadingAnchor, constant: 16),
            dropLabel.trailingAnchor.constraint(lessThanOrEqualTo: dropZone.trailingAnchor, constant: -16),
            chooseButton.centerXAnchor.constraint(equalTo: dropZone.centerXAnchor),
            chooseButton.topAnchor.constraint(equalTo: dropLabel.bottomAnchor, constant: 14)
        ])
        imageStatusLabel.font = .systemFont(ofSize: 13)
        imageStatusLabel.textColor = .secondaryLabelColor
        imageStatusLabel.stringValue = localizedString(
            hasCustomImage() ? .setupImageAlreadyConfigured : .setupImageRequired
        )
        let content = makeStack(
            [title, description, dropZone, imageStatusLabel],
            fullWidth: [description, dropZone, imageStatusLabel]
        )
        return makeImageDropTarget(content)
    }

    private func makeImageDropTarget(_ content: NSView) -> NSView {
        let dropTarget = PetImageDropView(frame: .zero)
        dropTarget.translatesAutoresizingMaskIntoConstraints = false
        dropTarget.layer?.cornerRadius = 14
        dropTarget.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
        }
        dropTarget.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: dropTarget.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: dropTarget.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: dropTarget.topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: dropTarget.bottomAnchor, constant: -16)
        ])
        return dropTarget
    }

    private func makePermissionPage() -> NSView {
        let title = makeTitle(.setupPermissionTitle)
        let description = makeDescription(.setupPermissionDescription)
        let privacyNote = makeDescription(.setupPrivacyNote)
        let appDragCard = makeDraggableAppCard()
        self.appDragCard = appDragCard
        requestPermissionButton.title = localizedString(.setupRequestPermission)
        requestPermissionButton.target = self
        requestPermissionButton.action = #selector(requestPermission)
        settingsButton.title = localizedString(.setupOpenSettings)
        settingsButton.target = self
        settingsButton.action = #selector(openInputMonitoringSettings)
        permissionStatusLabel.font = .systemFont(ofSize: 13)
        permissionStatusLabel.textColor = .secondaryLabelColor
        let actions = makeStack([requestPermissionButton, settingsButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        let page = makeStack(
            [title, description, appDragCard, privacyNote, permissionStatusLabel, actions],
            fullWidth: [description, appDragCard, privacyNote, permissionStatusLabel]
        )
        page.spacing = 8
        return page
    }
}

extension SetupWizardController {
    private func importImage(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            let imported = await onImportImage(url)
            imageStatusLabel.stringValue = imported
                ? String(format: localizedString(.setupImageImported), url.lastPathComponent)
                : localizedString(.setupImageNotImported)
            if currentStep == 1 {
                nextButton.isEnabled = hasCustomImage()
            }
        }
    }

    @objc private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localizedString(.setupChooseImage)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(from: url)
    }

    @objc private func copyPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else {
            NSSound.beep()
            return
        }
        copyPromptButton.title = localizedString(.setupPromptCopiedShort)
        copyPromptButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
    }

    @objc private func openChatGPT() {
        guard let url = URL(string: "https://chatgpt.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func requestPermission() {
        _ = requestInputMonitoringPermission()
        refreshPermissionStatus()
    }

    @objc private func openInputMonitoringSettings() {
        let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        guard let url = URL(string: settingsURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func goBack() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        renderCurrentStep()
    }

    @objc private func goNext() {
        guard currentStep != 1 || hasCustomImage() else { return }
        guard currentStep < 2 else {
            window?.close()
            return
        }
        currentStep += 1
        renderCurrentStep()
    }

    @objc private func skipPrompt() {
        guard currentStep == 0 else { return }
        currentStep = 1
        renderCurrentStep()
    }
}

extension AppDelegate {
    @objc func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardController(
                localization: localization,
                onImportImage: { [weak self] in await self?.importPetImage(from: $0) ?? false },
                hasCustomImage: { [weak self] in self?.hasCompletePetImageSet ?? false },
                hasInputMonitoringPermission: { [weak self] in self?.monitor.permissionGranted ?? false },
                requestInputMonitoringPermission: { [weak self] in
                    guard let self else { return false }
                    let granted = monitor.requestPermission()
                    if granted, !isPaused {
                        startMonitoring()
                    }
                    return granted
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    if !hasCompletePetImageSet {
                        settings.removeSetupWizardSeen()
                    } else {
                        settings.setupWizardSeen = true
                    }
                    if hasCompletePetImageSet, monitor.permissionGranted, !isPaused {
                        startMonitoring()
                    }
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWizardController?.showWindow(nil)
        setupWizardController?.window?.center()
    }
}
