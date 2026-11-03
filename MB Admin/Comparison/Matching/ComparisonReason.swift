import Foundation

/// Por que um par ficou no estado em que ficou — o texto curto que a tela mostra. Nenhum motivo é
/// uma probabilidade.
nonisolated enum ComparisonReason: Hashable, Sendable {
    case samePublicID
    case samePhoto
    case confirmedByUser
    case rejectedByUser
    /// A mesma foto liga mais de dois anúncios (duplicata numa loja, ou a mesma foto reaproveitada).
    case photoUsedByManyListings(Int)
    case closeCompetitor
    case colorVariant
    case similarPhoto
    case similarText
    case nearIdenticalTextDifferentPhotos
    case photosUnavailable
    case sizeDiffers(String, String)
    case categoryDiffers
    case otherListingAlreadyPaired
    case staleDecision

    var text: String {
        switch self {
        case .samePublicID: "o mesmo arquivo de foto nos dois anúncios"
        case .samePhoto: "a mesma foto nos dois anúncios"
        case .confirmedByUser: "você confirmou que é o mesmo produto"
        case .rejectedByUser: "você marcou como produtos diferentes"
        case .photoUsedByManyListings(let count): "a mesma foto liga \(count) anúncios — não dá pra saber sozinho qual é o par"
        case .closeCompetitor: "outro anúncio tem uma foto quase tão parecida"
        case .colorVariant: "a mesma foto, mas com outra cor — pode ser uma variante"
        case .similarPhoto: "fotos parecidas, mas não exatamente a mesma"
        case .similarText: "títulos parecidos"
        case .nearIdenticalTextDifferentPhotos: "texto quase igual, mas nenhuma foto em comum"
        case .photosUnavailable: "as fotos de um dos dois não puderam ser analisadas"
        case .sizeDiffers(let first, let second): "tamanhos diferentes (\(first) × \(second))"
        case .categoryDiffers: "categorias diferentes"
        case .otherListingAlreadyPaired: "um dos dois já tem par com outro anúncio"
        case .staleDecision: "você tinha revisado este par, mas um dos anúncios mudou desde então"
        }
    }
}
