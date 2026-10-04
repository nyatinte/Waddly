import Testing
@testable import WaddlyApp

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
