import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Test @MainActor func imageTransactionsStaySerializedAcrossWorkerSuspensions() async {
    let app = AppDelegate()
    let (started, startSignal) = AsyncStream<Void>.makeStream()
    let (release, releaseSignal) = AsyncStream<Void>.makeStream()
    var events: [Int] = []
    let first = Task {
        await app.queueImageUpdate {
            events.append(1)
            startSignal.yield(())
            for await _ in release {
                break
            }
            events.append(2)
            return true
        }
    }
    var iterator = started.makeAsyncIterator()
    _ = await iterator.next()
    let second = Task {
        await app.queueImageUpdate {
            events.append(3)
            return true
        }
    }
    await Task.yield()
    #expect(events == [1])
    releaseSignal.yield(())
    #expect(await first.value)
    #expect(await second.value)
    #expect(events == [1, 2, 3])
    startSignal.finish()
    releaseSignal.finish()
    app.isShuttingDown = true
    let accepted = await app.queueImageUpdate {
        events.append(4)
        return true
    }
    #expect(!accepted)
    #expect(events == [1, 2, 3])
}

@Test @MainActor func committedImageRowsStayCorrectWhileCleanupIsSuspended() async throws {
    _ = NSApplication.shared
    let domain = "WaddlyTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = AppDelegate(settings: AppSettings(defaults: defaults))
    app.petImagesDirectoryURL = directory
    let frames = try makeImageFrames()
    let row = try prepareImageRow(frames, app: app, directory: directory)
    let updated = PetImageSet([.idle: Array(frames.dropFirst())])
    let (started, startSignal) = AsyncStream<Void>.makeStream()
    let (release, releaseSignal) = AsyncStream<Void>.makeStream()
    let first = Task {
        await app.queueImageUpdate {
            do {
                try await app.persistPetImages(updated, cleanup: { storage, old, new in
                    startSignal.yield(())
                    for await _ in release {
                        break
                    }
                    await Task.detached { storage.removeObsoleteFiles(from: old, keeping: new) }.value
                })
                return true
            } catch {
                Issue.record(error)
                return false
            }
        }
    }
    var iterator = started.makeAsyncIterator()
    _ = await iterator.next()
    let thumbnails = imageThumbnails(in: row)
    #expect(thumbnails.count == 2)
    #expect(thumbnails.first?.image === frames[1])
    let visibleBIndex = try #require(thumbnails.firstIndex { $0.image === frames[1] })
    let removal = try #require(app.removeImage(at: visibleBIndex, from: .idle))
    releaseSignal.yield(())
    #expect(await first.value)
    await removal.value
    #expect(app.petImages[.idle].count == 1)
    #expect(app.petImages[.idle].first === frames[2])
    #expect(imageThumbnails(in: row).first?.image === frames[2])
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    startSignal.finish()
    releaseSignal.finish()
    app.animationController.shutdown()
}

@MainActor private func imageThumbnails(in view: NSView) -> [NSImageView] {
    if let imageView = view as? NSImageView {
        return [imageView]
    }
    return view.subviews.flatMap { imageThumbnails(in: $0) }
}

private func makeImageFrames() throws -> [NSImage] {
    let context = try #require(CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let raster = try #require(context.makeImage())
    return (0 ..< 3).map { _ in NSImage(cgImage: raster, size: NSSize(width: 2, height: 2)) }
}

@MainActor private func prepareImageRow(
    _ frames: [NSImage], app: AppDelegate, directory: URL
) throws -> PetImageCategoryRowView {
    let previous = PetImageSet([.idle: frames])
    app.importedImages = previous
    let storage = PetImageStorage(directory: directory)
    app.storedImageFiles = try storage.stage(previous, replacing: PetImageSet(), files: [:])
    let row = PetImageCategoryRowView(category: .idle, images: frames)
    app.imageRows[.idle] = row
    return row
}
