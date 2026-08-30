import Foundation

/// Em que ponto está a busca por produtos que pedem decisão de desconto.
nonisolated enum DiscountCandidatesPhase: Equatable, Sendable {
    case idle
    /// Buscando a lista de produtos da loja (vem paginada).
    case loadingProducts(loaded: Int, total: Int)
    /// Consultando a exposição de cada produto já carregado, em lotes.
    case checkingExposure(checked: Int, total: Int)
    case loaded
    case failed(String)

    var isActive: Bool {
        switch self {
        case .loadingProducts, .checkingExposure: true
        case .idle, .loaded, .failed: false
        }
    }
}
