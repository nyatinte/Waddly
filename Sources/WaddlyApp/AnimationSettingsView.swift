import AppKit
import SwiftUI
import WaddlyCore

/// One editable pose image. Identity is the image instance so reordering keeps every thumbnail
/// distinct without a parallel id table.
struct AnimationSettingsThumbnail: Identifiable {
    let image: NSImage

    var id: ObjectIdentifier {
        ObjectIdentifier(image)
    }
}

/// Fixed editor layout. The window's *content* minimum must cover the four pose rows, the spacing
/// between them, the wrapping instruction block, and the content insets. A minimum expressed as a
/// window frame height is smaller than this by the title bar, which clipped the last row.
enum AnimationSettingsMetrics {
    static let rowHeight: CGFloat = 138
    static let rowSpacing: CGFloat = 8
    static let contentInset: CGFloat = 20
    /// Room for the instructions above the rows at the minimum width.
    static let instructionBlockHeight: CGFloat = 64

    static var contentMinSize: NSSize {
        let rows = CGFloat(PetImageCategory.allCases.count)
        // The stack holds the instruction, one row per category, and a trailing spacer.
        let gaps = rows + 1
        let height = contentInset * 2 + instructionBlockHeight + rowSpacing * gaps + rowHeight * rows
        return NSSize(width: 620, height: height.rounded(.up))
    }
}

/// Presentation state for the animation editor. The editor owns this model only while its window is
/// open: `AppDelegate` builds it from the current pet images and releases it on close.
@MainActor
final class AnimationSettingsModel: ObservableObject {
    let localization: LocalizationController
    @Published private var thumbnailsByCategory: [PetImageCategory: [AnimationSettingsThumbnail]]
    /// The row a drag is currently hovering, so the drop area can highlight without SwiftUI state.
    @Published private(set) var dropTarget: PetImageCategory?

    var onAdd: ((PetImageCategory) -> Void)?
    var onDrop: ((PetImageCategory, [URL]) -> Void)?
    var onRemove: ((PetImageCategory, Int) -> Void)?
    var onMove: ((PetImageCategory, Int, Int) -> Void)?

    init(
        thumbnailsByCategory: [PetImageCategory: [AnimationSettingsThumbnail]],
        localization: LocalizationController
    ) {
        self.thumbnailsByCategory = thumbnailsByCategory
        self.localization = localization
    }

    func thumbnails(for category: PetImageCategory) -> [AnimationSettingsThumbnail] {
        thumbnailsByCategory[category] ?? []
    }

    func setThumbnails(_ thumbnails: [PetImageCategory: [AnimationSettingsThumbnail]]) {
        thumbnailsByCategory = thumbnails
    }

    func setDropTarget(_ category: PetImageCategory, targeted: Bool) {
        if targeted {
            dropTarget = category
        } else if dropTarget == category {
            dropTarget = nil
        }
    }

    /// The language choice lives in `AppSettings`, not the system locale, so the view re-reads its
    /// strings from the localization controller when the menu changes it.
    func refreshLocalization() {
        objectWillChange.send()
    }

    func add(_ category: PetImageCategory) {
        onAdd?(category)
    }

    func drop(_ urls: [URL], on category: PetImageCategory) {
        onDrop?(category, urls)
    }

    func remove(at index: Int, from category: PetImageCategory) {
        onRemove?(category, index)
    }

    func move(from source: Int, to destination: Int, in category: PetImageCategory) {
        onMove?(category, source, destination)
    }
}

@MainActor
struct AnimationSettingsView: View {
    @ObservedObject var model: AnimationSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: AnimationSettingsMetrics.rowSpacing) {
            Text(model.localization.string(for: .imagesInstructions))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(PetImageCategory.allCases, id: \.self) { category in
                AnimationSettingsCategoryRow(
                    category: category,
                    thumbnails: model.thumbnails(for: category),
                    isDropTargeted: model.dropTarget == category,
                    localization: model.localization,
                    onAdd: { model.add(category) },
                    onDrop: { model.drop($0, on: category) },
                    onDropTargetChange: { model.setDropTarget(category, targeted: $0) },
                    onRemove: { model.remove(at: $0, from: category) },
                    onMove: { model.move(from: $0, to: $1, in: category) }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(AnimationSettingsMetrics.contentInset)
        .frame(
            minWidth: AnimationSettingsMetrics.contentMinSize.width,
            minHeight: AnimationSettingsMetrics.contentMinSize.height,
            alignment: .topLeading
        )
    }
}

@MainActor
private struct AnimationSettingsCategoryRow: View {
    let category: PetImageCategory
    let thumbnails: [AnimationSettingsThumbnail]
    let isDropTargeted: Bool
    let localization: LocalizationController
    let onAdd: () -> Void
    let onDrop: ([URL]) -> Void
    let onDropTargetChange: (Bool) -> Void
    let onRemove: (Int) -> Void
    let onMove: (Int, Int) -> Void

    private var title: String {
        category.title(using: localization)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 92, alignment: .leading)
                .accessibilityLabel(title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
                    Button(action: onAdd) {
                        Label(localization.string(for: .imagesAdd), systemImage: "plus")
                    }
                    .frame(minWidth: 88)
                    .accessibilityLabel("\(localization.string(for: .imagesAdd)) — \(title)")

                    ForEach(Array(thumbnails.enumerated()), id: \.element.id) { index, thumbnail in
                        AnimationSettingsThumbnailView(
                            thumbnail: thumbnail,
                            index: index,
                            imageCount: thumbnails.count,
                            localization: localization,
                            onRemove: { onRemove(index) },
                            onMove: { onMove(index, $0) }
                        )
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .dropDestination(for: URL.self) { urls, _ in
                let pngs = urls.filter { $0.pathExtension.lowercased() == "png" }
                guard !pngs.isEmpty else { return false }
                onDrop(pngs)
                return true
            } isTargeted: { targeted in
                onDropTargetChange(targeted)
            }
        }
        .frame(height: AnimationSettingsMetrics.rowHeight)
    }
}

@MainActor
private struct AnimationSettingsThumbnailView: View {
    let thumbnail: AnimationSettingsThumbnail
    let index: Int
    let imageCount: Int
    let localization: LocalizationController
    let onRemove: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: thumbnail.image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("\(localization.string(for: .imagesThumbnail)) \(index + 1)")

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(imageCount <= 1)
                .accessibilityLabel("\(localization.string(for: .imagesRemove)) \(index + 1)")
            }

            HStack {
                Button { onMove(index - 1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .accessibilityLabel("\(localization.string(for: .imagesMoveLeft)) \(index + 1)")

                Spacer()

                Button { onMove(index + 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(index >= imageCount - 1)
                .accessibilityLabel("\(localization.string(for: .imagesMoveRight)) \(index + 1)")
            }
            .frame(width: 64)
        }
        .frame(width: 88, height: 104)
    }
}
