import Foundation

/// Um anúncio pronto pra comparar: o produto da listagem (com a descrição, se já buscada), as fotos
/// que entram na comparação com as assinaturas, os atributos do template e as palavras do texto.
nonisolated struct ComparableListing: Sendable {
    let key: ListingKey
    let product: EnjoeiProduct
    let photos: [ListingPhoto]
    /// O template, quando conhecido e ainda da mesma capa — todas as fotos, categoria, tamanho.
    /// Sem ele, só a capa da listagem é conhecida.
    let details: ProductListingDetails?
    /// Por que o template não veio, quando foi tentado nesta comparação e falhou.
    let detailsFailure: String?
    /// Título + descrição, normalizados (`ProductSimilarity.tokenize`).
    let words: Set<String>
    /// Só o título — pra conferências mais fracas (ver `unverifiedBlockingTextThreshold`).
    let titleWords: Set<String>

    init(
        sellerID: Int,
        product: EnjoeiProduct,
        details: ProductListingDetails?,
        detailsFailure: String? = nil,
        signatures: [String: PhotoSignature],
        failures: [String: PhotoSignatureError]
    ) {
        let usableDetails = details.flatMap { $0.matchesListing(product) ? $0 : nil }
        var product = product
        if product.description == nil, let description = usableDetails?.description, !description.isEmpty {
            product = product.withDescription(description)
        }
        key = ListingKey(sellerID: sellerID, productID: product.id)
        self.product = product
        self.details = usableDetails
        self.detailsFailure = detailsFailure
        photos = Self.photoIDs(product: product, details: usableDetails).enumerated().map { position, publicID in
            ListingPhoto(publicID: publicID, position: position, signature: signatures[publicID], failure: failures[publicID])
        }
        words = ProductSimilarity.tokenize(AccountProductMatcher.comparableText(for: product))
        titleWords = ProductSimilarity.tokenize(product.title)
    }

    /// As fotos que entram na comparação: as primeiras do template pela posição, ou só a capa sem ele.
    static func photoIDs(product: EnjoeiProduct, details: ProductListingDetails?) -> [String] {
        if let details, details.matchesListing(product), !details.comparisonPhotoIDs.isEmpty {
            return details.comparisonPhotoIDs
        }
        return product.photoPublicID.map { [$0] } ?? []
    }

    var hasAllPhotos: Bool { details != nil }
    var failedPhotoCount: Int { photos.count { $0.failure != nil } }
    var notAnalyzedPhotoCount: Int { photos.count(where: \.wasNotAnalyzed) }
    var size: String? { details?.size.flatMap { Self.normalized($0) } }
    var categoryID: Int? { details?.categoryID }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
