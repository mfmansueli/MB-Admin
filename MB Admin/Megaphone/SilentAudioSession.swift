import AVFoundation
import Foundation

/// Toca silêncio em loop para o iOS não suspender o app em segundo plano.
///
/// É o único jeito de o megafone continuar rodando enquanto você usa outros apps: sem uma sessão de
/// áudio ativa o processo é congelado ao sair da tela. Usamos `.mixWithOthers` de propósito — sua
/// música ou podcast continuam tocando normalmente por cima.
///
/// `AVAudioPlayer`, não `AVAudioEngine`: o motor renderiza o áudio *dentro do processo do app*, numa
/// thread de I/O (`AURemoteIO::IOThread`) acordada a cada ciclo do hardware — e era essa thread,
/// mixando e copiando silêncio, a mais pesada do app nos relatórios de CPU de um iPad real. Em
/// segundo plano o iOS mata o app que passa de 80% de CPU em 60s (`cpu_resource_fatal`), e foi isso
/// que derrubou o app depois de um tempo megafonando com ele fora da tela. O `AVAudioPlayer` entrega
/// o áudio ao servidor de áudio do sistema, que mixa fora do nosso processo; aqui só sobra reabastecer
/// o buffer de vez em quando, com um clipe minúsculo (ver `silentWAVData`).
///
/// Toda chamada de áudio (`AVAudioSession` e o player) roda em `sessionQueue`, nunca na principal:
/// essas chamadas seguram quem chama enquanto o sistema reconfigura o áudio — na principal isso
/// travava a tela ao tocar em megafonar/parar, e um `stop()` preso esperando a thread de áudio já fez
/// o watchdog do iOS matar o app (`0x8BADF00D`). O estado que a tela lê fica na principal; a fila só
/// avisa o resultado de volta.
@MainActor
final class SilentAudioSession: BackgroundAudioKeeping {
    private(set) var isKeepingAwake = false
    var onInterruption: ((Bool) -> Void)?

    /// Só lido/escrito dentro de `sessionQueue` — daí `nonisolated(unsafe)`: a fila serial é quem
    /// garante o acesso exclusivo, não o `MainActor`.
    nonisolated(unsafe) private var player: AVAudioPlayer?
    private var observers: [any NSObjectProtocol] = []
    /// Serial: uma desativação pedida enquanto a ativação ainda roda sempre acontece depois dela.
    private let sessionQueue = DispatchQueue(label: "br.com.mbadmin.silent-audio-session")
    /// Ativação pedida, ainda sem resposta da `sessionQueue`.
    private var isActivating = false
    /// Muda a cada `start`/`stop` — uma ativação que responde depois de um `stop` mais novo não marca
    /// o app como acordado por cima dele (o `stop` já enfileirou o desligamento depois dela).
    private var generation = 0

    func start() {
        guard !isKeepingAwake, !isActivating else { return }
        generation += 1
        let requestedGeneration = generation
        isActivating = true
        // `self` forte: quem é dono disto (`MegaphoneKeepAliveCoordinator.shared`) vive o app
        // inteiro, então segurar até a resposta da fila não prende nada além do que já existe.
        sessionQueue.async {
            let isPlaying = self.activateAndPlay()
            if !isPlaying { self.stopAndDeactivate() }
            Task { @MainActor in
                self.finishStarting(isPlaying: isPlaying, generation: requestedGeneration)
            }
        }
    }

    func stop() {
        guard isKeepingAwake || isActivating else { return }
        generation += 1
        isActivating = false
        isKeepingAwake = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        sessionQueue.async {
            self.stopAndDeactivate()
        }
    }

    private func finishStarting(isPlaying: Bool, generation requestedGeneration: Int) {
        guard requestedGeneration == generation else { return }
        isActivating = false
        guard isPlaying else { return }
        observeAudioSession()
        isKeepingAwake = true
    }

    /// Um segundo de silêncio num WAV PCM de 16 bits, mono, a 8 kHz — 16 KB. Taxa baixa de propósito:
    /// ninguém ouve, e quanto menos amostras por segundo, menos o app tem pra entregar ao sistema.
    nonisolated static func silentWAVData(sampleRate: Int = 8_000, seconds: Int = 1) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = sampleRate * seconds * blockAlign
        var data = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * blockAlign))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        // `Data(count:)` já vem zerado: silêncio digital.
        data.append(Data(count: dataSize))
        return data
    }

    /// O player do clipe de silêncio, já em loop infinito.
    nonisolated static func makeLoopingPlayer() throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: silentWAVData(), fileTypeHint: AVFileType.wav.rawValue)
        player.numberOfLoops = -1
        player.prepareToPlay()
        return player
    }

    // MARK: - Só em `sessionQueue`

    /// Ativa a sessão e põe o silêncio pra tocar — reaproveita o player que já existe (a volta de uma
    /// interrupção só precisa dar play de novo).
    nonisolated private func activateAndPlay() -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            let player = try player ?? Self.makeLoopingPlayer()
            self.player = player
            return player.isPlaying || player.play()
        } catch {
            return false
        }
    }

    nonisolated private func stopAndDeactivate() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Avisos do sistema

    private func observeAudioSession() {
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                MainActor.assumeIsolated {
                    self?.handleInterruption(rawValue: rawValue)
                }
            },
            // O servidor de mídia do sistema reiniciou (raro, mas acontece numa sessão de horas):
            // todo objeto de áudio criado antes morreu junto, e a sessão precisa ser configurada do
            // zero. Sem isso o silêncio para calado e o iOS volta a poder suspender o app.
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rebuildAfterMediaServicesReset()
                }
            }
        ]
    }

    private func handleInterruption(rawValue: UInt?) {
        guard let rawValue, let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }

        switch type {
        case .began:
            onInterruption?(true)
        case .ended:
            // Sem áudio ativo o app volta a poder ser suspenso, então religamos a sessão e o player
            // (fora da principal, como no `start`).
            let requestedGeneration = generation
            sessionQueue.async {
                _ = self.activateAndPlay()
                Task { @MainActor in
                    guard requestedGeneration == self.generation, self.isKeepingAwake else { return }
                    self.onInterruption?(false)
                }
            }
        @unknown default:
            break
        }
    }

    private func rebuildAfterMediaServicesReset() {
        guard isKeepingAwake else { return }
        sessionQueue.async {
            self.player = nil
            _ = self.activateAndPlay()
        }
    }
}
