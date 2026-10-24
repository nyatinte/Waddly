import AppKit
import SwiftUI
import WaddlyCore

/// The two editing tools. Resizing the crop always works through the eight canvas handles; the tool
/// only decides what dragging *inside* the selection does.
enum FrameEditorTool: String, CaseIterable, Identifiable {
    case crop
    case align

    var id: String {
        rawValue
    }
}

/// Presentation state for the sprite-frame crop and alignment editor.
///
/// The model never writes to disk. It renders previews from the staged source sheet and only hands
/// nine adjusted frames back to `CharacterImportModel` when the user chooses Done, so closing the
/// editor without Done leaves the parent draft untouched.
/// The exact centre of the crop at the start of a run of size changes.
struct CropSizeAnchor {
    let slot: SpriteFrameSlot
    let centerX: Double
    let centerY: Double
}

@MainActor
final class CharacterFrameEditorModel: ObservableObject {
    static let thumbnailSide = 120
    static let previewSide = 288

    let localization: LocalizationController

    @Published private(set) var isLoading = true
    @Published var editing: SpriteFrameEditing?
    @Published private(set) var sheet: CGImage?
    @Published private(set) var sourceFrames: PetImageSet
    @Published var selectedSlot: SpriteFrameSlot = .idle1
    @Published var tool: FrameEditorTool = .crop
    @Published private(set) var zoomScale: CGFloat = 1
    @Published var showsGrid = true
    @Published var showsCrosshair = true
    @Published private(set) var isComposing = false
    @Published private(set) var composeFailed = false
    @Published private(set) var isReleased = false
    /// Adjusted navigator thumbnails for frames that differ from the saved baseline.
    @Published var adjustedThumbnails: [SpriteFrameSlot: NSImage] = [:]

    var baseThumbnails: [SpriteFrameSlot: NSImage] = [:]
    private var beforePreview: FrameEditorPreviewImage?
    private var afterPreview: FrameEditorPreviewImage?
    /// Keeps the exact (possibly half-pixel) crop center stable across a slider drag or repeated
    /// stepper clicks; a crop origin or another tool resets it.
    var cropSizeAnchor: CropSizeAnchor?
    private var sheetPNGData: Data?
    /// Decodes the retained sheet. Injectable so tests can suspend a decode and release the editor
    /// while it is in flight.
    private let sheetDecoder: @Sendable (Data) async -> CGImage?
    /// Only used to report the entry point's source details and to stage the reviewed draft.
    private(set) weak var importModel: CharacterImportModel?

    init(
        importModel: CharacterImportModel,
        localization: LocalizationController,
        sheetDecoder: (@Sendable (Data) async -> CGImage?)? = nil
    ) {
        self.importModel = importModel
        self.localization = localization
        self.sheetDecoder = sheetDecoder ?? { data in await Self.decodeSheet(data) }
        sourceFrames = importModel.stagedFrames ?? PetImageSet()
    }

    /// A prepared model for snapshot tests and previews. Production paths use `prepare()`.
    init(
        frames: PetImageSet,
        localization: LocalizationController,
        sheet: CGImage? = nil,
        editing: SpriteFrameEditing? = nil
    ) {
        self.localization = localization
        sheetDecoder = { data in await Self.decodeSheet(data) }
        sourceFrames = frames
        if let editing {
            self.editing = editing
            self.sheet = editing.mode == .sheet ? sheet : nil
            sheetPNGData = frames.editingSource?.sheetPNGData
            isLoading = false
            baseThumbnails = renderBaseThumbnails()
            refreshRestoredAdjustedThumbnails()
        } else {
            prepareSynchronously(frames: frames, sheet: sheet)
        }
    }

    // MARK: - Loading the staged source

    /// Decodes the retained 3 × 3 sheet once, when the editor opens, and releases it when the editor
    /// closes. Legacy pets without a retained sheet keep working in per-frame mode.
    func prepare() async {
        guard isLoading, !isReleased else { return }
        let frames = sourceFrames
        if let source = frames.editingSource, let data = source.sheetPNGData {
            if let decoded = await sheetDecoder(data) {
                // The sheet can be dismissed while the decode is suspended; do not resurrect the
                // resources that releaseResources() already dropped.
                guard !isReleased, !Task.isCancelled else { return }
                completePreparation(editing: source.editing, sheet: decoded, data: data)
                return
            }
        }
        guard !isReleased, !Task.isCancelled else { return }
        completeIndividualPreparation(frames: frames)
    }

