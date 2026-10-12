import AppKit

extension SetupWizardController {
    func buildWindow() {
        // A PNG can be dropped anywhere in the window, which is what the hint under the options
        // promises. The preview pane registers as well; being the deeper view it keeps its own
        // highlight and takes the drops that land on it.
        let contentView = PetImageDropView()
        contentView.idleBorderWidth = 0
        contentView.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
        }
        let bodyContainer = NSView()
        let footer = makeFooter()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        leftContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stepIndicator)
        contentView.addSubview(bodyContainer)
        contentView.addSubview(footer)
        bodyContainer.addSubview(leftContainer)
        bodyContainer.addSubview(previewPane)

        activateLayout(contentView: contentView, footer: footer, bodyContainer: bodyContainer)

        previewPane.configure(localization: localization, showsControls: true)
        previewPane.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
        }
        previewPane.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buildCompletionStage()

        bindPermission()
        window?.contentView = contentView
        renderCurrentStep()
    }

    func buildCompletionStage() {
        completionStage.translatesAutoresizingMaskIntoConstraints = false
        completionStage.wantsLayer = true
        completionStage.layer?.cornerRadius = SetupMetrics.previewCornerRadius
        completionStage.layer?.borderWidth = 1
        completionStage.layer?.borderColor = NSColor.separatorColor.cgColor
        completionStage.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        completionPetView.translatesAutoresizingMaskIntoConstraints = false
        completionPetView.imageScaling = .scaleProportionallyUpOrDown
        completionStage.addSubview(completionPetView)
        NSLayoutConstraint.activate([
            completionStage.widthAnchor.constraint(equalToConstant: 220),
            completionStage.heightAnchor.constraint(equalToConstant: 144),
            completionPetView.centerXAnchor.constraint(equalTo: completionStage.centerXAnchor),
            completionPetView.centerYAnchor.constraint(equalTo: completionStage.centerYAnchor),
            completionPetView.widthAnchor.constraint(equalToConstant: 116),
            completionPetView.heightAnchor.constraint(equalToConstant: 116)
        ])
    }

    func activateLayout(contentView: NSView, footer: NSStackView, bodyContainer: NSView) {
        let leftLeading = leftContainer.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor)
        let leftCenter = leftContainer.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor)
        // One always-active width; the compact completion screen only changes its constant.
        let leftWidth = leftContainer.widthAnchor.constraint(equalToConstant: SetupMetrics.leftColumnWidth)
        leftLeadingConstraint = leftLeading
        leftCenterConstraint = leftCenter
        leftWidthConstraint = leftWidth

        // Horizontal pane constraints are switched off for the compact screen, otherwise the
        // hidden pane still forces the window to grow.
        let previewLeading = previewPane.leadingAnchor.constraint(
            equalTo: leftContainer.trailingAnchor,
            constant: SetupMetrics.columnGap
        )
        let previewTrailing = previewPane.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor)
        let previewWidth = previewPane.widthAnchor.constraint(equalToConstant: SetupMetrics.rightColumnWidth)
        previewWidthConstraint = previewWidth
        previewHorizontalConstraints = [previewLeading, previewTrailing, previewWidth]

        NSLayoutConstraint.activate([
            previewWidth,
            stepIndicator.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: SetupMetrics.sideInset
            ),
            stepIndicator.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -SetupMetrics.sideInset
            ),
            stepIndicator.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: SetupMetrics.topInset
            ),

            bodyContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: SetupMetrics.sideInset
            ),
            bodyContainer.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -SetupMetrics.sideInset
            ),
            bodyContainer.topAnchor.constraint(equalTo: stepIndicator.bottomAnchor, constant: 16),
            bodyContainer.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -20),

            leftLeading,
            leftContainer.widthAnchor.constraint(equalToConstant: SetupMetrics.leftColumnWidth),
            leftContainer.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            leftContainer.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            previewPane.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            previewPane.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SetupMetrics.sideInset),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SetupMetrics.sideInset),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SetupMetrics.bottomInset),
            footer.heightAnchor.constraint(equalToConstant: SetupMetrics.footerHeight)
        ])
    }

    func makeFooter() -> NSStackView {
        backButton.title = localizedString(.setupBack)
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.bezelStyle = .rounded
        nextButton.font = .systemFont(ofSize: 13, weight: .medium)
        nextButton.keyEquivalent = "\r"
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        laterButton.title = localizedString(.setupLater)
        laterButton.target = self
        laterButton.action = #selector(deferMonitoring)
        laterButton.isBordered = false
        laterButton.contentTintColor = .controlAccentColor
        laterButton.font = .systemFont(ofSize: 13)
        laterButton.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [backButton, NSView(), laterButton, nextButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    /// All step changes funnel through here so the saved step always matches the screen.
    func setStep(_ step: Step?) {
        currentStep = step ?? .pet
        onStepChange(step?.rawValue)
        renderCurrentStep()
    }
}
