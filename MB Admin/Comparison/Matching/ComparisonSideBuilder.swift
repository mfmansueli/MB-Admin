import Foundation

/// Monta as duas lojas prontas pra comparar (`ComparisonSide`) fora do MainActor — tokenizar e ler
/// aro/banho/marca de milhares de anúncios travava a tela quando rodava nele.
nonisolated enum ComparisonSideBuilder {
    /// O que vira um `ComparisonSide`, já tirado das contas (que são do MainActor).
    nonisolated struct Source: Sendable {
        let sellerID: Int
        let name: String
        let products: [EnjoeiProduct]
        let details: [Int: ProductListingDetails]
        let detailsFailures: [Int: String]
        let status: StoreListingStatus
    }

    @concurrent
    static func build(_ sourceA: Source, _ sourceB: Source, photos: PhotoAnalysisBatch) async -> (ComparisonSide, ComparisonSide) {
        (side(sourceA, photos: photos), side(sourceB, photos: photos))
    }

    static func side(_ source: Source, photos: PhotoAnalysisBatch) -> ComparisonSide {
        ComparisonSide(
            sellerID: source.sellerID,
            name: source.name,
            listings: source.products.map { product in
                ComparableListing(
                    sellerID: source.sellerID,
                    product: product,
                    details: source.details[product.id],
                    detailsFailure: source.detailsFailures[product.id],
                    signatures: photos.signatures,
                    failures: photos.failures
                )
            },
            status: source.status
        )
    }
}
