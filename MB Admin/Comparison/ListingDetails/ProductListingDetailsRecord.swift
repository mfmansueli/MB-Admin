import Foundation
import SwiftData

/// `ProductListingDetails` em disco, no `PerAccountModelContainer` da conta (o id do produto só é
/// único dentro da loja). Registro próprio, separado de `MegaphoneItemRecord`: aquela tabela é
/// apagada e regravada inteira a cada carregamento do megafone (`saveItems`), e isso aqui precisa
/// sobreviver a isso.
@Model
final class ProductListingDetailsRecord {
    @Attribute(.unique) var productID: Int
    var coverPublicID: String?
    /// Ids na ordem da posição, separados por `\n` (ids do Enjoei nunca têm quebra de linha).
    var photoPublicIDs: String
    var categoryID: Int?
    var size: String?
    var brand: String?
    var productDescription: String
    var fetchedAt: Date

    init(details: ProductListingDetails) {
        productID = details.productID
        coverPublicID = details.coverPublicID
        photoPublicIDs = details.photoPublicIDs.joined(separator: "\n")
        categoryID = details.categoryID
        size = details.size
        brand = details.brand
        productDescription = details.description
        fetchedAt = details.fetchedAt
    }

    func update(from details: ProductListingDetails) {
        coverPublicID = details.coverPublicID
        photoPublicIDs = details.photoPublicIDs.joined(separator: "\n")
        categoryID = details.categoryID
        size = details.size
        brand = details.brand
        productDescription = details.description
        fetchedAt = details.fetchedAt
    }

    var details: ProductListingDetails {
        ProductListingDetails(
            productID: productID,
            coverPublicID: coverPublicID,
            photoPublicIDs: photoPublicIDs.split(separator: "\n").map(String.init),
            categoryID: categoryID,
            size: size,
            brand: brand,
            description: productDescription,
            fetchedAt: fetchedAt
        )
    }
}
