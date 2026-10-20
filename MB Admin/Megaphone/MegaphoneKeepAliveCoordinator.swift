import Foundation
import UIKit

/// Dono único do "manter acordado" (áudio silencioso + idle timer) do app inteiro.
///
/// `UIApplication.isIdleTimerDisabled` e `AVAudioSession.sharedInstance()` são estado global do
/// processo — com várias contas megafonando em paralelo, cada `MegaphoneKeepAlive` não pode mexer
/// neles diretamente: a conta que termina primeiro desligaria o app inteiro e derrubaria as contas
/// que ainda estão rodando em segundo plano. Este coordenador conta quantas contas estão pedindo
/// para ficar acordado e só liga/desliga de fato quando essa contagem sai de/volta a zero.
@MainActor
final class MegaphoneKeepAliveCoordinator {
    static let shared = MegaphoneKeepAliveCoordinator()

    private let audio: any BackgroundAudioKeeping
    /// Uma interrupção de áudio (uma ligação, por exemplo) é global — todo mundo que está rodando
    /// precisa pausar junto, daí o broadcast para todos os registrados.
    private var interruptionHandlers: [ObjectIdentifier: (Bool) -> Void] = [:]

    init(audio: (any BackgroundAudioKeeping)? = nil) {
        self.audio = audio ?? SilentAudioSession()
        self.audio.onInterruption = { [weak self] began in
            self?.interruptionHandlers.values.forEach { $0(began) }
        }
    }

    var isKeepingAwake: Bool { audio.isKeepingAwake }

    func retain(token: ObjectIdentifier, onInterruption: @escaping (Bool) -> Void) {
        let wasEmpty = interruptionHandlers.isEmpty
        interruptionHandlers[token] = onInterruption
        guard wasEmpty else { return }
        audio.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func release(token: ObjectIdentifier) {
        interruptionHandlers[token] = nil
        guard interruptionHandlers.isEmpty else { return }
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
