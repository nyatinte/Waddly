import AppKit

@MainActor
final class PetShareDialogView: NSView {
    var onCopySprite: (() -> Void)?
    var onCopyMovie: (() -> Void)?
    var onOpenX: (() -> Void)?
    private let localization: LocalizationController
    private let moviePreview = PetMoviePreviewView()
    private let spriteImage = NSImageView()
    private let loading = NSStackView()
    private let loadingLabel: NSTextField
    private let movieTitleLabel: NSTextField
    private let spriteTitleLabel: NSTextField
    private let movieCopyButton: NSButton
    private let spriteCopyButton: NSButton
    private let cards: NSStackView
    private var errorLabel: NSTextField?
    private var movieWasCopied = false
    private var spriteWasCopied = false
    private let spinner = NSProgressIndicator()
    private let postTitle: NSTextField
    private let xRow = NSView()
    private let xIdentity = ShareXIdentityView()
    private let xMark = ShareXLogoView()
    private let xLabel: NSTextField

    init(localization: LocalizationController) {
        self.localization = localization
        loadingLabel = NSTextField(labelWithString: localization.string(for: .shareLoading))
        movieTitleLabel = NSTextField(labelWithString: localization.string(for: .shareVideo))
        spriteTitleLabel = NSTextField(labelWithString: localization.string(for: .shareSprite))
        movieCopyButton = NSButton(title: localization.string(for: .shareCopy), target: nil, action: nil)
        spriteCopyButton = NSButton(title: localization.string(for: .shareCopy), target: nil, action: nil)
        postTitle = NSTextField(labelWithString: localization.string(for: .sharePost))
        xLabel = NSTextField(labelWithString: localization.string(for: .shareXCreate))
        let videoCard = Self.makeCard(
            titleLabel: movieTitleLabel, copyButton: movieCopyButton,
            preview: moviePreview, detail: "MP4"
        )
        let spriteCard = Self.makeCard(
            titleLabel: spriteTitleLabel, copyButton: spriteCopyButton,
            preview: spriteImage, detail: "PNG · 9"
        )
        cards = NSStackView(views: [videoCard, spriteCard])
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

    func showAssets(spriteURL: URL, movieURL: URL, moviePoster: NSImage?) {
        spriteImage.image = NSImage(contentsOf: spriteURL)
        moviePreview.loadMovie(at: movieURL, poster: moviePoster)
        loading.isHidden = true
        cards.isHidden = false
    }

    func showError() {
        spinner.stopAnimation(nil)
        loading.arrangedSubviews.forEach { loading.removeArrangedSubview($0); $0.removeFromSuperview() }
        let label = NSTextField(wrappingLabelWithString: localization.string(for: .shareError))
        errorLabel = label
        loading.addArrangedSubview(label)
    }

    func refreshLocalization() {
        movieTitleLabel.stringValue = localization.string(for: .shareVideo)
        spriteTitleLabel.stringValue = localization.string(for: .shareSprite)
        loadingLabel.stringValue = localization.string(for: .shareLoading)
        movieCopyButton.title = localization.string(for: movieWasCopied ? .shareCopied : .shareCopy)
        spriteCopyButton.title = localization.string(for: spriteWasCopied ? .shareCopied : .shareCopy)
        postTitle.stringValue = localization.string(for: .sharePost)
        xLabel.stringValue = localization.string(for: .shareXCreate)
        xMark.setAccessibilityLabel(localization.string(for: .shareXCreate))
        errorLabel?.stringValue = localization.string(for: .shareError)
    }

    func stopPlayback() {
        moviePreview.stop()
    }

    func didCopySprite() {
        spriteWasCopied = true
        spriteCopyButton.title = localization.string(for: .shareCopied)
    }

    func didCopyMovie() {
        movieWasCopied = true
        movieCopyButton.title = localization.string(for: .shareCopied)
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

    private func configureAppearance() {
        postTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        postTitle.textColor = .secondaryLabelColor
        xRow.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postRow")
        xIdentity.addArrangedSubview(xMark)
        xIdentity.addArrangedSubview(xLabel)
        xRow.wantsLayer = true
        xRow.layer?.backgroundColor = NSColor(calibratedRed: 0.933, green: 0.933, blue: 0.945, alpha: 1).cgColor
        xRow.layer?.cornerRadius = 10
        xIdentity.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.xIdentity")
        xIdentity.orientation = .horizontal
        xIdentity.alignment = .centerY
        xIdentity.spacing = 6
        xMark.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.xLogo")
        spriteImage.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.spritePreview")
        xLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        spriteImage.imageScaling = .scaleProportionallyUpOrDown
        spriteImage.imageAlignment = .alignCenter
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fillEqually
        cards.spacing = 14
        spriteImage.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spriteImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        loading.orientation = .horizontal
        loading.alignment = .centerY
        loading.spacing = 9
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        loading.addArrangedSubview(spinner)
        loading.addArrangedSubview(loadingLabel)
        loadingLabel.textColor = .secondaryLabelColor
        cards.isHidden = true
    }

    private func installSubviews() {
        [cards, loading, postTitle, xRow].forEach(addSubview)
        xRow.addSubview(xIdentity)
        for item in [cards, loading, postTitle, xRow, xIdentity, xMark, xLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func installActions() {
        movieCopyButton.target = self
        movieCopyButton.action = #selector(copyMovie)
        spriteCopyButton.target = self
        spriteCopyButton.action = #selector(copySprite)
        for view in [xMark, xLabel] {
            view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openX)))
        }
        xMark.setAccessibilityRole(.button)
        xMark.setAccessibilityLabel(localization.string(for: .shareXCreate))
        xLabel.setAccessibilityRole(.button)
    }

    private func installConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 700), heightAnchor.constraint(equalToConstant: 410),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            cards.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            cards.arrangedSubviews[0].widthAnchor.constraint(equalTo: cards.arrangedSubviews[1].widthAnchor),
            cards.heightAnchor.constraint(equalToConstant: 275),
            loading.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            postTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            postTitle.topAnchor.constraint(equalTo: cards.bottomAnchor, constant: 17),
            xRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            xRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            xRow.topAnchor.constraint(equalTo: postTitle.bottomAnchor, constant: 7),
            xRow.heightAnchor.constraint(equalToConstant: 52),
            xIdentity.centerXAnchor.constraint(equalTo: xRow.centerXAnchor),
            xIdentity.centerYAnchor.constraint(equalTo: xRow.centerYAnchor),
            xMark.widthAnchor.constraint(equalToConstant: 32),
            xMark.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private static func makeCard(
        titleLabel: NSTextField,
        copyButton: NSButton,
        preview: NSView,
        detail: String
    ) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 11
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedRed: 0.851, green: 0.851, blue: 0.871, alpha: 1).cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        let surface = CheckerboardView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 7
        surface.layer?.masksToBounds = true
        copyButton.isBordered = false
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor(calibratedRed: 0.929, green: 0.941, blue: 0.957, alpha: 1).cgColor
        copyButton.layer?.cornerRadius = 6
        copyButton.contentTintColor = NSColor(calibratedRed: 0.204, green: 0.224, blue: 0.255, alpha: 1)
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        [titleLabel, copyButton, surface, detailLabel].forEach(card.addSubview)
        surface.addSubview(preview)
        for item in [titleLabel, copyButton, surface, preview, detailLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -5),
            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            copyButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            surface.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
            surface.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            surface.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            surface.heightAnchor.constraint(equalToConstant: 195),
            preview.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            preview.topAnchor.constraint(equalTo: surface.topAnchor),
            preview.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            detailLabel.topAnchor.constraint(equalTo: surface.bottomAnchor, constant: 7),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }
}
