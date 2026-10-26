import SwiftUI

@MainActor
extension SetupWizardScreen {
    func step(_ key: LocalizationKey, index: Int) -> some View {
        let current = controller.currentStep.rawValue == index
        let complete = controller.currentStep.rawValue > index
        return Label(
            controller.localizedString(key),
            systemImage: complete ? "checkmark.circle.fill" : "\(index + 1).circle.fill"
        )
        .font(current ? .system(.subheadline, design: .default).weight(.semibold) : .subheadline)
        .foregroundStyle(current || complete ? Color.accentColor : Color.secondary)
        .accessibilityElement(children: .combine)
    }

    func title(_ key: LocalizationKey) -> some View {
        Text(controller.localizedString(key))
            .font(.system(size: 25, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    func bodyText(_ key: LocalizationKey) -> some View {
        Text(controller.localizedString(key))
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func caption(_ key: LocalizationKey) -> some View {
        Text(controller.localizedString(key))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func caption(_ value: String) -> some View {
        Text(value).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func status(_ key: LocalizationKey, positive: Bool) -> some View {
        Label(controller.localizedString(key), systemImage: positive ? "checkmark.circle.fill" : "circle")
            .font(.callout.weight(.medium))
            .foregroundStyle(positive ? DesignTokens.Status.positive : Color.secondary)
            // The label text already states the current value, so VoiceOver reads the transition
            // when it reaches the element. `.updatesFrequently` instead marks the status as a
            // moving target, which is not what a stable permission state is.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.localizedString(key))
    }

    /// One outcome on the completion page. Same icon + words language as `status()`, so the finished
    /// step and the step that produced it agree on what "done" looks like.
    func resultRow(_ key: LocalizationKey, done: Bool) -> some View {
        Label(controller.localizedString(key), systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.callout.weight(.medium))
            .foregroundStyle(done ? DesignTokens.Status.positive : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.localizedString(key))
    }

    func errorMessage(_ key: LocalizationKey) -> some View {
        Label(controller.localizedString(key), systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(DesignTokens.Status.critical)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.localizedString(key))
    }

    func numbered(_ keys: [LocalizationKey]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                Label(controller.localizedString(key), systemImage: "\(index + 1).circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    func option(
        _ title: LocalizationKey,
        detail: LocalizationKey,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.localizedString(title)).font(.headline)
                    Text(controller.localizedString(detail)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: SetupMetrics.optionCardHeight, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: controller.localizedString(title)))
        .accessibilityHint(Text(verbatim: controller.localizedString(detail)))
    }
}

@MainActor
extension SetupWizardScreen {
    /// A standalone setup action with the shared 36 pt height, so the step body and the pinned
    /// footer read as one control system.
    func actionButton(
        _ title: String,
        identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .actionLabel()
        }
        .controlSize(.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
extension SetupWizardScreen {
    /// The one footer position: navigation left, the primary action right, always above a divider.
    var nextButtonKey: LocalizationKey {
        if controller.isMonitoringSettings {
            return .setupClose
        }
        return controller.currentStep == .completed ? .setupShowOnDesktop : .setupNext
    }

    var footer: some View {
        HStack(spacing: LayoutMetrics.actionGap) {
            if !controller.isMonitoringSettings, controller.currentStep != .pet {
                Button(action: controller.goBack) {
                    Text(verbatim: controller.localizedString(.setupBack))
                        .actionLabel()
                }
                .controlSize(.large)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: controller.localizedString(.setupBack)))
                .accessibilityIdentifier("goBack")
            }
            Spacer()
            if !controller.isMonitoringSettings, controller.currentStep == .monitoring, !controller.isMonitoringReady {
                Button(action: controller.deferMonitoring) {
                    Text(verbatim: controller.localizedString(.setupLater))
                        .actionLabel()
                }
                .controlSize(.large)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: controller.localizedString(.setupLater)))
                .accessibilityIdentifier("deferMonitoring")
            }
            Button(action: controller.goNext) {
                Text(verbatim: controller.localizedString(nextButtonKey))
                    .actionLabel()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: controller.localizedString(nextButtonKey)))
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                !controller.isMonitoringSettings && ((controller.currentStep == .pet && !controller.hasImage)
                    || (controller.currentStep == .monitoring && !controller.isMonitoringReady))
            )
            .keyboardShortcut(controller.isMonitoringSettings ? .cancelAction : .defaultAction)
            .accessibilityIdentifier(controller.isMonitoringSettings ? "closeMonitoringSettings" : "goNext")
        }
        .frame(height: LayoutMetrics.actionHeight)
    }
}
