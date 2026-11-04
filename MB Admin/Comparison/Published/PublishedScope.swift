import Foundation

/// A listagem de uma loja numa comparação (os ids e quando foi buscada) e o que dela já saiu da vitrine
/// (`PublishedListingFilter`). Guardado com o resultado, pra saber — sem refazer nada — se algo que o
/// app viu depois (fila de ações, aba inativos) muda o recorte de publicados.
nonisolated struct PublishedScope: Equatable, Sendable {
    let listedIDs: [Int]
    let listedAt: Date
    /// Os da listagem que não estão mais publicados.
    let unpublished: Set<Int>

    init(listedIDs: [Int], listedAt: Date, changes: [ListingStateChange]) {
        self.listedIDs = listedIDs
        self.listedAt = listedAt
        unpublished = PublishedListingFilter.unpublished(listedIDs: listedIDs, listedAt: listedAt, changes: changes)
    }

    init(_ listing: StoreListing, changes: [ListingStateChange]) {
        self.init(listedIDs: listing.products.map(\.id), listedAt: listing.listedAt, changes: changes)
    }

    init(_ side: ComparisonSide, listedAt: Date, changes: [ListingStateChange]) {
        self.init(listedIDs: side.listings.map(\.product.id), listedAt: listedAt, changes: changes)
    }

    /// A mesma listagem, com o que se sabe agora.
    func refreshed(with changes: [ListingStateChange]) -> PublishedScope {
        PublishedScope(listedIDs: listedIDs, listedAt: listedAt, changes: changes)
    }

    /// Só os publicados, na mesma ordem.
    func published(_ products: [EnjoeiProduct]) -> [EnjoeiProduct] {
        unpublished.isEmpty ? products : products.filter { !unpublished.contains($0.id) }
    }
}
