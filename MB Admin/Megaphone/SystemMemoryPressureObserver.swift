import Foundation
import UIKit

/// Observa o aviso de memória de verdade do UIKit — o mesmo que Debug ▸ Simulate Memory Warning
/// dispara no Simulador/dispositivo, o que dá pra validar sem precisar esperar o aparelho chegar
/// nesse ponto sozinho.
@MainActor
final class SystemMemoryPressureObserver: MemoryPressureObserving {
    var onMemoryWarning: (() -> Void)?
    private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onMemoryWarning?()
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
