import Foundation

/// Uma linha de `ProductFamily`: uma versão do produto e onde ela está.
nonisolated struct ProductFamilyVersion: Identifiable, Equatable, Sendable {
    nonisolated enum Presence: Int, Comparable, Sendable {
        /// Só na loja A — possivelmente ausente na B.
        case onlyInA = 0
        /// Só na loja B — possivelmente ausente na A.
        case onlyInB = 1
        /// Há um par pra revisar com ela.
        case needsReview = 2
        /// Não deu pra verificar (fotos/template que falharam).
        case unverified = 3
        /// Correspondência forte ou confirmada nas duas lojas.
        case both = 4

        static func < (lhs: Presence, rhs: Presence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// "aro 16 · ródio" — os valores dos eixos que mudam entre as versões da família.
    let label: String
    let productA: EnjoeiProduct?
    let productB: EnjoeiProduct?
    let presence: Presence

    var id: String { "\(productA.map { "\($0.id)" } ?? "-")|\(productB.map { "\($0.id)" } ?? "-")" }
}
