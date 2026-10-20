import AVFoundation
import Foundation

/// Toca silêncio em loop para o iOS não suspender o app em segundo plano.
///
/// É o único jeito de o megafone continuar rodando enquanto você usa outros apps: sem uma sessão de
/// áudio ativa o processo é congelado ao sair da tela. Usamos `.mixWithOthers` de propósito — sua
/// música ou podcast continuam tocando normalmente por cima.
@MainActor
final class SilentAudioSession: BackgroundAudioKeeping {
    private(set) var isKeepingAwake = false
    var onInterruption: ((Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var interruptionObserver: (any NSObjectProtocol)?

    func start() {
        guard !isKeepingAwake else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            try startEngine()
            observeInterruptions()
            isKeepingAwake = true
        } catch {
            isKeepingAwake = false
        }
    }

    func stop() {
        guard isKeepingAwake else { return }
        player.stop()
        engine.stop()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isKeepingAwake = false
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
            // Sem áudio ativo o app volta a poder ser suspenso, então religamos o motor.
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
            player.play()
            onInterruption?(false)
        @unknown default:
            break
        }
    }
}
