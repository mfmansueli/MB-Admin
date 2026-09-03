import Foundation
@testable import MaryBottom

/// Substitui a WebView no logout dos testes.
final class FakeSessionClearer: EnjoeiSessionClearing {
    private(set) var clearCallCount = 0

    // Default-argument expressions (ex.: em `AccountSessionTests.makeAccount`) são avaliadas fora
    // do MainActor — mesma razão do `nonisolated init()` de `InMemoryPostHistoryPersistence`.
    nonisolated init() {}

    func clearSession() async {
        clearCallCount += 1
    }
}
