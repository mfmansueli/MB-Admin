import Foundation

/// Um par de anúncios sem ordem — A×B e B×A são o mesmo par, pra uma revisão feita comparando
/// "antonia ↔ loja B" valer também em "loja B ↔ antonia".
nonisolated struct ListingPairKey: Hashable, Sendable {
    let first: ListingKey
    let second: ListingKey

    init(_ one: ListingKey, _ other: ListingKey) {
        if one < other {
            first = one
            second = other
        } else {
            first = other
            second = one
        }
    }

    /// Chave única no disco.
    var storageID: String { "\(first)|\(second)" }
}
