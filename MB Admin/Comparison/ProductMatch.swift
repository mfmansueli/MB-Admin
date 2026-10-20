import Foundation

/// Um par de produtos — um de cada conta — que a comparação considerou o mesmo item (ou uma
/// variação bem próxima dele).
nonisolated struct ProductMatch: Identifiable, Equatable, Sendable {
    let productA: EnjoeiProduct
    let productB: EnjoeiProduct
    /// De `0` a `1` — o que `ProductSimilarity.score` calculou pros títulos dos dois.
    let similarity: Double

    var id: String { "\(productA.id)-\(productB.id)" }
}
