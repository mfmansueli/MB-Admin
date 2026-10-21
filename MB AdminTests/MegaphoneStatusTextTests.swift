import Foundation
import Testing
@testable import MB_Admin

@Suite("texto do andamento do megafone")
struct MegaphoneStatusTextTests {
    private func statusText(
        phase: MegaphonePhase,
        itemsCount: Int = 10,
        processedCount: Int = 0,
        totalSucceeded: Int = 0,
        totalFailed: Int = 0,
        round: Int = 1
    ) -> MegaphoneStatusText {
        MegaphoneStatusText(
            phase: phase,
            itemsCount: itemsCount,
            processedCount: processedCount,
            totalSucceeded: totalSucceeded,
            totalFailed: totalFailed,
            round: round
        )
    }

    @Test("parado, sem progresso")
    func parado() {
        let status = statusText(phase: .idle)
        #expect(status.headline == "pronto para megafonar.")
        #expect(status.progress == nil)
    }

    @Test("buscando produtos mostra o total quando já sabe quantos são")
    func buscandoProdutosComTotal() {
        let status = statusText(phase: .loadingProducts(loaded: 20, total: 80))
        #expect(status.headline == "buscando seus produtos… 20 de 80")
        #expect(status.progress == 0.25)
    }

    @Test("buscando produtos sem total ainda não mostra progresso")
    func buscandoProdutosSemTotal() {
        let status = statusText(phase: .loadingProducts(loaded: 5, total: 0))
        #expect(status.headline == "buscando seus produtos…")
        #expect(status.progress == nil)
    }

    @Test("conferindo exposição mostra quantos já foram conferidos")
    func conferindoExposicao() {
        let status = statusText(phase: .checkingExposure(checked: 30, total: 80))
        #expect(status.headline == "conferindo quais pedem desconto… 30 de 80")
        #expect(status.progress == 0.375)
    }

    @Test("megafonando numa rodada única não menciona rodada")
    func megafonandoRodadaUnica() {
        let status = statusText(
            phase: .megaphoning(round: 1, of: .once),
            itemsCount: 10,
            processedCount: 3
        )
        #expect(status.headline == "megafonando 4 de 10…")
        #expect(status.progress == 0.3)
    }

    @Test("megafonando em várias rodadas menciona a rodada atual")
    func megafonandoVariasRodadas() {
        let status = statusText(
            phase: .megaphoning(round: 2, of: .times(3)),
            itemsCount: 10,
            processedCount: 4
        )
        #expect(status.headline == "rodada 2 de 3 · megafonando 5 de 10…")
        // (2-1)*10 + 4 = 14 de 30.
        #expect(status.progress == 14.0 / 30.0)
    }

    @Test("rodada infinita usa só a rodada atual pro progresso")
    func rodadaInfinita() {
        let status = statusText(
            phase: .megaphoning(round: 5, of: .unlimited),
            itemsCount: 10,
            processedCount: 6
        )
        #expect(status.headline == "rodada 5 · megafonando 7 de 10…")
        #expect(status.progress == 0.6)
    }

    @Test("pausado pelo usuário")
    func pausadoPeloUsuario() {
        let status = statusText(phase: .paused(round: 1, of: .once, reason: .user))
        #expect(status.headline == "pausado — toque em continuar quando quiser.")
    }

    @Test("pausado em segundo plano")
    func pausadoEmSegundoPlano() {
        let status = statusText(phase: .paused(round: 1, of: .once, reason: .background))
        #expect(status.headline == "pausado em segundo plano — volta sozinho quando você reabrir o app.")
    }

    @Test("terminado mostra os totais")
    func terminado() {
        let status = statusText(phase: .finished, totalSucceeded: 78, totalFailed: 2)
        #expect(status.headline == "fim: 78 megafones, 2 com erro.")
        #expect(status.progress == nil)
    }

    @Test("cancelado usa a rodada guardada pelo runner, não a do phase")
    func cancelado() {
        let status = statusText(phase: .cancelled, totalSucceeded: 12, round: 3)
        #expect(status.headline == "interrompido na rodada 3, com 12 megafones.")
        #expect(status.progress == nil)
    }

    @Test("falhou mostra a mensagem do erro")
    func falhou() {
        let status = statusText(phase: .failed("sua sessão do enjoei expirou. entre de novo."))
        #expect(status.headline == "sua sessão do enjoei expirou. entre de novo.")
        #expect(status.progress == nil)
    }

    // MARK: - contagem, rodada e linha curta (painel do megafone e row da conta)

    @Test("megafonando numa rodada única: só a contagem, sem rodada")
    func linhaCurtaRodadaUnica() {
        let status = statusText(phase: .megaphoning(round: 1, of: .once), itemsCount: 340, processedCount: 11)
        #expect(status.count == "12 de 340")
        #expect(status.roundLabel == nil)
        #expect(status.compactLine == "12 de 340")
    }

    @Test("megafonando com várias rodadas: rodada e contagem na linha curta")
    func linhaCurtaVariasRodadas() {
        let status = statusText(phase: .megaphoning(round: 2, of: .times(5)), itemsCount: 340, processedCount: 11)
        #expect(status.count == "12 de 340")
        #expect(status.roundLabel == "rodada 2 de 5")
        #expect(status.compactLine == "rodada 2 de 5 · 12 de 340")
    }

    @Test("megafonando no infinito: rodada sem total")
    func linhaCurtaInfinito() {
        let status = statusText(phase: .megaphoning(round: 3, of: .unlimited), itemsCount: 10, processedCount: 0)
        #expect(status.roundLabel == "rodada 3")
        #expect(status.compactLine == "rodada 3 · 1 de 10")
    }

    @Test("pausado avisa na frente da linha curta")
    func linhaCurtaPausado() {
        let status = statusText(
            phase: .paused(round: 2, of: .times(5), reason: .user),
            itemsCount: 340,
            processedCount: 11
        )
        #expect(status.count == "12 de 340")
        #expect(status.compactLine == "pausado · rodada 2 de 5 · 12 de 340")
    }

    @Test("fora de megafonando/pausado, sem contagem — a linha curta é o próprio texto")
    func linhaCurtaForaDaRodada() {
        let waiting = statusText(phase: .waitingInQueue)
        #expect(waiting.count == nil)
        #expect(waiting.roundLabel == nil)
        #expect(waiting.compactLine == waiting.headline)

        let loading = statusText(phase: .loadingProducts(loaded: 20, total: 80))
        #expect(loading.count == nil)
        #expect(loading.compactLine == "buscando seus produtos… 20 de 80")
    }
}
