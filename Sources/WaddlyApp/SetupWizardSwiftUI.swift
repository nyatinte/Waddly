import AppKit
import SwiftUI
import WaddlyCore

@MainActor
struct SetupWizardScreen: View {
    @ObservedObject var controller: SetupWizardController

    var body: some View {
        VStack(spacing: 0) {
            if !controller.isMonitoringSettings, controller.currentStep != .completed {
                HStack(spacing: 10) {
                    step(.setupStepPet, index: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    step(.setupStepMonitoring, index: 1)
                    Spacer()
                }
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.top, 22)
            }

            if !controller.isMonitoringSettings, controller.currentStep == .pet {
                characterImport
            } else {
                HStack(alignment: .top, spacing: LayoutMetrics.columnGap) {
                    if controller.isCompactGuide {
                        ScrollView(.vertical) {
                            page.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    // The compact permission guide stays beside System Settings without a preview.
                    if !controller.isCompactGuide {
                        SetupPreviewHost(pane: controller.previewPane)
                            .frame(width: LayoutMetrics.previewWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.top, LayoutMetrics.sectionGap)
                .padding(.bottom, LayoutMetrics.sectionGap)
                .frame(maxHeight: .infinity)

                Divider()
                footer
                    .padding(.horizontal, LayoutMetrics.contentInset)
                    .padding(.vertical, LayoutMetrics.footerInset)
            }
        }
        .frame(width: controller.contentSize.width, height: controller.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(MotionPreference.isReduced ? nil : .easeInOut(duration: 0.18), value: controller.currentStep)
    }

    @ViewBuilder private var page: some View {
        switch controller.currentStep {
        case .pet: EmptyView()
        case .monitoring: monitoringPage
        case .completed: completedPage
        }
    }
}

@MainActor
private struct SetupPreviewHost: NSViewRepresentable {
    let pane: SetupPreviewPane

    func makeNSView(context: Context) -> SetupPreviewPane {
        pane
    }

    func updateNSView(_ nsView: SetupPreviewPane, context: Context) {}
}
