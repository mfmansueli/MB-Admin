import Foundation

/// Quem avisa quando o sistema sinaliza pressão de memória de verdade. Protocolo para os testes não
/// depender de provocar um aviso de memória real do UIKit.
@MainActor
protocol MemoryPressureObserving: AnyObject {
    /// Chamado a cada aviso de memória reportado pelo sistema, enquanto `start()` estiver ativo.
    var onMemoryWarning: (() -> Void)? { get set }

    func start()
    func stop()
}
