import AppKit
import SwiftUI
import WaddlyCore

// MARK: - Center column

@MainActor
struct FrameEditorCenterColumn: View {
    @ObservedObject var model: CharacterFrameEditorModel
    let localization: LocalizationController

    var body: some View {
        GeometryReader { geometry in
            let canvasHeight = max(
                FrameEditorMetrics.minimumCanvasHeight,
                geometry.size.height - FrameEditorMetrics.centerReservedHeight
            )
            VStack(alignment: .leading, spacing: 10) {
                header
                FrameEditorCanvas(configuration: canvasConfiguration) { adjustment in
                    model.applyCanvasAdjustment(adjustment)
                }
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                navigationRow
                FrameEditorResultPreview(model: model)
            }
            .padding(FrameEditorMetrics.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var canvasConfiguration: FrameCanvasConfiguration {
        FrameCanvasConfiguration(
            source: model.currentSourceImage,
            sourceSide: model.geometry?.sourceSide ?? 1,
            canvasSide: model.outputSide,
            nominalCell: model.geometry?.nominalCell,
            adjustment: model.currentAdjustment,
            tool: model.tool,
            zoomPercent: model.zoomPercent,
            showsGrid: model.showsGrid,
            showsCrosshair: model.showsCrosshair,
            showsWarning: model.cropExtendsIntoNeighbor,
            accessibilityLabel: localization.string(for: .frameEditorCanvasA11y),
            accessibilityValue: canvasAccessibilityValue,
            accessibilityHelp: localization.string(for: .frameEditorCanvasHelp)
        )
    }

    private var canvasAccessibilityValue: String {
        let crop = model.currentAdjustment.crop
        return String(
            format: localization.string(for: .frameEditorCanvasValueFormat),
            crop.size,
            crop.x,
            crop.y,
            model.currentAdjustment.offsetX,
            model.currentAdjustment.offsetY
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedFrameTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("frameEditorFrameTitle")
                Text(localization.string(for: .frameEditorCanvasHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            zoomControls
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                model.zoomPercent = max(
                    CharacterFrameEditorModel.zoomLevels.first ?? 100,
                    model.zoomPercent - 100
                )
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.zoomPercent <= (CharacterFrameEditorModel.zoomLevels.first ?? 100))
            .help(localization.string(for: .frameEditorZoomOut))
            .accessibilityLabel(localization.string(for: .frameEditorZoomOut))

            Text(String(format: localization.string(for: .frameEditorZoomPercentFormat), model.zoomPercent))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 44)
                .accessibilityLabel(String(
                    format: localization.string(for: .frameEditorZoomAccessibilityFormat),
                    model.zoomPercent
                ))

            Button {
                model.zoomPercent = min(
                    CharacterFrameEditorModel.zoomLevels.last ?? 400,
                    model.zoomPercent + 100
                )
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.zoomPercent >= (CharacterFrameEditorModel.zoomLevels.last ?? 400))
            .help(localization.string(for: .frameEditorZoomIn))
            .accessibilityLabel(localization.string(for: .frameEditorZoomIn))

            Text(localization.string(for: .frameEditorSquareAspect))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .accessibilityLabel(localization.string(for: .frameEditorSquareLocked))
        }
    }

    private var navigationRow: some View {
        HStack(spacing: 10) {
            Button {
                model.selectPreviousFrame()
            } label: {
                Label(
                    localization.string(for: .frameEditorPreviousFrame),
                    systemImage: "chevron.left"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.canSelectPreviousFrame)
            .keyboardShortcut(.leftArrow, modifiers: [.option])

            Spacer()

            Text(model.selectedFramePosition)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(
                    format: localization.string(for: .frameEditorFramePositionA11yFormat),
                    model.selectedSlot.sheetNumber,
                    model.totalFrameCount
                ))

            Spacer()

            Button {
                model.selectNextFrame()
            } label: {
                Label(
                    localization.string(for: .frameEditorNextFrame),
                    systemImage: "chevron.right"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.canSelectNextFrame)
            .keyboardShortcut(.rightArrow, modifiers: [.option])
        }
    }
}

// MARK: - Result preview

@MainActor
private struct FrameEditorResultPreview: View {
    @ObservedObject var model: CharacterFrameEditorModel

    var body: some View {
        let localization = model.localization
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.string(for: .frameEditorResultPreview))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(
                    format: localization.string(for: .frameEditorOutputSizeFormat),
                    model.outputSide,
                    model.outputSide
                ))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                FrameEditorPreviewCard(
                    title: localization.string(for: .frameEditorBefore),
                    image: model.beforeImage(for: model.selectedSlot),
                    accessibilityLabel: localization.string(for: .frameEditorBeforeA11y)
                )
                FrameEditorPreviewCard(
                    title: localization.string(for: .frameEditorAfter),
                    image: model.afterImage(for: model.selectedSlot),
                    accessibilityLabel: localization.string(for: .frameEditorAfterA11y)
                )
                VStack(alignment: .leading, spacing: 7) {
                    if model.cropExtendsIntoNeighbor {
                        Label(
                            localization.string(for: .frameEditorCropNeighborWarning),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isCurrentFrameEdited {
                        Label(
                            localization.string(for: .frameEditorEdited),
                            systemImage: "pencil.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Text(localization.string(for: .frameEditorPreviewHint))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}

@MainActor
private struct FrameEditorPreviewCard: View {
    static let cardSide: CGFloat = 126

    let title: String
    let image: NSImage?
    let accessibilityLabel: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack {
                if let image {
                    ZStack {
                        CheckerboardBackground(square: 7)
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    }
                    .frame(width: Self.cardSide, height: Self.cardSide)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
            }
            .frame(width: Self.cardSide, height: Self.cardSide)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
