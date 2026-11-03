import Foundation

/// `ProductListingDetailsPersisting` só em memória — testes.
final class InMemoryProductListingDetailsPersistence: ProductListingDetailsPersisting {
    private(set) var stored: [Int: ProductListingDetails]

    init(stored: [ProductListingDetails] = []) {
        self.stored = Dictionary(stored.map { ($0.productID, $0) }, uniquingKeysWith: { $1 })
    }

    func details(for productIDs: [Int]) -> [Int: ProductListingDetails] {
        var result: [Int: ProductListingDetails] = [:]
        for productID in productIDs {
            result[productID] = stored[productID]
        }
        return result
    }

    func upsert(_ details: ProductListingDetails) {
        stored[details.productID] = details
    }

    var count: Int { stored.count }
}
