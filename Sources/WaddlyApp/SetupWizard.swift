import AppKit
import UniformTypeIdentifiers

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate {
    private let prompt: String
    private let onImportImage: @MainActor (URL) -> Bool
    private let hasInputMonitoringPermission: @MainActor () -> Bool
    private let requestInputMonitoringPermission: @MainActor () -> Bool
    private let onClose: @MainActor () -> Void
    private let progressLabel = NSTextField(labelWithString: "")
    private let pageContainer = NSView()
    private let promptStatusLabel = NSTextField(labelWithString: "")
    private let imageStatusLabel = NSTextField(labelWithString: "")
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private var currentStep = 0

    init(
        onImportImage: @escaping @MainActor (URL) -> Bool,
        hasInputMonitoringPermission: @escaping @MainActor () -> Bool,
        requestInputMonitoringPermission: @escaping @MainActor () -> Bool,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.prompt = Self.loadPrompt()
        self.onImportImage = onImportImage
        self.hasInputMonitoringPermission = hasInputMonitoringPermission
        self.requestInputMonitoringPermission = requestInputMonitoringPermission
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = localizedString("setup.windowTitle")
        window.minSize = NSSize(width: 650, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildWindow()
    }

    required init?(coder: NSCoder) { nil }

    func refreshPermissionStatus() {
        permissionStatusLabel.stringValue = localizedString(
            hasInputMonitoringPermission() ? "setup.permissionGranted" : "setup.permissionRequired"
        )
        settingsButton.isHidden = hasInputMonitoringPermission()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

extension SetupWizardController {
    private func buildWindow() {
        let contentView = NSView()
        let navigation = makeNavigation()
        let stack = makeStack([progressLabel, pageContainer, navigation])
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            pageContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pageContainer.heightAnchor.constraint(equalToConstant: 440),
            navigation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            navigation.heightAnchor.constraint(equalToConstant: 32)
        ])
        window?.contentView = contentView
        renderCurrentStep()
    }

    private func makeNavigation() -> NSStackView {
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.setAccessibilityLabel(localizedString("setup.back"))

        let laterButton = NSButton(
            title: localizedString("setup.later"),
            target: self,
            action: #selector(closeWizard)
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nextButton.target = self
        nextButton.action = #selector(goNext)

        let navigation = makeStack([backButton, laterButton, spacer, nextButton])
        navigation.orientation = .horizontal
        navigation.alignment = .centerY
        navigation.distribution = .fill
        return navigation
    }

    private func renderCurrentStep() {
        let page: NSView
        switch currentStep {
        case 0: page = makePromptPage()
        case 1: page = makeImagePage()
        default: page = makePermissionPage()
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.subviews.forEach { $0.removeFromSuperview() }
        pageContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            page.widthAnchor.constraint(equalTo: pageContainer.widthAnchor),
            page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            page.bottomAnchor.constraint(lessThanOrEqualTo: pageContainer.bottomAnchor)
        ])
        progressLabel.stringValue = String(
            format: localizedString("setup.progress"),
            currentStep + 1
        )
        backButton.title = localizedString("setup.back")
        backButton.isEnabled = currentStep > 0
        nextButton.title = localizedString(currentStep == 2 ? "setup.finish" : "setup.next")
        window?.defaultButtonCell = nextButton.cell as? NSButtonCell
        if currentStep == 2 { refreshPermissionStatus() }
    }

}

extension SetupWizardController {
    private func makePromptPage() -> NSView {
        let title = makeTitle("setup.promptTitle")
        let description = makeDescription("setup.promptDescription")
        let promptView = NSTextView()
        promptView.isEditable = false
        promptView.isSelectable = true
        promptView.string = prompt
        promptView.font = .systemFont(ofSize: 13)
        promptView.textContainerInset = NSSize(width: 12, height: 12)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = promptView
        scrollView.heightAnchor.constraint(equalToConstant: 240).isActive = true

        let copyButton = NSButton(
            title: localizedString("setup.copyPrompt"),
            target: self,
            action: #selector(copyPrompt)
        )
        copyButton.isEnabled = !prompt.isEmpty
        let chatGPTButton = NSButton(
            title: localizedString("setup.openChatGPT"),
            target: self,
            action: #selector(openChatGPT)
        )
        let actions = makeStack([copyButton, chatGPTButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        promptStatusLabel.stringValue = prompt.isEmpty ? localizedString("setup.promptUnavailable") : ""
        return makeStack([title, description, scrollView, actions, promptStatusLabel])
    }

    private func makeImagePage() -> NSView {
        let title = makeTitle("setup.imageTitle")
        let description = makeDescription("setup.imageDescription")
        let dropZone = PetImageDropView(frame: .zero)
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        dropZone.heightAnchor.constraint(equalToConstant: 180).isActive = true
        dropZone.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
        }

        let dropLabel = NSTextField(wrappingLabelWithString: localizedString("setup.imageDrop"))
        dropLabel.translatesAutoresizingMaskIntoConstraints = false
        dropLabel.alignment = .center
        dropLabel.setAccessibilityLabel(localizedString("setup.imageDrop"))
        let chooseButton = NSButton(
            title: localizedString("setup.chooseImage"),
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
        imageStatusLabel.stringValue = localizedString("setup.imageOptional")
        return makeStack([title, description, dropZone, imageStatusLabel])
    }

    private func makePermissionPage() -> NSView {
        let title = makeTitle("setup.permissionTitle")
        let description = makeDescription("setup.permissionDescription")
        let privacyNote = makeDescription("setup.privacyNote")
        let requestButton = NSButton(
            title: localizedString("setup.requestPermission"),
            target: self,
            action: #selector(requestPermission)
        )
        settingsButton.title = localizedString("setup.openSettings")
        settingsButton.target = self
        settingsButton.action = #selector(openInputMonitoringSettings)
        let actions = makeStack([requestButton, settingsButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        return makeStack([title, description, privacyNote, permissionStatusLabel, actions])
    }

    private func makeTitle(_ key: String) -> NSTextField {
        let label = NSTextField(labelWithString: localizedString(key))
        label.font = .boldSystemFont(ofSize: 21)
        return label
    }

    private func makeDescription(_ key: String) -> NSTextField {
        NSTextField(wrappingLabelWithString: localizedString(key))
    }

    private func makeStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

}

extension SetupWizardController {
    private func importImage(from url: URL) {
        guard onImportImage(url) else {
            imageStatusLabel.stringValue = localizedString("setup.imageNotImported")
            return
        }
        imageStatusLabel.stringValue = String(
            format: localizedString("setup.imageImported"),
            url.lastPathComponent
        )
    }

    @objc private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localizedString("setup.chooseImage")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(from: url)
    }

    @objc private func copyPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(prompt, forType: .string)
        let statusKey = copied ? "setup.promptCopied" : "setup.promptCopyFailed"
        promptStatusLabel.stringValue = localizedString(statusKey)
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
        guard currentStep < 2 else {
            window?.close()
            return
        }
        currentStep += 1
        renderCurrentStep()
    }

    @objc private func closeWizard() {
        window?.close()
    }

    private static func loadPrompt() -> String {
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("ja") == true ? "ja" : "en"
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("prompts/\(language).md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let start = markdown.range(of: "```text\n"),
              let end = markdown[start.upperBound...].range(of: "```") else {
            return ""
        }
        return String(markdown[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AppDelegate {
    @objc func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardController(
                onImportImage: { [weak self] in self?.importPetImage(from: $0) ?? false },
                hasInputMonitoringPermission: { [weak self] in self?.monitor.permissionGranted ?? false },
                requestInputMonitoringPermission: { [weak self] in
                    guard let self else { return false }
                    let granted = self.monitor.requestPermission()
                    if granted && !self.isPaused { self.startMonitoring() }
                    return granted
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    self.defaults.set(true, forKey: "setupWizardSeen")
                    if self.monitor.permissionGranted && !self.isPaused { self.startMonitoring() }
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWizardController?.showWindow(nil)
        setupWizardController?.window?.center()
    }
}
