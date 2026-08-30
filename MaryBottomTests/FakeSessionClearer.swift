import Foundation
@testable import MaryBottom

/// Substitui a WebView no logout dos testes.
final class FakeSessionClearer: EnjoeiSessionClearing {
    private(set) var clearCallCount = 0

    func clearSession() async {
        clearCallCount += 1
    }
}
