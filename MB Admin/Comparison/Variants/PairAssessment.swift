import Foundation

/// O que foto + texto + preço + marca dizem de um par, já medido (`PairAssessor`) — o índice e os
/// fatos que as regras do `ComparisonResolver` usam.
nonisolated struct PairAssessment: Sendable {
    let index: MatchIndex
    /// Eixos em que os dois descrevem versões diferentes (o valor de A primeiro).
    let conflicts: [AttributeDifference]
    /// Eixos em que os dois dizem o mesmo valor.
    let agreements: [VariantDimension]
    /// As concordâncias que dizem algo de verdade — sem o "prata" que quase todo título de joia tem.
    let strongAgreements: [VariantDimension]
    let brandA: String?
    let brandB: String?
    let brandsDiffer: Bool
    let categoriesDiffer: Bool
    let priceRelation: PriceRelation
    let pricesFarApart: Bool
    /// Jaccard das descrições sem vocabulário de variante; `nil` se alguma não foi buscada.
    let descriptionSimilarity: Double?

    /// Algum atributo decisivo em conflito: outra versão do produto, nunca o mesmo anúncio.
    var isVariant: Bool { !conflicts.isEmpty }

    /// O texto confirma um par 1:1 que o preço deixou em dúvida.
    var textConfirms: Bool {
        !strongAgreements.isEmpty || (descriptionSimilarity ?? 0) >= MatchIndexParameters.descriptionConfirmsThreshold
    }
}
