import Foundation

/// Por que anúncios da mesma loja foram dados como repetidos — ou por que ficaram só como "talvez
/// repetidos". O texto curto que a tela mostra; nenhum motivo é probabilidade.
nonisolated enum DuplicateReason: Hashable, Sendable {
    /// O mesmo arquivo de foto (o mesmo id público) nos anúncios.
    case samePublicID
    case samePhoto
    case samePrice(String)
    /// Algum dos anúncios não teve o template buscado: aro, banho e marca ainda não foram conferidos.
    case detailsMissing
    case priceDiffers(String, String)
    case brandDiffers(String, String)
    case categoryDiffers
    /// Outra foto dos dois bate na forma, mas não na cor.
    case colorVariant
    case confirmedByUser
    case dismissedByUser

    var text: String {
        switch self {
        case .samePublicID: "o mesmo arquivo de foto"
        case .samePhoto: "a mesma foto"
        case .samePrice(let price): "mesmo preço inicial (\(price))"
        case .detailsMissing: "falta a descrição de algum deles pra conferir aro, banho e marca"
        case .priceDiffers(let first, let second): "preço inicial bem diferente (\(first) × \(second)) — pode ser outra versão"
        case .brandDiffers(let first, let second): "marcas diferentes (\(first) × \(second))"
        case .categoryDiffers: "categorias diferentes"
        case .colorVariant: "outra foto bate na forma, mas com outra cor"
        case .confirmedByUser: "você confirmou que são repetidos"
        case .dismissedByUser: "você marcou que não são repetidos"
        }
    }

    /// Deixa o grupo em "talvez repetidos" — a evidência sozinha não basta.
    var isDoubt: Bool {
        switch self {
        case .detailsMissing, .priceDiffers, .brandDiffers, .categoryDiffers, .colorVariant: true
        case .samePublicID, .samePhoto, .samePrice, .confirmedByUser, .dismissedByUser: false
        }
    }
}
