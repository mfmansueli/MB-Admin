import Foundation

/// O que fazer com a Live Activity de uma conta quando o resumo da rodada muda. Só uma rodada de
/// verdade abre uma — tocar em "megafonar" passa sempre por "esperando a vez" (ver
/// `MegaphoneRunner.start`); carregar a lista ao abrir a conta também passa por "buscando
/// produtos", mas sozinho, e não deve acender nada na tela bloqueada.
nonisolated enum MegaphoneLiveActivityStep: Equatable, Sendable {
    case start
    case update
    case end
    case none

    static func step(for phase: MegaphonePhase, hasActivity: Bool) -> Self {
        switch phase {
        case .waitingInQueue, .megaphoning, .paused:
            hasActivity ? .update : .start
        case .loadingProducts, .checkingExposure:
            hasActivity ? .update : .none
        case .idle, .finished, .cancelled, .failed:
            hasActivity ? .end : .none
        }
    }
}
