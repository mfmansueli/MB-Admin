import Foundation

/// Um par de produtos — um de cada conta — que a comparação considerou o mesmo item (ou uma
/// variação bem próxima dele).
nonisolated struct ProductMatch: Identifiable, Equatable, Sendable {
    let productA: EnjoeiProduct
    let productB: EnjoeiProduct
    /// De `0` a `1` — o que `ProductSimilarity.score` calculou pros títulos dos dois.
    let similarity: Double

    var id: String { "\(productA.id)-\(productB.id)" }

    /// A partir daqui o par é quase certamente o mesmo produto — o anel fica na cor da ação
    /// principal; abaixo, cinza e com o aviso de conferir antes de tratar como igual.
    static let confidentSimilarity = 0.8

    var isConfident: Bool { similarity >= Self.confidentSimilarity }

    /// O número dentro do anel — de 0 a 100.
    var similarityPercent: Int { Int((similarity * 100).rounded()) }
}
