import Foundation
import Testing
@testable import MB_Admin

@Suite("opções de repetição")
struct MegaphoneRoundsTests {
    @Test("as opções do menu vão de uma vez até infinito")
    func presets() {
        #expect(MegaphoneRounds.presets.map(\.rawValue) == [1, 5, 10, 20, 50, 100, 0])
        #expect(MegaphoneRounds.presets.map(\.label).last == "infinito")
        #expect(MegaphoneRounds.times(5).label == "5 vezes")
        #expect(MegaphoneRounds.once.label == "1 vez")
    }

    @Test("infinito nunca fecha a conta")
    func infinitoSempreIncluiARodada() {
        #expect(MegaphoneRounds.unlimited.isUnlimited)
        #expect(MegaphoneRounds.unlimited.includes(round: 1))
        #expect(MegaphoneRounds.unlimited.includes(round: 9_999))
    }

    @Test("um número fecha a conta na última rodada")
    func numeroLimitaAsRodadas() {
        let rounds = MegaphoneRounds.times(3)

        #expect(rounds.includes(round: 3))
        #expect(rounds.includes(round: 4) == false)
        // Valor inválido vira uma volta só, em vez de nenhuma.
        #expect(MegaphoneRounds.times(-2).rawValue == 1)
    }
}
