import Foundation
@testable import MaryBottom

/// Substitui o áudio silencioso nos testes do keep-alive.
final class FakeBackgroundAudio: BackgroundAudioKeeping {
    var isKeepingAwake = false
    var onInterruption: ((Bool) -> Void)?
    /// Simula o caso em que a sessão de áudio não sobe (aparelho ocupado, por exemplo).
    var failsToStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
        isKeepingAwake = !failsToStart
    }

    func stop() {
        stopCount += 1
        isKeepingAwake = false
    }

    /// Dispara o que o `AVAudioSession` avisaria numa ligação recebida e no fim dela.
    func interrupt(began: Bool) {
        if began { isKeepingAwake = false }
        onInterruption?(began)
    }
}
