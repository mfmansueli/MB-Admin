import Foundation
import Testing
@testable import MaryBottom

@Suite("resumo da última rodada de megafone")
struct MegaphoneRoundSummaryTests {
    @Test("mostra sucesso, falha e há quanto tempo terminou")
    func textoDoResumo() {
        let now = Date(timeIntervalSince1970: 10_000)
        let summary = MegaphoneRoundSummary(
            succeeded: 78,
            failed: 2,
            finishedAt: now.addingTimeInterval(-3 * 3600)
        )

        let text = summary.summaryText(now: now)

        #expect(text.hasPrefix("78 sucesso, 2 falha, "))
    }

    @Test("é igual quando os três campos são iguais")
    func igualdade() {
        let date = Date(timeIntervalSince1970: 10_000)
        let a = MegaphoneRoundSummary(succeeded: 5, failed: 1, finishedAt: date)
        let b = MegaphoneRoundSummary(succeeded: 5, failed: 1, finishedAt: date)
        #expect(a == b)
    }

    @Test("sobrevive a ida e volta por Codable")
    func codable() throws {
        let summary = MegaphoneRoundSummary(
            succeeded: 5,
            failed: 1,
            finishedAt: Date(timeIntervalSince1970: 10_000)
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(MegaphoneRoundSummary.self, from: data)

        #expect(decoded == summary)
    }
}
