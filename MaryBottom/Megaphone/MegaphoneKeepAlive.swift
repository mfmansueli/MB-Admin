import Foundation

/// Mantém o megafone vivo enquanto ele roda: impede a tela de dormir, segura o app acordado em
/// segundo plano e pausa a rodada quando o áudio é interrompido (uma ligação, por exemplo).
@MainActor
final class MegaphoneKeepAlive {
    private let runner: MegaphoneRunner
    private let coordinator: MegaphoneKeepAliveCoordinator
    private var token: ObjectIdentifier { ObjectIdentifier(self) }

    init(runner: MegaphoneRunner, coordinator: MegaphoneKeepAliveCoordinator? = nil) {
        self.runner = runner
        self.coordinator = coordinator ?? .shared
    }

    /// O app continua rodando em segundo plano?
    var keepsRunningInBackground: Bool { coordinator.isKeepingAwake }

    func start() {
        coordinator.retain(token: token) { [weak self] began in
            began ? self?.runner.pauseForBackground() : self?.runner.resumeFromBackground()
        }
    }

    func stop() {
        coordinator.release(token: token)
    }

    /// O app saiu de vista. Sem áudio segurando, o iOS congela o processo — então paramos no lugar
    /// em vez de acumular erro.
    func applicationWentToBackground() {
        guard !keepsRunningInBackground else { return }
        runner.pauseForBackground()
    }

    func applicationBecameActive() {
        runner.resumeFromBackground()
    }
}
