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
            .font(.callout.weight(.medium)).foregroundStyle(positive ? Color.green : Color.secondary)
            // The label text already states the current value, so VoiceOver reads the transition
            // when it reaches the element. `.updatesFrequently` instead marks the status as a
            // moving target, which is not what a stable permission state is.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.localizedString(key))
    }

    func errorMessage(_ key: LocalizationKey) -> some View {
        Label(controller.localizedString(key), systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
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
