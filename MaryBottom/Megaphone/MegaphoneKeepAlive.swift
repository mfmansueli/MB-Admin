import Foundation
import UIKit

/// Mantém o megafone vivo enquanto ele roda: impede a tela de dormir, segura o app acordado em
/// segundo plano e pausa a rodada quando o áudio é interrompido (uma ligação, por exemplo).
@MainActor
final class MegaphoneKeepAlive {
    private let runner: MegaphoneRunner
    private let audio: any BackgroundAudioKeeping

    init(runner: MegaphoneRunner, audio: (any BackgroundAudioKeeping)? = nil) {
        self.runner = runner
        self.audio = audio ?? SilentAudioSession()
        self.audio.onInterruption = { [weak self] began in
            began ? self?.runner.pauseForBackground() : self?.runner.resumeFromBackground()
        }
    }

    /// O app continua rodando em segundo plano?
    var keepsRunningInBackground: Bool { audio.isKeepingAwake }

    func start() {
        audio.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = false
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
