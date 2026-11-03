import Foundation

/// Por que um anúncio sem par não pôde ser dado como "possivelmente ausente" na outra loja.
nonisolated enum UnverifiedReason: Hashable, Sendable {
    case otherStoreListingIncomplete(storeName: String)
    case detailsUnavailable
    case photosFailed(Int)
    case noUsablePhoto
    /// Um anúncio da outra loja que não deu pra analisar tem título parecido — pode ser o par.
    case possibleUnverifiedCounterpart(title: String)

    var text: String {
        switch self {
        case .otherStoreListingIncomplete(let storeName): "a lista de \(storeName) não veio completa"
        case .detailsUnavailable: "não deu pra buscar todas as fotos do anúncio"
        case .photosFailed(let count): count == 1 ? "1 foto não pôde ser analisada" : "\(count) fotos não puderam ser analisadas"
        case .noUsablePhoto: "sem foto que dê pra comparar"
        case .possibleUnverifiedCounterpart(let title): "pode ser \"\(title)\", da outra loja, que não deu pra analisar"
        }
    }
}
