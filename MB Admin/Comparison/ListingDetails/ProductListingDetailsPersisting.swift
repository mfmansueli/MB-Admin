import Foundation

/// Onde ficam os `ProductListingDetails` de uma conta.
protocol ProductListingDetailsPersisting: AnyObject {
    func details(for productIDs: [Int]) -> [Int: ProductListingDetails]
    func upsert(_ details: ProductListingDetails)
    /// Esquece tudo desta conta — o "atualizar" da comparação busca cada anúncio de novo.
    func removeAll()
    var count: Int { get }
}
