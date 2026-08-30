import Foundation

/// Em que ponto está o megafone.
nonisolated enum MegaphonePhase: Equatable, Sendable {
    case idle
    /// Buscando a lista de produtos da loja (vem paginada).
    case loadingProducts(loaded: Int, total: Int)
    case megaphoning(round: Int, of: MegaphoneRounds)
    case paused(round: Int, of: MegaphoneRounds, reason: MegaphonePauseReason)
    case finished
    case cancelled
    /// Interrompido por um erro que não adianta insistir (sessão caiu, falhas seguidas).
    case failed(String)

    var isActive: Bool {
        switch self {
        case .loadingProducts, .megaphoning, .paused: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }
}
