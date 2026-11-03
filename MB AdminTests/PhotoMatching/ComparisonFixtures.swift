import Foundation
@testable import MB_Admin

/// Peças prontas pros testes da comparação: assinaturas de fotos sintéticas, anúncios, lojas e
/// pares — sem rede nem SwiftData.
enum ComparisonFixtures {
    typealias Spec = DemoPhotoRenderer.Spec

    static let sellerA = 1001
    static let sellerB = 2002

    /// Assinatura de uma foto sintética (cada loja com a sua recompressão).
    static func signature(_ spec: Spec, side: Int = 300, quality: Double = 0.85) -> PhotoSignature {
        guard let data = DemoPhotoRenderer.jpeg(spec, side: side, quality: quality),
              let signature = try? PhotoSignatureGenerator.makeSignature(from: data) else {
            preconditionFailure("não deu pra gerar a assinatura de teste")
        }
        return signature
    }

    static func ring(_ seed: Int) -> Spec { Spec(shape: .ring, seed: seed) }

    static func product(_ id: Int, title: String, cover: String?, price: Double = 100) -> EnjoeiProduct {
        EnjoeiProduct(id: id, title: title, path: "produto-\(id)", photoPublicID: cover, currentPrice: price, originalPrice: price)
    }

    /// Um anúncio com as fotos dadas (id público → assinatura; `nil` = a foto falhou). Com
    /// `hasDetails`, o template é conhecido (todas as fotos, descrição, tamanho, marca); sem, só a
    /// primeira foto (a capa), o título e o preço existem.
    static func listing(
        seller: Int,
        id: Int,
        title: String,
        photos: [(id: String, signature: PhotoSignature?)],
        hasDetails: Bool = true,
        size: String? = nil,
        categoryID: Int? = 327,
        detailsFailure: String? = nil,
        description: String = "",
        brand: String? = nil,
        price: Double = 100
    ) -> ComparableListing {
        let product = product(id, title: title, cover: photos.first?.id, price: price)
        let details = hasDetails ? ProductListingDetails(
            productID: id,
            coverPublicID: photos.first?.id,
            photoPublicIDs: photos.map(\.id),
            categoryID: categoryID,
            size: size,
            brand: brand,
            description: description,
            fetchedAt: Date()
        ) : nil
        var signatures: [String: PhotoSignature] = [:]
        var failures: [String: PhotoSignatureError] = [:]
        for photo in photos {
            if let signature = photo.signature {
                signatures[photo.id] = signature
            } else {
                failures[photo.id] = .downloadFailed("HTTP 404")
            }
        }
        return ComparableListing(
            sellerID: seller,
            product: product,
            details: details,
            detailsFailure: detailsFailure,
            signatures: signatures,
            failures: failures
        )
    }

    static func side(_ seller: Int, _ listings: [ComparableListing], name: String? = nil, status: StoreListingStatus = .complete) -> ComparisonSide {
        ComparisonSide(sellerID: seller, name: name ?? (seller == sellerA ? "antonia" : "loja B"), listings: listings, status: status)
    }

    static func compare(
        _ listingsA: [ComparableListing],
        _ listingsB: [ComparableListing],
        statusA: StoreListingStatus = .complete,
        statusB: StoreListingStatus = .complete,
        decisions: [ComparisonDecision] = []
    ) -> AccountComparisonResult {
        AccountProductMatcher.compare(
            side(sellerA, listingsA, status: statusA),
            side(sellerB, listingsB, status: statusB),
            decisions: decisions
        )
    }

    static func summary(_ seller: Int, name: String = "loja") -> ComparisonStoreSummary {
        ComparisonStoreSummary(
            sellerID: seller, name: name, status: .complete, listingCount: 0,
            listingsWithPhotoFailures: 0, listingsWithDetailsFailures: 0
        )
    }

    static func match(
        _ idA: Int,
        _ idB: Int,
        status: ProductMatch.Status = .strong,
        titleA: String = "brinco prata 925",
        titleB: String = "brinco prata 925"
    ) -> ProductMatch {
        match(product(idA, title: titleA, cover: "cover-\(idA)"), product(idB, title: titleB, cover: "cover-\(idB)"), status: status)
    }

    static func match(_ productA: EnjoeiProduct, _ productB: EnjoeiProduct, status: ProductMatch.Status = .strong) -> ProductMatch {
        ProductMatch(
            productA: productA,
            productB: productB,
            keyA: ListingKey(sellerID: sellerA, productID: productA.id),
            keyB: ListingKey(sellerID: sellerB, productID: productB.id),
            status: status,
            reasons: status == .strong ? [.samePhoto] : [.similarPhoto],
            photoEvidence: nil,
            photoA: nil,
            photoB: nil,
            textSimilarity: 1
        )
    }

    static func result(
        matches: [ProductMatch] = [],
        reviews: [ProductMatch] = [],
        rejected: [ProductMatch] = [],
        missingInB: [EnjoeiProduct] = [],
        missingInA: [EnjoeiProduct] = [],
        unverifiedA: [UnverifiedListing] = [],
        unverifiedB: [UnverifiedListing] = [],
        families: [ProductFamily] = [],
        otherVersions: [ListingKey: [OtherVersion]] = [:]
    ) -> AccountComparisonResult {
        AccountComparisonResult(
            storeA: summary(sellerA, name: "antonia"),
            storeB: summary(sellerB, name: "loja B"),
            matches: matches,
            reviews: reviews,
            rejected: rejected,
            possiblyMissingInB: missingInB,
            possiblyMissingInA: missingInA,
            unverifiedA: unverifiedA,
            unverifiedB: unverifiedB,
            families: families,
            otherVersions: otherVersions
        )
    }

    /// Uma família de versões pronta, com as versões dadas (rótulo, produto de A, de B, onde está).
    static func family(_ id: String, title: String, versions: [ProductFamilyVersion]) -> ProductFamily {
        ProductFamily(id: id, title: title, photoPublicID: nil, dimensions: [.size], versions: versions)
    }
}
