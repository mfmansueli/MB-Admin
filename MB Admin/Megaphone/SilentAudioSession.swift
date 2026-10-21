import AVFoundation
import Foundation

/// Toca silêncio em loop para o iOS não suspender o app em segundo plano.
///
/// É o único jeito de o megafone continuar rodando enquanto você usa outros apps: sem uma sessão de
/// áudio ativa o processo é congelado ao sair da tela. Usamos `.mixWithOthers` de propósito — sua
/// música ou podcast continuam tocando normalmente por cima.
///
/// Ativar e desativar a sessão (`setActive`) roda fora da thread principal, em `sessionQueue`: a
/// chamada segura quem chama enquanto o sistema reconfigura o áudio, e na principal isso travava a
/// tela ao tocar em megafonar/parar — o próprio sistema avisa no console ("This method can lead to
/// UI unresponsiveness if called on the main thread"). O motor de áudio só liga depois, de volta na
/// principal, com a sessão já ativa.
@MainActor
final class SilentAudioSession: BackgroundAudioKeeping {
    private(set) var isKeepingAwake = false
    var onInterruption: ((Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var interruptionObserver: (any NSObjectProtocol)?
    /// Serial: uma desativação pedida enquanto a ativação ainda roda sempre acontece depois dela.
    private let sessionQueue = DispatchQueue(label: "br.com.mbadmin.silent-audio-session")
    /// Ativação pedida, ainda sem resposta da `sessionQueue`.
    private var isActivating = false
    /// Muda a cada `start`/`stop` — uma ativação que responde depois de um `stop` mais novo não liga
    /// o motor por cima dele.
    private var generation = 0

    func start() {
        guard !isKeepingAwake, !isActivating else { return }
        generation += 1
        let requestedGeneration = generation
        isActivating = true
        // `self` forte: quem é dono disto (`MegaphoneKeepAliveCoordinator.shared`) vive o app
        // inteiro, então segurar até a resposta da fila não prende nada além do que já existe.
        sessionQueue.async {
            let isActive = Self.activateSession()
            Task { @MainActor in
                self.finishStarting(isSessionActive: isActive, generation: requestedGeneration)
            }
        }
    }

    func stop() {
        guard isKeepingAwake || isActivating else { return }
        generation += 1
        isActivating = false
        if isKeepingAwake {
            player.stop()
            engine.stop()
            if let interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
            }
            interruptionObserver = nil
            isKeepingAwake = false
        }
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func finishStarting(isSessionActive: Bool, generation requestedGeneration: Int) {
        guard requestedGeneration == generation else { return }
        isActivating = false
        guard isSessionActive else { return }
        do {
            try startEngine()
            observeInterruptions()
            isKeepingAwake = true
        } catch {
            sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    nonisolated private static func activateSession() -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func startEngine() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else {
            throw AVError(.unknown)
        }
        // Buffer recém-criado já vem zerado: um segundo de silêncio, repetido sem parar.
        buffer.frameLength = buffer.frameCapacity

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }

        switch type {
        case .began:
            onInterruption?(true)
        case .ended:
            // Sem áudio ativo o app volta a poder ser suspenso, então religamos a sessão (fora da
            // principal, como no `start`) e depois o motor.
            let requestedGeneration = generation
            sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(true)
                Task { @MainActor in
                    self.resumeAfterInterruption(generation: requestedGeneration)
                }
            }
        @unknown default:
            break
        }
    }

    private func resumeAfterInterruption(generation requestedGeneration: Int) {
        guard requestedGeneration == generation, isKeepingAwake else { return }
        try? engine.start()
        player.play()
        onInterruption?(false)
    }
}
