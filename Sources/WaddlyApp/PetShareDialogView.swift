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
    private let postTitle: NSTextField
    private let xRow = NSView()
    private let postButton: ShareActionButton
    private let postStatusLabel: NSTextField

    init(localization: LocalizationController) {
        self.localization = localization
        loadingLabel = NSTextField(labelWithString: localization.string(for: .shareLoading))
        postTitle = NSTextField(labelWithString: localization.string(for: .sharePost))
        postButton = makeShareDialogActionButton(title: localization.string(for: .shareXCreate))
        postStatusLabel = NSTextField(labelWithString: "")
        failureLabel = NSTextField(wrappingLabelWithString: localization.string(for: .shareError))
        retryButton = makeShareDialogActionButton(title: localization.string(for: .shareRetry))
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
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
        postTitle.stringValue = localization.string(for: .sharePost)
        postButton.title = localization.string(for: .shareXCreate)
        failureLabel.stringValue = localization.string(for: .shareError)
        retryButton.title = localization.string(for: .shareRetry)
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

    /// Settles the surfaces the dialog owns. Called at init and on every appearance change, like the
    /// cards do for themselves.
    private func updateAppearance() {
        xRow.layer?.backgroundColor = shareLayerColor(.controlBackgroundColor, appearance: effectiveAppearance)
    }

    private func configureAppearance() {
        postTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        postTitle.textColor = .secondaryLabelColor
        xRow.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postRow")
        xRow.wantsLayer = true
        xRow.layer?.cornerRadius = 10
        postButton.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postButton")
        postButton.image = ShareXLogo.image(size: 18)
        postButton.imagePosition = .imageLeading
        postButton.font = .systemFont(ofSize: 12)
        postButton.isEnabled = false
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
        postStatusLabel.font = .systemFont(ofSize: 10)
        postStatusLabel.lineBreakMode = .byTruncatingTail
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
        updateAppearance()
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
        [cards, loading, failure, postTitle, xRow].forEach(addSubview)
        xRow.addSubview(postButton)
        xRow.addSubview(postStatusLabel)
        for item in [cards, loading, failure, postTitle, xRow, postButton, postStatusLabel] {
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
            widthAnchor.constraint(equalToConstant: 700), heightAnchor.constraint(equalToConstant: 410),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            cards.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            videoCard.widthAnchor.constraint(equalTo: imageCard.widthAnchor),
            cards.heightAnchor.constraint(equalToConstant: 275),
            loading.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            failure.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            failure.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            failure.widthAnchor.constraint(lessThanOrEqualTo: cards.widthAnchor, constant: -60),
            postTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            postTitle.topAnchor.constraint(equalTo: cards.bottomAnchor, constant: 17),
            xRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            xRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            xRow.topAnchor.constraint(equalTo: postTitle.bottomAnchor, constant: 7),
            xRow.heightAnchor.constraint(equalToConstant: 52),
            postButton.centerXAnchor.constraint(equalTo: xRow.centerXAnchor),
            postButton.centerYAnchor.constraint(equalTo: xRow.centerYAnchor),
            postStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: postButton.trailingAnchor, constant: 10),
            postStatusLabel.trailingAnchor.constraint(equalTo: xRow.trailingAnchor, constant: -12),
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

@MainActor private func makeShareDialogActionButton(title: String) -> ShareActionButton {
    ShareActionButton(
        title: title,
        base: .quaternaryLabelColor,
        hover: .selectedContentBackgroundColor.withAlphaComponent(0.22),
        pressed: .selectedContentBackgroundColor.withAlphaComponent(0.45)
    )
}
