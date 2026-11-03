import Foundation

/// Se a listagem de uma loja veio inteira. Só com `.complete` dá pra dizer que um produto da outra
/// loja "possivelmente não existe" nesta — lista faltando pedaço não é prova de ausência.
nonisolated enum StoreListingStatus: Equatable, Sendable, Codable {
    case complete
    /// Veio menos produto do que o `total` que a própria busca informou.
    case incomplete(loaded: Int, expected: Int)
    /// Uma página falhou no meio (ou logo na primeira) — `loaded` é o que veio antes disso.
    case failed(loaded: Int, message: String)

    var allowsAbsenceConclusions: Bool { self == .complete }

    var problemText: String? {
        switch self {
        case .complete: nil
        case .incomplete(let loaded, let expected): "a lista veio com \(loaded) de \(expected) produtos"
        case .failed(let loaded, let message):
            loaded == 0 ? "a lista não carregou (\(message))" : "a lista parou em \(loaded) produtos (\(message))"
        }
    }
}
