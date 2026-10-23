import AppKit

/// The two files the share dialog generates.
enum PetShareAssetKind: Hashable {
    case video
    case image
}

/// The dialog's user-visible state. The controller owns which state is current; the view only renders it.
@MainActor
final class PetShareDialogView: NSView {
    var onCopySprite: (() -> Void)?
    var onCopyMovie: (() -> Void)?
    var onOpenX: (() -> Void)?
    var onRetry: (() -> Void)?
    private let localization: LocalizationController
    private let moviePreview = PetMoviePreviewView()
    private let spriteImage = NSImageView()
    private let videoCard: PetShareCardView
    private let imageCard: PetShareCardView
    private let cards: NSStackView
    private let loading = NSStackView()
    private let loadingLabel: NSTextField
    private let spinner = NSProgressIndicator()
    private let failure = NSStackView()
    private let failureLabel: NSTextField
    private let retryButton: ShareActionButton
    private let footerSeparator = NSBox()
    private let xRow = NSView()
    private let postButton: ShareActionButton
    private let postStatusLabel: NSTextField

    init(localization: LocalizationController) {
        self.localization = localization
        loadingLabel = NSTextField(labelWithString: localization.string(for: .shareLoading))
        postButton = ShareActionButton.primaryAction(title: localization.string(for: .shareXCreate))
        postStatusLabel = NSTextField(labelWithString: "")
        failureLabel = NSTextField(wrappingLabelWithString: localization.string(for: .shareError))
        retryButton = ShareActionButton.secondaryAction(title: localization.string(for: .shareRetry))
        videoCard = PetShareCardView(
            copyButtonIdentifier: "share.copyVideo",
            statusIdentifier: "share.videoStatus",
            title: localization.string(for: .shareVideo),
            copyTitle: localization.string(for: .shareCopyVideo),
            copyHelp: localization.string(for: .shareCopyHelpVideo),
            detail: localization.string(for: .shareVideoDetail),
            preview: moviePreview
        )
        imageCard = PetShareCardView(
            copyButtonIdentifier: "share.copyImage",
            statusIdentifier: "share.imageStatus",
            title: localization.string(for: .shareSprite),
            copyTitle: localization.string(for: .shareCopyImage),
            copyHelp: localization.string(for: .shareCopyHelpImage),
            detail: localization.string(for: .shareSpriteDetail),
            preview: spriteImage
        )
        cards = NSStackView(views: [videoCard, imageCard])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureAppearance()
        installSubviews()
        installActions()
        installConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWorking() {
        spinner.startAnimation(nil)
        loading.isHidden = false
        failure.isHidden = true
        cards.isHidden = true
        postButton.isEnabled = false
        videoCard.setStatus("", failed: false)
        imageCard.setStatus("", failed: false)
        postStatusLabel.stringValue = ""
    }

    func showAssets(spriteURL: URL, movieURL: URL, moviePoster: NSImage?) {
        spriteImage.image = NSImage(contentsOf: spriteURL)
        moviePreview.loadMovie(at: movieURL, poster: moviePoster)
        spinner.stopAnimation(nil)
        loading.isHidden = true
        failure.isHidden = true
        cards.isHidden = false
        postButton.isEnabled = true
    }

    func showFailure() {
        spinner.stopAnimation(nil)
        loading.isHidden = true
        cards.isHidden = true
        postButton.isEnabled = false
        failure.isHidden = false
        Self.announce(failureLabel)
    }

    /// Shows what one copy actually did, next to the asset it copied.
    func showCopyResult(_ text: String, failed: Bool, for asset: PetShareAssetKind) {
        let card = asset == .video ? videoCard : imageCard
        card.setStatus(text, failed: failed)
        Self.announce(card.statusLabel)
    }

    /// Shows why the post composer did not open, or clears the message.
    func showXOpenFailure(_ text: String?) {
        postStatusLabel.stringValue = text ?? ""
        postStatusLabel.textColor = .systemRed
        if text != nil {
            Self.announce(postStatusLabel)
        }
    }

    func refreshLocalization() {
        videoCard.setTitle(localization.string(for: .shareVideo))
        imageCard.setTitle(localization.string(for: .shareSprite))
        videoCard.setDetail(localization.string(for: .shareVideoDetail))
        imageCard.setDetail(localization.string(for: .shareSpriteDetail))
        videoCard.setCopyTitle(localization.string(for: .shareCopyVideo))
        imageCard.setCopyTitle(localization.string(for: .shareCopyImage))
        loadingLabel.stringValue = localization.string(for: .shareLoading)
        postButton.setPrimaryTitle(localization.string(for: .shareXCreate))
        failureLabel.stringValue = localization.string(for: .shareError)
        retryButton.title = localization.string(for: .shareRetry)
        retryButton.invalidateIntrinsicContentSize()
        refreshAccessibilityLabels()
    }

    func stopPlayback() {
        moviePreview.stop()
    }

    @objc private func copySprite() {
        onCopySprite?()
    }

    @objc private func copyMovie() {
        onCopyMovie?()
    }

    @objc private func openX() {
        onOpenX?()
    }

    @objc private func retry() {
        onRetry?()
    }

    /// Builds the dialog's static surfaces and identifiers once. The footer separator is an `NSBox`,
    /// so it follows the system appearance without a manual color refresh.
    private func configureAppearance() {
        xRow.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postRow")
        postButton.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postButton")
        postButton.image = ShareXLogo.image(size: 18)
        postButton.imagePosition = .imageLeading
        postButton.isEnabled = false
        footerSeparator.boxType = .separator
        spriteImage.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.spritePreview")
        spriteImage.imageScaling = .scaleProportionallyUpOrDown
        spriteImage.imageAlignment = .alignCenter
        spriteImage.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spriteImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fillEqually
        cards.spacing = 14
        cards.isHidden = true
        loading.orientation = .horizontal
        loading.alignment = .centerY
        loading.spacing = 9
        spinner.style = .spinning
        spinner.controlSize = .small
        loading.addArrangedSubview(spinner)
        loading.addArrangedSubview(loadingLabel)
        loadingLabel.textColor = .secondaryLabelColor
        postStatusLabel.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postStatus")
        postStatusLabel.font = .systemFont(ofSize: 11)
        postStatusLabel.maximumNumberOfLines = 2
        postStatusLabel.lineBreakMode = .byWordWrapping
        postStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        failure.orientation = .vertical
        failure.alignment = .centerX
        failure.spacing = 10
        failure.isHidden = true
        failureLabel.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.failure")
        failureLabel.alignment = .center
        failureLabel.maximumNumberOfLines = 3
        retryButton.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.retry")
        failure.addArrangedSubview(failureLabel)
        failure.addArrangedSubview(retryButton)
    }

    private func refreshAccessibilityLabels() {
        videoCard.copyButton.setAccessibilityLabel(localization.string(for: .shareCopyHelpVideo))
        videoCard.copyButton.setAccessibilityHelp(localization.string(for: .shareCopyHelpVideo))
        imageCard.copyButton.setAccessibilityLabel(localization.string(for: .shareCopyHelpImage))
        imageCard.copyButton.setAccessibilityHelp(localization.string(for: .shareCopyHelpImage))
        postButton.setAccessibilityLabel(localization.string(for: .shareXCreate))
        postButton.setAccessibilityHelp(localization.string(for: .shareXHelp))
        moviePreview.setAccessibilityLabels(
            play: localization.string(for: .sharePlayPreview),
            pause: localization.string(for: .sharePausePreview)
        )
    }

    private func installSubviews() {
        [cards, loading, failure, footerSeparator, xRow].forEach(addSubview)
        xRow.addSubview(postButton)
        xRow.addSubview(postStatusLabel)
        for item in [cards, loading, failure, footerSeparator, xRow, postButton, postStatusLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func installActions() {
        videoCard.copyButton.target = self
        videoCard.copyButton.action = #selector(copyMovie)
        imageCard.copyButton.target = self
        imageCard.copyButton.action = #selector(copySprite)
        postButton.target = self
        postButton.action = #selector(openX)
        retryButton.target = self
        retryButton.action = #selector(retry)
        refreshAccessibilityLabels()
    }

    private func installConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 700), heightAnchor.constraint(equalToConstant: 380),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutMetrics.contentInset),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutMetrics.contentInset),
            cards.topAnchor.constraint(equalTo: topAnchor, constant: LayoutMetrics.contentInset),
            videoCard.widthAnchor.constraint(equalTo: imageCard.widthAnchor),
            cards.heightAnchor.constraint(equalToConstant: 275),
            loading.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            failure.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            failure.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            failure.widthAnchor.constraint(lessThanOrEqualTo: cards.widthAnchor, constant: -60),
            footerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),
            footerSeparator.bottomAnchor.constraint(equalTo: xRow.topAnchor, constant: -LayoutMetrics.footerInset),
            cards.bottomAnchor.constraint(
                lessThanOrEqualTo: footerSeparator.topAnchor,
                constant: -LayoutMetrics.sectionGap
            ),
            xRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutMetrics.contentInset),
            xRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutMetrics.contentInset),
            xRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -LayoutMetrics.footerInset),
            xRow.heightAnchor.constraint(equalToConstant: LayoutMetrics.actionHeight),
            postButton.centerXAnchor.constraint(equalTo: xRow.centerXAnchor),
            postButton.centerYAnchor.constraint(equalTo: xRow.centerYAnchor),
            postStatusLabel.leadingAnchor.constraint(equalTo: xRow.leadingAnchor),
            postStatusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: postButton.leadingAnchor,
                constant: -LayoutMetrics.actionGap
            ),
            postStatusLabel.centerYAnchor.constraint(equalTo: xRow.centerYAnchor)
        ])
    }

    private static func announce(_ label: NSTextField) {
        guard !label.stringValue.isEmpty else { return }
        NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [
            .announcement: label.stringValue,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
