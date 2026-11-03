import Foundation

/// Uma das duas lojas, pronta pra comparar.
nonisolated struct ComparisonSide: Sendable {
    let sellerID: Int
    let name: String
    let listings: [ComparableListing]
    let status: StoreListingStatus
}
