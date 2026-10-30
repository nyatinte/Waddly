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

    /// Title and current state as one block. The state is the first thing to read, so it belongs
    /// under the title instead of between two cards further down the page.
    func pageHeader(_ titleKey: LocalizationKey, statusKey: LocalizationKey, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            title(titleKey)
            status(statusKey, positive: positive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one card shape the setup pages use. Callers stack their own rows inside it, so a page can
    /// add a step or an action without rebuilding the surface.
    func cardContainer(
        spacing: CGFloat = DesignTokens.Spacing.md,
        padding: CGFloat = DesignTokens.Spacing.md,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        return VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.stroke(Color(nsColor: .separatorColor)))
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

    /// A numbered step's badge. Decorative: the step text carries the meaning.
    func stepBadge(_ index: Int) -> some View {
        Image(systemName: "\(index).circle.fill")
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }

    func numberedStep(_ index: Int, _ key: LocalizationKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            stepBadge(index)
            Text(controller.localizedString(key))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(stepAccessibilityLabel(index, key))
        }
    }

    func stepAccessibilityLabel(_ index: Int, _ key: LocalizationKey) -> String {
        String(format: controller.localizedString(.setupGuideStepAccessibility), index, controller.localizedString(key))
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

    /// The accent-filled action of a page. The style goes on the button itself, so a caller cannot
    /// end up with a secondary-looking primary by applying it to the wrapper instead.
    func primaryActionButton(
        _ title: String,
        identifier: String,
        systemImage: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            if let systemImage {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(verbatim: title)
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                .actionLabel()
            } else {
                Text(verbatim: title)
                    .actionLabel()
            }
        }
        .buttonStyle(.borderedProminent)
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
