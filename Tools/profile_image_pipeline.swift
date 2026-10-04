import AppKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

@main
struct ImagePipelineProbe {
    static func main() throws {
        let source = try makeSource()
        if CommandLine.arguments.count == 2 {
            try source.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
            return
        }
        print("state,rss_bytes,physical_footprint_bytes,max_rss_bytes,peak_physical_footprint_bytes")
        snapshot("fixture-ready")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var resident = PetImageSet()
        for iteration in 0 ..< 5 {
            try autoreleasepool {
                guard let images = PetSpriteSheetImporter.frames(from: source) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                #if LEGACY
                    let preview = NSImage(data: source)
                #else
                    let preview = PetSpriteSheetImporter.preview(from: source)
                #endif
                guard let preview else { throw CocoaError(.fileReadCorruptFile) }
                _ = preview.cgImage(forProposedRect: nil, context: nil, hints: nil)
                snapshot("import-\(iteration)")
                try persist(images, in: directory, iteration: iteration)
                resident = images
            }
            snapshot("retained-\(iteration)")
        }
        snapshot("final")
        withExtendedLifetime(resident) {}
    }

    private static func persist(_ images: PetImageSet, in directory: URL, iteration: Int) throws {
        for category in PetImageCategory.allCases {
            for (index, image) in images[category].enumerated() {
                guard let data = PetSpriteSheetImporter.pngData(for: image) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let url = directory.appendingPathComponent("\(category)-\(index).png")
                try data.write(to: url, options: .atomic)
                snapshot("encode-\(iteration)-\(category)-\(index)")
            }
        }
    }

    private static func makeSource() throws -> Data {
        try autoreleasepool {
            guard let context = CGContext(
                data: nil, width: 3072, height: 3072, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let storage = context.data else { throw CocoaError(.fileReadCorruptFile) }
            let pixels = storage.assumingMemoryBound(to: UInt8.self)
            for index in 0 ..< context.bytesPerRow * context.height {
                pixels[index] = UInt8(truncatingIfNeeded: index / 17)
            }
            guard let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil
            ) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            return data as Data
        }
    }

    private static func snapshot(_ label: String) {
        var basic = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: basic) / MemoryLayout<integer_t>.size)
        let basicStatus = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        var info = task_vm_info_data_t()
        var infoCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let infoStatus = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &infoCount)
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let values = [
            label,
            String(basicStatus == KERN_SUCCESS ? basic.resident_size : 0),
            String(infoStatus == KERN_SUCCESS ? info.phys_footprint : 0),
            String(usage.ru_maxrss),
            String(infoStatus == KERN_SUCCESS ? info.ledger_phys_footprint_peak : 0)
        ]
        print(values.joined(separator: ","))
    }
}
