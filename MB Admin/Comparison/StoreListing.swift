import Foundation

/// A listagem de uma loja como a comparação recebeu: os produtos que vieram, se veio inteira e quando
/// foi buscada (o que o app vê sair da vitrine depois disso tira o produto da comparação — ver
/// `PublishedListingFilter`).
nonisolated struct StoreListing: Sendable {
    let products: [EnjoeiProduct]
    let status: StoreListingStatus
    /// Quando a busca da primeira página começou.
    let listedAt: Date

    init(products: [EnjoeiProduct], status: StoreListingStatus, listedAt: Date = Date()) {
        self.products = products
        self.status = status
        self.listedAt = listedAt
    }
}
