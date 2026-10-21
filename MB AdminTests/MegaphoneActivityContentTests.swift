import Foundation
import Testing
@testable import MB_Admin

@Suite("o que a Live Activity mostra")
struct MegaphoneActivityContentTests {
    private func snapshot(
        phase: MegaphonePhase,
        itemsCount: Int = 340,
        processedCount: Int = 11,
        succeeded: Int = 9,
        failed: Int = 2,
        discount: Int = 3,
        round: Int = 2
    ) -> MegaphoneProgressSnapshot {
        MegaphoneProgressSnapshot(
            phase: phase,
            itemsCount: itemsCount,
            processedCount: processedCount,
            totalSucceeded: succeeded,
            totalFailed: failed,
            round: round,
            discountDecisionCount: discount
        )
    }

    @Test("megafonando: o produto da vez, a rodada, o andamento e o que pede atenção")
    func megafonando() {
        let content = MegaphoneActivityContent(snapshot: snapshot(phase: .megaphoning(round: 2, of: .times(5))))

        #expect(content.title == "12 de 340")
        #expect(content.compactText == "12/340")
        #expect(content.roundText == "rodada 2 de 5")
        #expect(content.detailText == "2 com erro · 3 pedem desconto")
        #expect(content.progress != nil)
        #expect(!content.isPaused)
        #expect(!content.isFinished)
    }

    @Test("pausado marca a pausa; uma rodada só não fala de rodada")
    func pausadoRodadaUnica() {
        let content = MegaphoneActivityContent(snapshot: snapshot(phase: .paused(round: 1, of: .once, reason: .user)))

        #expect(content.isPaused)
        #expect(content.roundText == nil)
    }

    @Test("no fim da rodada o produto da vez não passa do total")
    func naoPassaDoTotal() {
        let content = MegaphoneActivityContent(
            snapshot: snapshot(phase: .megaphoning(round: 1, of: .once), processedCount: 340)
        )

        #expect(content.title == "340 de 340")
    }

    @Test("sem erro nem desconto, não sobra linha de detalhe")
    func semDetalhe() {
        let content = MegaphoneActivityContent(
            snapshot: snapshot(phase: .megaphoning(round: 1, of: .once), failed: 0, discount: 0)
        )

        #expect(content.detailText == nil)
    }

    @Test("antes de começar, diz o que está fazendo, sem número")
    func antesDeComecar() {
        let waiting = MegaphoneActivityContent(snapshot: snapshot(phase: .waitingInQueue))
        #expect(waiting.title == "esperando a vez")
        #expect(waiting.compactText == "…")
        #expect(waiting.progress == nil)

        let loading = MegaphoneActivityContent(snapshot: snapshot(phase: .loadingProducts(loaded: 10, total: 40)))
        #expect(loading.title == "buscando produtos")
        #expect(loading.progress == 0.25)
    }

    @Test("fim: quantos megafones, com a atividade marcada como encerrada")
    func fim() {
        let content = MegaphoneActivityContent(snapshot: snapshot(phase: .finished, succeeded: 338))

        #expect(content.title == "338 megafones")
        #expect(content.isFinished)
        #expect(content.progress == 1)
    }

    @Test("parou com erro mostra a mensagem")
    func parouComErro() {
        let content = MegaphoneActivityContent(snapshot: snapshot(phase: .failed("sessão expirada")))

        #expect(content.title == "parou com erro")
        #expect(content.detailText == "sessão expirada")
        #expect(content.isFinished)
    }

    @Test("interrompido conta o que já tinha sido feito")
    func interrompido() {
        let content = MegaphoneActivityContent(snapshot: snapshot(phase: .cancelled, succeeded: 120, failed: 0, discount: 0))

        #expect(content.title == "interrompido")
        #expect(content.detailText == "120 megafones")
    }
}
