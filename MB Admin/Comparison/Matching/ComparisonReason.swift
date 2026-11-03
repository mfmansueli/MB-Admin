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
    /// Atributos que descrevem versões diferentes ("aro 16 × aro 18") — num par confirmado ou
    /// rejeitado por você; sem revisão, esse par nem vira revisão (é outra versão).
    case attributesDiffer(String)
    case brandDiffers(String, String)
    /// Preço inicial bem diferente num par 1:1 que o texto não confirma.
    case priceDiffers(String, String)
    /// A mesma foto liga outras versões, e os atributos/preço/texto apontam só este par.
    case versionResolved(String?)
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
        case .attributesDiffer(let differences): "versões diferentes: \(differences)"
        case .brandDiffers(let first, let second): "marcas diferentes (\(first) × \(second))"
        case .priceDiffers(let first, let second): "preço inicial bem diferente (\(first) × \(second)) — pode ser outra versão"
        case .versionResolved(let label?): "a mesma foto está em outros anúncios; só este par bate em \(label)"
        case .versionResolved(nil): "a mesma foto está em outros anúncios; este par é o que mais bate no título, na descrição e no preço inicial"
        case .categoryDiffers: "categorias diferentes"
        case .otherListingAlreadyPaired: "um dos dois já tem par com outro anúncio"
        case .staleDecision: "você tinha revisado este par, mas um dos anúncios mudou desde então"
        }
    }
}
