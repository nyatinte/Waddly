import AppKit
import SwiftUI
import WaddlyCore

// MARK: - Left navigator

@MainActor
struct FrameEditorSidebar: View {
    @ObservedObject var model: CharacterFrameEditorModel

    private var localization: LocalizationController {
        model.localization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.string(for: .frameEditorFrames))
                    .font(.system(size: 15, weight: .semibold))
                Text(localization.string(for: model.isSheetMode
                        ? .frameEditorFramesSubtitle
                        : .frameEditorFramesSubtitleIndividual))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            contactSheet
            Divider()
            groups
            Spacer(minLength: 6)
            if !model.isSheetMode {
                legacyNotice
            }
            if let sourceName = model.sourceName, let dimensions = model.sourceDimensionsDescription {
                VStack(alignment: .leading, spacing: 2) {
                    Label(sourceName, systemImage: "photo")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(dimensions)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    localization.string(for: .frameEditorSourceLabel)
                        + ": " + sourceName + ", " + dimensions
                )
            }
        }
        .padding(FrameEditorMetrics.outerPadding)
    }

    private var contactSheet: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(SpriteFrameSlot.allCases, id: \.self) { slot in
                FrameThumbnailTile(
                    slot: slot,
                    image: model.thumbnail(for: slot),
                    isSelected: model.isSelected(slot),
                    isEdited: model.isFrameEdited(slot),
                    showNumber: true,
                    accessibilityLabel: CharacterFrameEditorModel.accessibilityLabel(
                        for: slot,
                        edited: model.isFrameEdited(slot),
                        localization: localization
                    )
                ) {
                    model.select(slot)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(for: .frameEditorFrameNavigatorA11y))
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.groupOrder, id: \.self) { category in
                let slots = SpriteFrameSlot.slots(for: category)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(category.title(using: localization))
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(slots.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        ForEach(slots, id: \.self) { slot in
                            FrameThumbnailTile(
                                slot: slot,
                                image: model.thumbnail(for: slot),
                                isSelected: model.isSelected(slot),
                                isEdited: model.isFrameEdited(slot),
                                showNumber: false,
                                accessibilityLabel: CharacterFrameEditorModel.accessibilityLabel(
                                    for: slot,
                                    edited: model.isFrameEdited(slot),
                                    localization: localization
                                )
                            ) {
                                model.select(slot)
                            }
                            .frame(width: 44, height: 44)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// The four semantic groups in animation order. The contact sheet above stays in sheet order.
    private static let groupOrder: [PetImageCategory] = [.idle, .typing, .enter, .sleep]

    private var legacyNotice: some View {
        Label(localization.string(for: .frameEditorLegacyNotice), systemImage: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A numbered contact-sheet cell or a compact grouped thumbnail. Both select the same frame.
@MainActor
private struct FrameThumbnailTile: View {
    let slot: SpriteFrameSlot
    let image: NSImage?
    let isSelected: Bool
    let isEdited: Bool
    let showNumber: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                CheckerboardBackground(square: 6)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                }
                if showNumber {
                    Text(String(format: "%02d", slot.sheetNumber))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
                if isEdited {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The collapsed navigator shown on narrower screens: numbered frames stay reachable without the
/// group thumbnails competing for canvas width.
@MainActor
struct FrameEditorCompactRail: View {
    @ObservedObject var model: CharacterFrameEditorModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 5) {
                ForEach(SpriteFrameSlot.allCases, id: \.self) { slot in
                    Button {
                        model.select(slot)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.isSelected(slot)
                                    ? Color.accentColor.opacity(0.18)
                                    : Color(nsColor: .controlBackgroundColor))
                            HStack(spacing: 2) {
                                Text(String(format: "%02d", slot.sheetNumber))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                if model.isFrameEdited(slot) {
                                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                                }
                            }
                        }
                        .frame(width: 38, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(
                                    model.isSelected(slot)
                                        ? Color.accentColor
                                        : Color(nsColor: .separatorColor),
                                    lineWidth: model.isSelected(slot) ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CharacterFrameEditorModel.accessibilityLabel(
                        for: slot,
                        edited: model.isFrameEdited(slot),
                        localization: model.localization
                    ))
                    .accessibilityAddTraits(model.isSelected(slot) ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }
}
