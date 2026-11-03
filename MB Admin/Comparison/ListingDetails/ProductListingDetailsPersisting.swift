import Foundation

/// Onde ficam os `ProductListingDetails` de uma conta.
protocol ProductListingDetailsPersisting: AnyObject {
    func details(for productIDs: [Int]) -> [Int: ProductListingDetails]
    func upsert(_ details: ProductListingDetails)
    var count: Int { get }
}
