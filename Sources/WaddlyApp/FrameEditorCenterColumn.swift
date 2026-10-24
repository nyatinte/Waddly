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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header
                FrameEditorCanvas(
                    configuration: canvasConfiguration,
                    onAdjustmentChange: { adjustment in model.applyCanvasAdjustment(adjustment) },
                    onZoomChange: { scale in model.setZoomScale(scale) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                navigationRow
                FrameEditorResultPreview(model: model)
            }
            .padding(DesignTokens.Spacing.lg)
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
            zoomScale: model.zoomScale,
            resetKey: model.selectedSlot.rawValue,
            showsGrid: model.showsGrid,
            showsCrosshair: model.showsCrosshair,
            showsWarning: model.cropExtendsIntoNeighbor,
            accessibilityLabel: localization.string(for: .frameEditorCanvasA11y),
            accessibilityValue: canvasAccessibilityValue,
            accessibilityHelp: localization.string(for: .frameEditorCanvasHelp),
            zoomInLabel: localization.string(for: .frameEditorZoomInAction),
            zoomOutLabel: localization.string(for: .frameEditorZoomOutAction),
            resetViewLabel: localization.string(for: .frameEditorResetViewAction)
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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(model.selectedFrameTitle)
                    .font(DesignTokens.Typography.heading)
                    .accessibilityIdentifier("frameEditorFrameTitle")
                Text(localization.string(for: .frameEditorCanvasHelp))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var navigationRow: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                model.selectPreviousFrame()
            } label: {
                Label(
                    localization.string(for: .frameEditorPreviousFrame),
                    systemImage: "chevron.left"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.canSelectPreviousFrame)
            .keyboardShortcut(.leftArrow, modifiers: [.option])

            Spacer()

            Text(model.selectedFramePosition)
                .font(DesignTokens.Typography.mono)
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
            .controlSize(.large)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(localization.string(for: .frameEditorResultPreview))
                    .font(DesignTokens.Typography.heading)
                    .foregroundStyle(.secondary)
                if model.isCurrentFrameEdited {
                    Label(
                        localization.string(for: .frameEditorEdited),
                        systemImage: "pencil.circle.fill"
                    )
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text(String(
                    format: localization.string(for: .frameEditorOutputSizeFormat),
                    model.outputSide,
                    model.outputSide
                ))
                .font(DesignTokens.Typography.mono)
                .foregroundStyle(.secondary)
            }
            if model.cropExtendsIntoNeighbor {
                Label(
                    localization.string(for: .frameEditorCropNeighborWarning),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Status.warning)
                .fixedSize(horizontal: false, vertical: true)
                .help(localization.string(for: .frameEditorCropNeighborWarning))
            }
            HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
                Spacer(minLength: 0)
                FrameEditorPreviewCard(
                    title: localization.string(for: .frameEditorBefore),
                    image: model.beforeImage(for: model.selectedSlot),
                    accessibilityLabel: localization.string(for: .frameEditorBeforeA11y)
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                FrameEditorPreviewCard(
                    title: localization.string(for: .frameEditorAfter),
                    image: model.afterImage(for: model.selectedSlot),
                    accessibilityLabel: localization.string(for: .frameEditorAfterA11y)
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}

@MainActor
private struct FrameEditorPreviewCard: View {
    static let cardSide: CGFloat = 168

    let title: String
    let image: NSImage?
    let accessibilityLabel: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            ZStack {
                if let image {
                    ZStack {
                        CheckerboardBackground(square: 7)
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                        FrameEditorPreviewCrosshair()
                    }
                    .frame(width: Self.cardSide, height: Self.cardSide)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
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

/// Center crosshair overlay for the Before/After cards, mirroring the canvas guides so the
/// alignment anchor is visible while comparing.
@MainActor
private struct FrameEditorPreviewCrosshair: View {
    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            Path { path in
                path.move(to: CGPoint(x: center.x, y: 0))
                path.addLine(to: CGPoint(x: center.x, y: proxy.size.height))
                path.move(to: CGPoint(x: 0, y: center.y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: center.y))
            }
            .stroke(
                Color.white.opacity(0.75),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            .shadow(color: .black.opacity(0.6), radius: 0.5)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.2))
                .position(center)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