    nonisolated static func decodeSheet(_ data: Data) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            PetFrameSourceDecoder.sheetImage(from: data)
        }.value
    }

    private func completePreparation(editing: SpriteFrameEditing, sheet: CGImage, data: Data) {
        guard !isReleased else { return }
        self.editing = editing.normalized
        self.sheet = sheet
        sheetPNGData = data
        baseThumbnails = renderBaseThumbnails()
        refreshRestoredAdjustedThumbnails()
        isLoading = false
    }

    private func completeIndividualPreparation(frames: PetImageSet) {
        guard !isReleased else { return }
        guard let editing = PetImageEditingSource.individualEditing(for: frames) else {
            composeFailed = true
            isLoading = false
            return
        }
        self.editing = editing
        sheet = nil
        sheetPNGData = nil
        baseThumbnails = renderBaseThumbnails()
        refreshRestoredAdjustedThumbnails()
        isLoading = false
    }

    private func prepareSynchronously(frames: PetImageSet, sheet: CGImage?) {
        if let source = frames.editingSource, let sheet {
            completePreparation(editing: source.editing, sheet: sheet, data: source.sheetPNGData ?? Data())
            return
        }
        completeIndividualPreparation(frames: frames)
    }

    /// Drops every heavy resource as soon as the editor surface goes away.
    ///
    /// SwiftUI may keep a dismissed sheet's state object alive until its next transaction, so the
    /// model cannot rely on `deinit` alone: the decoded sheet (up to 37.7 MB), the frame references
    /// and both thumbnail caches are released deterministically here.
    func releaseResources() {
        guard !isReleased else { return }
        isReleased = true
        isLoading = false
        sheet = nil
        sheetPNGData = nil
        baseThumbnails.removeAll()
        adjustedThumbnails.removeAll()
        beforePreview = nil
        afterPreview = nil
        sourceFrames = PetImageSet()
        editing = nil
        cropSizeAnchor = nil
    }

    /// Continuous canvas zoom driven by trackpad pinch / Option-scroll; 1 means fit.
    func setZoomScale(_ scale: CGFloat) {
        zoomScale = min(max(scale, 0.5), 8)
    }

    // MARK: - Selection

    var selectedFramePosition: String {
        String(
            format: localization.string(for: .frameEditorFramePositionFormat),
            selectedSlot.sheetNumber,
            totalFrameCount
        )
    }

    var totalFrameCount: Int {
        SpriteFrameSlot.allCases.count
    }

    func isSelected(_ slot: SpriteFrameSlot) -> Bool {
        selectedSlot == slot
    }

    func select(_ slot: SpriteFrameSlot) {
        guard selectedSlot != slot else { return }
        cropSizeAnchor = nil
        selectedSlot = slot
    }

    // MARK: - Current frame geometry

    var geometry: FrameEditGeometry? {
        editing?.geometry(for: selectedSlot)
    }

    var currentAdjustment: FrameAdjustment {
        editing?.adjustment(for: selectedSlot)
            ?? FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 1), offsetX: 0, offsetY: 0)
    }

    var currentSourceImage: CGImage? {
        sourceImage(for: selectedSlot)
    }

    /// The fixed square each exported frame keeps. The crop narrows the visible window inside this
    /// canvas; it never rescales the character or changes the frame dimensions.
    var outputSide: Int {
        canvasSide(for: selectedSlot)
    }

    var cropSide: Int {
        currentAdjustment.crop.size
    }

    func canvasSide(for slot: SpriteFrameSlot) -> Int {
        guard let editing else { return 1 }
        let geometry = editing.geometry(for: slot)
        return max(1, geometry.nominalCell?.size ?? geometry.sourceSide)
    }

    var isCurrentFrameEdited: Bool {
        editing?.isEdited(selectedSlot) ?? false
    }

    var hasEdits: Bool {
        editing?.hasEdits ?? false
    }

    var cropExtendsIntoNeighbor: Bool {
        guard let geometry else { return false }
        return geometry.extendsOutsideCell(currentAdjustment.crop)
    }

    var minimumCropSide: Int {
        geometry?.minimumSide ?? 1
    }

    /// The largest useful crop is the fixed output canvas. Growing beyond it cannot reveal more of
    /// the exported frame and only pushes handles out of the viewport.
    var maximumCropSide: Int {
        outputSide
    }

    var cropSizeRange: ClosedRange<Int> {
        minimumCropSide ... max(minimumCropSide, maximumCropSide)
    }

    var cropOriginXRange: ClosedRange<Int> {
        guard let geometry else { return 0 ... 0 }
        return 0 ... max(0, geometry.sourceSide - currentAdjustment.crop.size)
    }

    var cropOriginYRange: ClosedRange<Int> {
        guard let geometry else { return 0 ... 0 }
        return 0 ... max(0, geometry.sourceSide - currentAdjustment.crop.size)
    }

    var offsetRange: ClosedRange<Int> {
        let limit = max(1, outputSide)
        return -limit ... limit
    }

    // MARK: - Preview images

    func thumbnail(for slot: SpriteFrameSlot) -> NSImage? {
        adjustedThumbnails[slot] ?? baseThumbnails[slot]
    }

    func beforeImage(for slot: SpriteFrameSlot) -> NSImage? {
        guard let editing else { return nil }
        let baseline = FrameAdjustment.baseline(
            slot: slot,
            geometry: editing.geometry(for: slot)
        )
        return previewImage(for: slot, adjustment: baseline, cached: &beforePreview)
    }

    func afterImage(for slot: SpriteFrameSlot) -> NSImage? {
        guard let editing else { return nil }
        return previewImage(for: slot, adjustment: editing.adjustment(for: slot), cached: &afterPreview)
    }

    // MARK: - Staging

    /// Whether Done must render and stage frames.
    ///
    /// An untouched editor closes without replacing the draft's frame objects (which would mark the
    /// draft dirty for no visible change). Reset-all after a previously staged edit differs from the
    /// draft's baseline, so it does stage and restores the exact-thirds extraction.
    var needsStaging: Bool {
        guard let current = editing?.normalized else { return false }
        if let baseline = sourceFrames.editingSource?.editing.normalized {
            return baseline != current
        }
        return hasEdits
    }

    /// Renders all nine frames from the retained source and stages them on the parent draft.
    /// Nothing reaches disk here; the parent Apply still owns persistence.
    func stageIntoDraft() async -> Bool {
        guard !isComposing, let editing, let importModel else { return false }
        isComposing = true
        composeFailed = false
        defer { isComposing = false }
        guard let frames = composeFrames(editing: editing) else {
            composeFailed = true
            return false
        }
        importModel.stageFrameEdited(frames)
        return true
    }

    private func composeFrames(editing: SpriteFrameEditing) -> PetImageSet? {
        var result = PetImageSet()
        for slot in SpriteFrameSlot.allCases {
            guard let source = sourceImage(for: slot),
                  let image = SpriteFrameRenderer.renderCanvasNSImage(
                      source: source,
                      adjustment: editing.adjustment(for: slot),
                      canvasSide: canvasSide(for: slot)
                  )
            else { return nil }
            result[slot.category].append(image)
        }
        if editing.mode == .sheet {
            result.editingSource = PetImageEditingSource(
                editing: editing,
                sheetPNGData: sheetPNGData
            )
        }
        return result
    }
}

private struct FrameEditorPreviewParameters: Equatable {
    let slot: SpriteFrameSlot
    let adjustment: FrameAdjustment
    let canvasSide: Int
}

/// One result per preview, not a per-frame cache. Retain the source to make identity checks safe.
private struct FrameEditorPreviewImage {
    let source: CGImage
    let parameters: FrameEditorPreviewParameters
    let image: NSImage
}

extension CharacterFrameEditorModel {
    private func previewImage(
        for slot: SpriteFrameSlot, adjustment: FrameAdjustment, cached: inout FrameEditorPreviewImage?
    ) -> NSImage? {
        guard let source = sourceImage(for: slot) else {
            cached = nil
            return nil
        }
        let side = canvasSide(for: slot)
        let parameters = FrameEditorPreviewParameters(slot: slot, adjustment: adjustment, canvasSide: side)
        if let cached, cached.source === source, cached.parameters == parameters {
            return cached.image
        }
        let image = SpriteFrameRenderer.renderCanvasNSImage(
            source: source, adjustment: adjustment, canvasSide: side, cappedOutputSide: Self.previewSide
        )
        cached = image.map { FrameEditorPreviewImage(source: source, parameters: parameters, image: $0) }
        return image
    }
}
