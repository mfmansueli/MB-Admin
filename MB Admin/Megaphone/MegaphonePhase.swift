import Foundation

/// Em que ponto está o megafone.
nonisolated enum MegaphonePhase: Equatable, Sendable {
    case idle
    /// Esperando a vez pra megafonar de verdade — só uma conta por vez faz o trabalho pesado (rede
    /// + JS via WebView), pra várias contas megafonando juntas não sobrecarregarem o aparelho. Ver
    /// `MegaphoneQueue`.
    case waitingInQueue
    /// Buscando a lista de produtos da loja (vem paginada).
    case loadingProducts(loaded: Int, total: Int)
    /// Conferindo, em lotes, quais produtos já carregados pedem decisão de desconto.
    case checkingExposure(checked: Int, total: Int)
    case megaphoning(round: Int, of: MegaphoneRounds)
    case paused(round: Int, of: MegaphoneRounds, reason: MegaphonePauseReason)
    case finished
    case cancelled
    /// Interrompido por um erro que não adianta insistir (sessão caiu, falhas seguidas).
    case failed(String)

    var isActive: Bool {
        switch self {
        case .waitingInQueue, .loadingProducts, .checkingExposure, .megaphoning, .paused: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }
}
