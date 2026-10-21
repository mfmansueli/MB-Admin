import Foundation
import Testing
@testable import MB_Admin

@Suite("linha de status da conta na lista")
struct AccountStatusLineTests {
    private func line(
        sessionStatus: AccountSessionStatus = .active,
        crossAccountActivity: String? = nil,
        snapshot: MegaphoneProgressSnapshot = MegaphoneProgressSnapshot(),
        lastRoundSummary: MegaphoneRoundSummary? = nil,
        now: Date = Date(timeIntervalSince1970: 10_000)
    ) -> AccountStatusLine {
        AccountStatusLine(
            sessionStatus: sessionStatus,
            crossAccountActivity: crossAccountActivity,
            snapshot: snapshot,
            lastRoundSummary: lastRoundSummary,
            now: now
        )
    }

    @Test("sessão expirada fala mais alto que o megafone, em vermelho com o triângulo")
    func sessaoExpirada() {
        let status = line(
            sessionStatus: .sessionExpired,
            snapshot: MegaphoneProgressSnapshot(phase: .megaphoning(round: 1, of: .once), itemsCount: 10)
        )
        #expect(status.text == "sessão expirada — toque para entrar de novo")
        #expect(status.role == .failure)
        #expect(status.symbol == .warning)
        #expect(status.progress == nil)
    }

    @Test("sessão não conferida também é falha, com o convite pra tentar de novo")
    func sessaoNaoConferida() {
        let status = line(sessionStatus: .checkFailed)
        #expect(status.text == "não deu pra conferir a sessão — toque para tentar de novo")
        #expect(status.role == .failure)
    }

    @Test("ação da fila em voo aparece como em andamento, antes do megafone")
    func acaoDaFila() {
        let status = line(
            crossAccountActivity: "apagando \"colar\"…",
            snapshot: MegaphoneProgressSnapshot(phase: .megaphoning(round: 1, of: .once), itemsCount: 10)
        )
        #expect(status.text == "apagando \"colar\"…")
        #expect(status.role == .inProgress)
        #expect(status.symbol == nil)
    }

    @Test("megafonando: linha curta, cor de em andamento, ícone pulsando e anel de progresso")
    func megafonando() {
        let status = line(snapshot: MegaphoneProgressSnapshot(
            phase: .megaphoning(round: 2, of: .times(5)),
            itemsCount: 340,
            processedCount: 11,
            round: 2
        ))
        #expect(status.text == "rodada 2 de 5 · 12 de 340")
        #expect(status.role == .inProgress)
        #expect(status.symbol == .megaphone)
        #expect(status.isAnimating)
        #expect(status.progress != nil)
    }

    @Test("esperando a vez: relógio, texto de apoio, sem pulsar nem anel")
    func esperandoAVez() {
        let status = line(snapshot: MegaphoneProgressSnapshot(phase: .waitingInQueue))
        #expect(status.text == "esperando a vez pra megafonar…")
        #expect(status.role == .supporting)
        #expect(status.symbol == .clock)
        #expect(!status.isAnimating)
        #expect(status.progress == nil)
    }

    @Test("pausado: mantém o anel, mas não pulsa")
    func pausado() {
        let status = line(snapshot: MegaphoneProgressSnapshot(
            phase: .paused(round: 1, of: .once, reason: .user),
            itemsCount: 10,
            processedCount: 4
        ))
        #expect(status.text == "pausado · 5 de 10")
        #expect(status.role == .supporting)
        #expect(status.symbol == .pause)
        #expect(!status.isAnimating)
        #expect(status.progress == 0.4)
    }

    @Test("parado mostra o resumo da última rodada, sem ícone")
    func paradoComResumo() {
        let now = Date(timeIntervalSince1970: 10_000)
        let summary = MegaphoneRoundSummary(succeeded: 338, failed: 2, finishedAt: now.addingTimeInterval(-7200))
        let status = line(snapshot: MegaphoneProgressSnapshot(phase: .finished), lastRoundSummary: summary, now: now)
        #expect(status.text == summary.summaryText(now: now))
        #expect(status.role == .supporting)
        #expect(status.symbol == nil)
        #expect(status.progress == nil)
    }

    @Test("parado sem nenhuma rodada ainda")
    func paradoSemResumo() {
        let status = line()
        #expect(status.text == "ainda não megafonado")
        #expect(status.role == .supporting)
    }
}
