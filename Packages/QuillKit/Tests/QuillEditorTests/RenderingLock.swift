import Testing

/// Das Theme des Editors gilt prozessweit (`EditorThemeState`). Tests, die zeichnen
/// oder das Theme wechseln, laufen deshalb nacheinander, auch über Suites hinweg.
struct RenderingLock: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> RenderingLock? {
        // Nur um einzelne Testfälle, nicht zusätzlich um die Suite: Das sperrte sich selbst.
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        await RenderingGate.shared.acquire()
        do {
            try await function()
        } catch {
            await RenderingGate.shared.release()
            throw error
        }
        await RenderingGate.shared.release()
    }
}

extension Trait where Self == RenderingLock {
    static var renderingLock: RenderingLock { RenderingLock() }
}

private actor RenderingGate {
    static let shared = RenderingGate()
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
