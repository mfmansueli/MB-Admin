import Foundation
import Testing
@testable import MB_Admin

@Suite("quando abrir, atualizar e encerrar a Live Activity")
struct MegaphoneLiveActivityStepTests {
    @Test("tocar em megafonar (esperando a vez) abre a atividade; com ela aberta, só atualiza")
    func rodadaAbre() {
        #expect(MegaphoneLiveActivityStep.step(for: .waitingInQueue, hasActivity: false) == .start)
        #expect(MegaphoneLiveActivityStep.step(for: .megaphoning(round: 1, of: .once), hasActivity: true) == .update)
        #expect(
            MegaphoneLiveActivityStep.step(for: .paused(round: 1, of: .once, reason: .user), hasActivity: true) == .update
        )
    }

    @Test("carregar a lista ao abrir a conta não acende nada na tela bloqueada")
    func carregarSozinhoNaoAbre() {
        #expect(MegaphoneLiveActivityStep.step(for: .loadingProducts(loaded: 0, total: 0), hasActivity: false) == .none)
        #expect(MegaphoneLiveActivityStep.step(for: .checkingExposure(checked: 0, total: 10), hasActivity: false) == .none)
        #expect(MegaphoneLiveActivityStep.step(for: .loadingProducts(loaded: 10, total: 40), hasActivity: true) == .update)
    }

    @Test("fim, interrupção, erro ou volta ao parado encerram a atividade aberta")
    func fimEncerra() {
        #expect(MegaphoneLiveActivityStep.step(for: .finished, hasActivity: true) == .end)
        #expect(MegaphoneLiveActivityStep.step(for: .cancelled, hasActivity: true) == .end)
        #expect(MegaphoneLiveActivityStep.step(for: .failed("sessão caiu"), hasActivity: true) == .end)
        #expect(MegaphoneLiveActivityStep.step(for: .idle, hasActivity: true) == .end)
        #expect(MegaphoneLiveActivityStep.step(for: .finished, hasActivity: false) == .none)
    }
}
