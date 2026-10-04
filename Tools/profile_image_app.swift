import AppKit
import Darwin
import WaddlyCore

@main
struct ImageAppProbe {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let app = NSApplication.shared
        let domain = "WaddlyMemoryProbe-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else { exit(2) }
        let delegate = AppDelegate(settings: AppSettings(defaults: defaults))
        delegate.petImagesDirectoryURL = URL(fileURLWithPath: CommandLine.arguments[2])
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do {
                try await measure(delegate, source: URL(fileURLWithPath: CommandLine.arguments[1]))
                defaults.removePersistentDomain(forName: domain)
                app.terminate(nil)
            } catch {
                fputs("Image app probe failed: \(error)\n", stderr)
                defaults.removePersistentDomain(forName: domain)
                exit(1)
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func measure(_ delegate: AppDelegate, source: URL) async throws {
        try await Task.sleep(for: .seconds(2))
        print("state,physical_footprint_bytes,peak_physical_footprint_bytes")
        snapshot("launch")
        delegate.setupWizardController?.close()
        for iteration in 0 ..< 10 {
            let prepared = await Task.detached {
                autoreleasepool { () -> (PetImageSet, NSImage)? in
                    guard let data = PetSpriteSheetImporter.readPNG(from: source),
                          let images = PetSpriteSheetImporter.frames(from: data),
                          let preview = PetSpriteSheetImporter.preview(from: data) else { return nil }
                    return (images, preview)
                }
            }.value
            guard let (images, preview) = prepared else { throw CocoaError(.fileReadCorruptFile) }
            snapshot("prepared-\(iteration)")
            let saved = await delegate.queueImageUpdate {
                do {
                    try await delegate.persistPetImages(images, resetActivity: true)
                    return true
                } catch { return false }
            }
            guard saved else { throw CocoaError(.fileWriteUnknown) }
            if iteration == 0 {
                delegate.showImageSettings()
            }
            withExtendedLifetime(preview) {}
            try await Task.sleep(for: .milliseconds(500))
            snapshot("import-\(iteration)")
        }
        try await Task.sleep(for: .seconds(30))
        snapshot("image-settings-30s")
        delegate.imageSettingsWindow?.close()
        try await Task.sleep(for: .seconds(30))
        snapshot("return-idle-30s")
    }

    private static func snapshot(_ label: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { exit(1) }
        print("\(label),\(info.phys_footprint),\(info.ledger_phys_footprint_peak)")
        fflush(stdout)
    }
}
