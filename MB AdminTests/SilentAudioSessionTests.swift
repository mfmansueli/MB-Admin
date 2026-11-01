import AVFoundation
import Foundation
import Testing
@testable import MB_Admin

/// Só o clipe e o player — subir a sessão de áudio de verdade fica de fora de propósito (mesmo motivo
/// de `FakeBackgroundAudio`): os testes não devem tocar áudio nem disputar a sessão do aparelho.
@Suite("áudio silencioso que segura o app")
struct SilentAudioSessionTests {
    @Test("o clipe é um WAV PCM mono de 8 kHz com um segundo de silêncio")
    func clipeEhWAVDeSilencio() {
        let bytes = [UInt8](SilentAudioSession.silentWAVData())

        #expect(bytes.count == 44 + 16_000)
        #expect(Array(bytes[0..<4]) == Array("RIFF".utf8))
        #expect(Array(bytes[8..<12]) == Array("WAVE".utf8))
        #expect(Array(bytes[36..<40]) == Array("data".utf8))
        #expect(bytes[44...].allSatisfy { $0 == 0 })
    }

    @Test("o AVAudioPlayer aceita o clipe e lê o formato certo")
    func playerLeOClipe() throws {
        let player = try AVAudioPlayer(data: SilentAudioSession.silentWAVData())

        #expect(player.numberOfChannels == 1)
        #expect(player.format.sampleRate == 8_000)
        #expect(abs(player.duration - 1) < 0.01)
    }

    @Test("o player sai pronto para tocar em loop sem fim")
    func playerEmLoopInfinito() throws {
        let player = try SilentAudioSession.makeLoopingPlayer()

        #expect(player.numberOfLoops == -1)
        #expect(player.isPlaying == false)
    }
}
