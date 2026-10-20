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
        print(
            "state,physical_footprint_bytes,peak_physical_footprint_bytes," +
                "rss_bytes,peak_rss_bytes,system_uptime_seconds,reusable_bytes," +
                "purgeable_volatile_resident_bytes,purgeable_volatile_virtual_bytes," +
                "compressed_bytes,internal_bytes,external_bytes,device_bytes"
        )
        snapshot("launch")
        delegate.setupWizardController?.close()
        if ProcessInfo.processInfo.environment["WADDLY_PROFILE_CHARACTER_LIFECYCLE"] == "1" {
            try await measureCharacterLifecycle(delegate, source: source)
            return
        }
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
                delegate.showChangeCharacter()
            }
            withExtendedLifetime(preview) {}
            try await Task.sleep(for: .milliseconds(500))
            snapshot("import-\(iteration)")
        }
        try await Task.sleep(for: .seconds(30))
        snapshot("character-import-30s")
        delegate.characterImportWindowController?.window?.close()
        try await Task.sleep(for: .seconds(30))
        snapshot("return-idle-30s")
    }

    private enum LifecycleFailure: Error {
        case invalidCandidate, commitOrCloseFailed, retainedClosedSession, invalidCycleCount
    }

    /// Uses the real staged import and Apply path, not a direct persistence replacement. The first
    /// cycle warms the renderer; compare later closed plateaus, not empty launch with a loaded pet.
    @MainActor private static func measureCharacterLifecycle(_ delegate: AppDelegate, source: URL) async throws {
        let configuredCount = ProcessInfo.processInfo.environment["WADDLY_PROFILE_CHARACTER_CYCLES"] ?? "3"
        guard let cycles = Int(configuredCount), cycles > 0 else { throw LifecycleFailure.invalidCycleCount }
        for cycle in 0 ..< cycles {
            let released = try await stageAndApplyCharacter(delegate, source: source, cycle: cycle)
            for second in 1 ... 30 {
                try await Task.sleep(for: .seconds(1))
                snapshot("cycle-\(cycle)-closed-\(second)s")
            }
            guard released() else { throw LifecycleFailure.retainedClosedSession }
        }
        snapshot("lifecycle-complete")
    }

    @MainActor private static func stageAndApplyCharacter(
        _ delegate: AppDelegate, source: URL, cycle: Int
    ) async throws -> @MainActor () -> Bool {
        delegate.showChangeCharacter()
        guard let controller = delegate.characterImportWindowController else {
            throw LifecycleFailure.commitOrCloseFailed
        }
        await controller.model.stageFiles(at: [source])
        guard controller.model.failure == nil,
              controller.model.isDirty,
              controller.model.canApply else { throw LifecycleFailure.invalidCandidate }
        for second in 1 ... 30 {
            try await Task.sleep(for: .seconds(1))
            snapshot("cycle-\(cycle)-staged-\(second)s")
        }
        await controller.applyAndClose().value
        guard delegate.characterImportWindowController == nil,
              delegate.hasCompletePetImageSet,
              !controller.model.isDirty,
              !controller.model.commitFailed,
              !controller.model.commitRejected,
              controller.window?.isVisible == false else { throw LifecycleFailure.commitOrCloseFailed }
        return { [weak controller, weak model = controller.model] in controller == nil && model == nil }
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
        print(
            "\(label),\(info.phys_footprint),\(info.ledger_phys_footprint_peak)," +
                "\(info.resident_size),\(info.resident_size_peak),\(ProcessInfo.processInfo.systemUptime)," +
                "\(info.reusable),\(info.purgeable_volatile_resident),\(info.purgeable_volatile_virtual)," +
                "\(info.compressed),\(info.internal),\(info.external),\(info.device)"
        )
        fflush(stdout)
    }
}
