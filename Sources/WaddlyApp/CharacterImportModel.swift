import AppKit
import SwiftUI
import WaddlyCore

/// Why the last acquisition attempt could not produce a staged candidate.
enum CharacterImportFailure: Equatable {
    case sheet(PetSheetValidationFailure)
    /// An explicit paste found no supported image on the clipboard.
    case noClipboardImage
    /// A sheet drop carried more than one file; the sheet surface accepts exactly one.
    case multipleFiles
}

/// What a commit attempt did, so the screen can retry truthfully.
enum CharacterCommitOutcome: Equatable {
    case committed
    /// The store refused the write (for example the sample rule, or shutdown).
    case rejected
    /// Persistence failed; the committed pet is unchanged and the draft stays for retry.
    case failed
}

/// The shared acquisition → inspect → commit state machine behind the character import screen.
///
/// Staging never touches persistent state. Only `apply()` writes, through the injected commit
/// closure, so an invalid import, a cancel, or a failed save leaves the committed pet untouched and
/// the staged draft available for a retry. One generation counter makes a late decode from a stale
/// acquisition unable to overwrite a newer one.
@MainActor
final class CharacterImportModel: ObservableObject {
    @Published private(set) var stagedFrames: PetImageSet?
    @Published private(set) var sourceName: String?
    @Published private(set) var sourceDimension: Int?
    @Published private(set) var cellSize: Int?
    @Published private(set) var failure: CharacterImportFailure?
    @Published private(set) var commitFailed = false
    @Published private(set) var isReading = false
    @Published private(set) var isApplying = false
    @Published var isEditingFrames = false
    /// Whether the clipboard currently holds something Waddly can import. Checked without reading
    /// pixels, when the screen appears or the app becomes active; never automatically imported.
    @Published private(set) var clipboardHasImage = false
    /// The system's drag-eligibility report for the drop zone, so one highlight can show without
    /// moving the layout.
    @Published private(set) var isDropTargeted = false
    /// Bumped on every draft mutation so the advanced editor rebuilds its thumbnails.
    @Published private(set) var draftVersion = 0

    private let currentImages: () -> PetImageSet
    private let commit: (PetImageSet) async -> CharacterCommitOutcome
    private var committedBaseline: PetImageSet
    private var generation = 0

    init(
        currentImages: @escaping () -> PetImageSet,
        commit: @escaping (PetImageSet) async -> CharacterCommitOutcome
    ) {
        self.currentImages = currentImages
        self.commit = commit
        committedBaseline = currentImages()
    }

    var hasStagedCandidate: Bool {
        stagedFrames?.isComplete == true
    }

    var canApply: Bool {
        hasStagedCandidate && !isApplying
    }

    /// True when the staged frames differ from what is committed, so Cancel must confirm first.
    var isDirty: Bool {
        guard let stagedFrames else { return false }
        return !Self.sameFrames(stagedFrames, committedBaseline)
    }

    /// Rebase the draft on the pet that is committed now, so reopening shows the real pet.
    func reload() {
        guard !isApplying else { return }
        generation += 1
        committedBaseline = currentImages()
        stagedFrames = nil
        sourceName = nil
        sourceDimension = nil
        cellSize = nil
        failure = nil
        commitFailed = false
        isReading = false
        isApplying = false
        isEditingFrames = false
        isDropTargeted = false
        draftVersion += 1
    }

    // MARK: - Acquisition

    /// Stage one dropped or chosen PNG. A multi-file drop is rejected rather than silently using one.
    func stageFiles(at urls: [URL]) async {
        guard urls.count == 1, let url = urls.first else {
            failure = .multipleFiles
            return
        }
        let token = beginRead()
        let outcome = await CharacterSheetLoader.load(from: url)
        guard token == generation else { return }
        apply(outcome, name: url.lastPathComponent)
    }

    /// Stage the explicit paste. Reads the clipboard only now, never on focus.
    func stageClipboard(from pasteboard: NSPasteboard) async {
        let token = beginRead()
        let outcome = await CharacterSheetLoader.loadFromClipboard(pasteboard)
        guard token == generation else { return }
        apply(outcome, name: nil)
    }

    /// Recheck the pasteboard's shape without reading image pixels, so the Paste affordance can be
    /// truthful before the user commits to a paste.
    func refreshClipboardAvailability(from pasteboard: NSPasteboard) {
        clipboardHasImage = PetClipboardImporter.hasSupportedImage(on: pasteboard)
    }

    /// The drop zone reports the system's drag eligibility here; only a valid PNG drag is targeted.
    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }

    private func beginRead() -> Int {
        generation += 1
        isReading = true
        failure = nil
        commitFailed = false
        return generation
    }

    private func apply(_ outcome: CharacterSheetLoadOutcome, name: String?) {
        isReading = false
        switch outcome {
        case let .valid(candidate):
            stagedFrames = candidate.images
            sourceName = name
            sourceDimension = candidate.sourceDimension
            cellSize = candidate.cellSize
            failure = nil
            draftVersion += 1
        case .empty:
            // Nothing overwrites the staged draft: the reason is reported and the last candidate stays.
            clipboardHasImage = false
            failure = .noClipboardImage
        case let .invalid(reason):
            failure = .sheet(reason)
        }
    }

    // MARK: - Commit / discard

    @discardableResult
    func apply() async -> Bool {
        // Re-entrancy guard: a primary-action double click must commit once, not twice.
        guard !isApplying, let stagedFrames, stagedFrames.isComplete else { return false }
        isApplying = true
        let outcome = await commit(stagedFrames)
        isApplying = false
        switch outcome {
        case .committed:
            committedBaseline = stagedFrames
            failure = nil
            commitFailed = false
            return true
        case .rejected, .failed:
            commitFailed = true
            return false
        }
    }

    /// The app's language lives in `AppSettings`, not the system locale, so the view re-reads its
    /// strings from the localization controller when the menu changes it.
    func refreshLocalization() {
        objectWillChange.send()
    }

    func discard() {
        guard !isApplying else { return }
        reload()
    }

    // MARK: - Advanced editing over the same draft

    func addFrames(_ urls: [URL], to category: PetImageCategory) async {
        guard namedStaged else { return }
        let decoded = await CharacterSheetLoader.optimizedImages(from: urls)
        guard !decoded.isEmpty, var updated = stagedFrames else { return }
        updated[category].append(contentsOf: decoded)
        stagedFrames = updated
        draftVersion += 1
    }

    func removeFrame(at index: Int, from category: PetImageCategory) {
        guard var updated = stagedFrames,
              updated[category].indices.contains(index),
              updated[category].count > 1 else { return }
        updated[category].remove(at: index)
        stagedFrames = updated
        draftVersion += 1
    }

    func moveFrame(from source: Int, to destination: Int, in category: PetImageCategory) {
        guard var updated = stagedFrames,
              let moved = Self.moving(updated[category], from: source, to: destination) else { return }
        updated[category] = moved
        stagedFrames = updated
        draftVersion += 1
    }

    /// The advanced editor is only meaningful once a candidate exists.
    var namedStaged: Bool {
        stagedFrames != nil
    }

    // MARK: - Pure helpers

    static func sameFrames(_ lhs: PetImageSet, _ rhs: PetImageSet) -> Bool {
        PetImageCategory.allCases.allSatisfy { category in
            let left = lhs[category]
            let right = rhs[category]
            return left.count == right.count && zip(left, right).allSatisfy { $0 === $1 }
        }
    }

    static func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
        guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
        var result = elements
        let item = result.remove(at: source)
        result.insert(item, at: destination)
        return result
    }
}
