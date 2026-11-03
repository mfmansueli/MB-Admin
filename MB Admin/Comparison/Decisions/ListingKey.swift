import Foundation

/// Um anúncio, de forma estável entre sessões: a loja (id do vendedor no Enjoei — o mesmo mesmo
/// depois de sair e entrar de novo na conta) e o id do produto.
nonisolated struct ListingKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    let sellerID: Int
    let productID: Int

    static func < (lhs: ListingKey, rhs: ListingKey) -> Bool {
        (lhs.sellerID, lhs.productID) < (rhs.sellerID, rhs.productID)
    }

    var description: String { "\(sellerID):\(productID)" }
}
