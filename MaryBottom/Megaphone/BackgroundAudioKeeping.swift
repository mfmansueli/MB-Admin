import Foundation

/// Quem mantém o app acordado em segundo plano. Protocolo para os testes não subirem um motor de
/// áudio de verdade.
@MainActor
protocol BackgroundAudioKeeping: AnyObject {
    /// Ligado quando o app está de fato com tempo de execução garantido.
    var isKeepingAwake: Bool { get }
    /// Chamado quando o áudio é interrompido (uma ligação, por exemplo) e quando volta.
    var onInterruption: ((Bool) -> Void)? { get set }

    func start()
    func stop()
}
