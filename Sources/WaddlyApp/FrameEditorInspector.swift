import AppKit
import SwiftUI
import WaddlyCore

// MARK: - Right inspector

@MainActor
struct FrameEditorInspector: View {
    @ObservedObject var model: CharacterFrameEditorModel

    private var localization: LocalizationController {
        model.localization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string(for: .frameEditorInspectorTitle))
                    .font(.system(size: 13, weight: .semibold))
                Text(localization.string(for: .frameEditorThisFrameOnly))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: $model.tool) {
                Text(localization.string(for: .frameEditorToolCrop))
                    .tag(FrameEditorTool.crop)
                Text(localization.string(for: .frameEditorToolAlign))
                    .tag(FrameEditorTool.align)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(localization.string(for: .frameEditorInspectorTitle))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if model.tool == .crop {
                        cropSection
                    } else {
                        alignSection
                    }
                    guidesSection
                }
                .padding(.bottom, 4)
            }

            Divider()

            HStack(spacing: 8) {
                Button(localization.string(for: .frameEditorResetFrame)) {
                    model.resetCurrentFrame()
                }
                .controlSize(.small)
                .disabled(!model.isCurrentFrameEdited)
                .accessibilityIdentifier("frameEditorResetFrame")

                Spacer()

                if model.isCurrentFrameEdited {
                    Label(localization.string(for: .frameEditorEdited), systemImage: "pencil.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(FrameEditorMetrics.outerPadding)
    }

    private var cropSection: some View {
        InspectorSection(title: localization.string(for: .frameEditorToolCrop)) {
            HStack(spacing: 8) {
                Text(localization.string(for: .frameEditorSize))
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                IntegerField(
                    value: Binding(
                        get: { model.currentAdjustment.crop.size },
                        set: { model.setCropSize($0) }
                    ),
                    range: model.cropSizeRange,
                    accessibilityLabel: localization.string(for: .frameEditorSize),
                    width: 58
                )
                Text("px")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(model.currentAdjustment.crop.size) },
                    set: { model.setCropSize(Int($0.rounded())) }
                ),
                in: Double(model.cropSizeRange.lowerBound) ... Double(model.cropSizeRange.upperBound)
            )
            .controlSize(.small)
            .accessibilityLabel(localization.string(for: .frameEditorSize))

            Divider()

            Text(localization.string(for: .frameEditorCropOrigin))
                .font(.system(size: 11, weight: .medium))
            HStack(spacing: 8) {
                IntegerField(
                    label: localization.string(for: .frameEditorOriginX),
                    value: Binding(
                        get: { model.currentAdjustment.crop.x },
                        set: { model.setCropOriginX($0) }
                    ),
                    range: model.cropOriginXRange,
                    accessibilityLabel: localization.string(for: .frameEditorOriginXA11y)
                )
                IntegerField(
                    label: localization.string(for: .frameEditorOriginY),
                    value: Binding(
                        get: { model.currentAdjustment.crop.y },
                        set: { model.setCropOriginY($0) }
                    ),
                    range: model.cropOriginYRange,
                    accessibilityLabel: localization.string(for: .frameEditorOriginYA11y)
                )
            }

            Text(localization.string(for: .frameEditorSquareLocked))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(String(
                format: localization.string(for: .frameEditorFixedCanvasHelp),
                model.outputSide,
                model.outputSide
            ))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

            if model.cropExtendsIntoNeighbor {
                Label(
                    localization.string(for: .frameEditorCropNeighborWarning),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var alignSection: some View {
        InspectorSection(title: localization.string(for: .frameEditorToolAlign)) {
            HStack(alignment: .top, spacing: 10) {
                NudgePad(
                    localization: localization,
                    onNudge: nudge,
                    onReset: model.resetPosition
                )
                VStack(spacing: 8) {
                    IntegerField(
                        label: localization.string(for: .frameEditorAlignHorizontal),
                        value: Binding(
                            get: { model.currentAdjustment.offsetX },
                            set: { model.setOffsetX($0) }
                        ),
                        range: model.offsetRange,
                        accessibilityLabel: localization.string(for: .frameEditorHorizontalPosition)
                    )
                    IntegerField(
                        label: localization.string(for: .frameEditorAlignVertical),
                        value: Binding(
                            get: { model.currentAdjustment.offsetY },
                            set: { model.setOffsetY($0) }
                        ),
                        range: model.offsetRange,
                        accessibilityLabel: localization.string(for: .frameEditorVerticalPosition)
                    )
                    Text(localization.string(for: .frameEditorAlignNudgeHelp))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(localization.string(for: .frameEditorAlignHelp))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guidesSection: some View {
        InspectorSection(title: localization.string(for: .frameEditorGuides)) {
            Toggle(localization.string(for: .frameEditorGuideGrid), isOn: $model.showsGrid)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Toggle(localization.string(for: .frameEditorGuideCrosshair), isOn: $model.showsCrosshair)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text(localization.string(for: .frameEditorGuidesHelp))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nudge(deltaX: Int, deltaY: Int) {
        let step = NSEvent.modifierFlags.contains(.shift) ? 10 : 1
        model.nudge(deltaX: deltaX * step, deltaY: deltaY * step)
    }
}

@MainActor
private struct NudgePad: View {
    let localization: LocalizationController
    let onNudge: (Int, Int) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            nudgeButton("arrow.up", label: .frameEditorNudgeUp) { onNudge(0, -1) }
            HStack(spacing: 3) {
                nudgeButton("arrow.left", label: .frameEditorNudgeLeft) { onNudge(-1, 0) }
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(localization.string(for: .frameEditorResetPosition))
                .accessibilityLabel(localization.string(for: .frameEditorResetPosition))
                nudgeButton("arrow.right", label: .frameEditorNudgeRight) { onNudge(1, 0) }
            }
            nudgeButton("arrow.down", label: .frameEditorNudgeDown) { onNudge(0, 1) }
        }
    }

    private func nudgeButton(
        _ symbol: String,
        label: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(localization.string(for: label))
        .accessibilityLabel(localization.string(for: label))
    }
}
