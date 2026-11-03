import Foundation

/// O que o template de um anúncio (`EnjoeiClientProtocol.productTemplate`, uma chamada por
/// produto) traz que a listagem da loja não traz: todas as fotos com a posição, categoria, tamanho,
/// marca e descrição. Salvo por anúncio (`ProductListingDetailsPersisting`) pra nunca buscar de novo
/// sem motivo.
///
/// A listagem (`searchProductsForStore`) só devolve a capa (`photo.image_public_id`) — não existe
/// rota que devolva as fotos de vários produtos de uma vez; por isso a comparação só busca o
/// template de quem a capa sozinha não resolveu (ver `AccountComparisonLoader`).
nonisolated struct ProductListingDetails: Equatable, Sendable {
    let productID: Int
    /// A capa da listagem quando o template foi buscado — se mudar, o anúncio mudou de foto e o
    /// template salvo deixa de valer.
    let coverPublicID: String?
    /// Todas as fotos, já ordenadas pela `position` do template.
    let photoPublicIDs: [String]
    let categoryID: Int?
    let size: String?
    let brand: String?
    let description: String
    let fetchedAt: Date

    init(
        productID: Int,
        coverPublicID: String?,
        photoPublicIDs: [String],
        categoryID: Int?,
        size: String?,
        brand: String?,
        description: String,
        fetchedAt: Date
    ) {
        self.productID = productID
        self.coverPublicID = coverPublicID
        self.photoPublicIDs = photoPublicIDs
        self.categoryID = categoryID
        self.size = size
        self.brand = brand
        self.description = description
        self.fetchedAt = fetchedAt
    }

    init(product: EnjoeiProduct, template: ProductTemplate, fetchedAt: Date) {
        self.init(
            productID: product.id,
            coverPublicID: product.photoPublicID,
            photoPublicIDs: template.photos.sorted { $0.position < $1.position }.map(\.imagePublicID),
            categoryID: template.category.id,
            size: template.size,
            brand: template.brand,
            description: template.description,
            fetchedAt: fetchedAt
        )
    }

    /// Ainda descreve o anúncio como ele está na listagem agora (mesma capa)?
    func matchesListing(_ product: EnjoeiProduct) -> Bool {
        coverPublicID == product.photoPublicID
    }

    /// Bom pra usar sem buscar de novo: mesma capa e dentro de `maxAge`.
    func isFresh(for product: EnjoeiProduct, now: Date, maxAge: TimeInterval = PhotoMatchingParameters.listingDetailsMaxAge) -> Bool {
        matchesListing(product) && now.timeIntervalSince(fetchedAt) < maxAge
    }

    /// As fotos que entram na comparação: as `comparisonPhotoCount` primeiras pela posição.
    var comparisonPhotoIDs: [String] {
        Array(photoPublicIDs.prefix(PhotoMatchingParameters.comparisonPhotoCount))
    }
}
