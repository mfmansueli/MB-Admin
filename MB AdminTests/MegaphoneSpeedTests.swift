import Foundation
import Testing
@testable import MB_Admin

@Suite("intervalo entre megafones")
struct MegaphoneSpeedTests {
    @Test("não desce abaixo do piso de 0,1s")
    func respeitaOPiso() {
        #expect(MegaphoneSpeed(milliseconds: 50).milliseconds == 100)
        #expect(MegaphoneSpeed(milliseconds: 0).milliseconds == 100)
        #expect(MegaphoneSpeed(milliseconds: -1).milliseconds == 100)
        #expect(MegaphoneSpeed(milliseconds: 200).milliseconds == 200)
        #expect(MegaphoneSpeed.fastest.milliseconds == MegaphoneSpeed.minimumMilliseconds)
    }

    @Test("as opções vão da mais rápida à mais cautelosa")
    func presets() {
        let valores = MegaphoneSpeed.presets.map(\.milliseconds)

        #expect(valores == [100, 200, 300, 500, 900, 1_500, 3_000])
        #expect(valores == valores.sorted())
        #expect(MegaphoneSpeed.presets.contains(.standard))
    }

    @Test("vira a pausa que o runner usa entre um produto e o próximo")
    func viraDuracao() {
        #expect(MegaphoneSpeed(milliseconds: 1_500).duration == .milliseconds(1_500))
        #expect(MegaphoneSpeed(milliseconds: 900).seconds == 0.9)
        #expect(MegaphoneSpeed(milliseconds: 100).duration == .milliseconds(100))
    }

    @Test("rótulo das opções rápidas", arguments: [(100, 0.1), (200, 0.2)])
    func rotuloRapido(milliseconds: Int, seconds: Double) {
        let speed = MegaphoneSpeed(milliseconds: milliseconds)
        #expect(speed.seconds == seconds)
        #expect(speed.label == "\(seconds.formatted(.number.precision(.fractionLength(1))))s")
    }
}
