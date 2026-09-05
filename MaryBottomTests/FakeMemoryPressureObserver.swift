import Foundation
@testable import MaryBottom

/// Substitui o observador de memória de verdade nos testes — dispara o aviso manualmente em vez de
/// esperar o UIKit de verdade.
final class FakeMemoryPressureObserver: MemoryPressureObserving {
    var onMemoryWarning: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    /// Simula o que o UIKit avisaria numa pressão de memória real.
    func fireMemoryWarning() {
        onMemoryWarning?()
    }
}
