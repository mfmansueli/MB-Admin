import Foundation
import Testing
@testable import MB_Admin

/// Os cenários do modo de demonstração (`DemoPhotoCatalog`) passando pelo comparador de verdade —
/// garante que o que a demo mostra na tela é o que o algoritmo de fato conclui.
@Suite("cenários da comparação no modo de demonstração")
struct DemoComparisonScenarioTests {
    private static let antonia = DemoCatalog.profiles[0]
    private static let storeB = DemoCatalog.profiles[1]

    private static func listings(for profile: DemoCatalog.Profile) -> [ComparableListing] {
        DemoCatalog.products(for: profile).map { product in
            let position = DemoCatalog.position(of: product.id, in: profile)
            let photoIDs = DemoPhotoCatalog.photoIDs(sellerID: profile.user.id, position: position)
            var signatures: [String: PhotoSignature] = [:]
            var failures: [String: PhotoSignatureError] = [:]
            for publicID in photoIDs {
                if let data = DemoPhotoCatalog.photoData(publicID: publicID), let signature = try? PhotoSignatureGenerator.makeSignature(from: data) {
                    signatures[publicID] = signature
                } else {
                    failures[publicID] = .downloadFailed("HTTP 404")
                }
            }
            let details = ProductListingDetails(
                productID: product.id, coverPublicID: product.photoPublicID, photoPublicIDs: photoIDs, categoryID: 327,
                size: DemoPhotoCatalog.size(sellerID: profile.user.id, position: position), brand: nil,
                description: "", fetchedAt: Date()
            )
            return ComparableListing(
                sellerID: profile.user.id, product: product, details: details, detailsFailure: nil,
                signatures: signatures, failures: failures
            )
        }
    }

    private static let result: AccountComparisonResult = AccountProductMatcher.compare(
        ComparisonSide(sellerID: antonia.user.id, name: antonia.user.name, listings: listings(for: antonia), status: .complete),
        ComparisonSide(sellerID: storeB.user.id, name: storeB.user.name, listings: listings(for: storeB), status: .complete),
        decisions: []
    )

    private func idA(_ position: Int) -> Int { Self.antonia.user.id * 1000 + position }
    private func idB(_ position: Int) -> Int { Self.storeB.user.id * 1000 + position }

    private func review(_ positionA: Int, _ positionB: Int) -> ProductMatch? {
        Self.result.reviews.first { $0.productA.id == idA(positionA) && $0.productB.id == idB(positionB) }
    }

    @Test("os produtos comuns viram par forte pela foto, mesmo quando a capa é outra")
    func paresFortes() {
        let special: Set = [
            DemoPhotoCatalog.sizeConflictPosition, DemoPhotoCatalog.variantPosition, DemoPhotoCatalog.differentPhotoPosition,
            DemoPhotoCatalog.duplicatedPosition, DemoPhotoCatalog.duplicatePosition, DemoPhotoCatalog.brokenPhotosPosition
        ]
        let expected = (0..<Self.storeB.productCount).filter { !special.contains($0) }.map { "\(idA($0))-\(idB($0))" }
        #expect(Self.result.matches.map(\.id).sorted() == expected.sorted())
        #expect(Self.result.matches.allSatisfy { $0.status == .strong })
    }

    @Test("tamanho diferente, variante de cor e mesmo título com outra foto vão pra revisão")
    func revisoes() {
        let size = review(DemoPhotoCatalog.sizeConflictPosition, DemoPhotoCatalog.sizeConflictPosition)
        #expect(size?.reasons.contains(.sizeDiffers("17", "16")) == true)
        #expect(review(DemoPhotoCatalog.variantPosition, DemoPhotoCatalog.variantPosition)?.reasons.contains(.colorVariant) == true)
        #expect(review(DemoPhotoCatalog.differentPhotoPosition, DemoPhotoCatalog.differentPhotoPosition) != nil)
    }

    @Test("a mesma foto em dois anúncios da loja B: os dois pares ficam pra revisar")
    func duplicata() {
        #expect(review(DemoPhotoCatalog.duplicatedPosition, DemoPhotoCatalog.duplicatedPosition) != nil)
        #expect(review(DemoPhotoCatalog.duplicatedPosition, DemoPhotoCatalog.duplicatePosition) != nil)
    }

    @Test("fotos que não carregam: não verificado, nunca possivelmente ausente")
    func fotosQuebradas() {
        let broken = DemoPhotoCatalog.brokenPhotosPosition
        #expect(Self.result.unverifiedB.contains { $0.product.id == idB(broken) } || review(broken, broken) != nil)
        #expect(!Self.result.possiblyMissingInB.contains { $0.id == idA(broken) })
        #expect(!Self.result.possiblyMissingInA.contains { $0.id == idB(broken) })
    }

    @Test("o que antonia tem a mais aparece como possivelmente ausente na loja B; a loja B não tem nada a mais")
    func ausentes() {
        let missing = Set(Self.result.possiblyMissingInB.map(\.id))
        // Peças só parecidas com uma da loja B que já tem par, sem texto parecido, não seguram nada.
        #expect(missing.isSuperset(of: [idA(26), idA(35), idA(45), idA(50)]))
        #expect(missing.allSatisfy { DemoCatalog.position(of: $0, in: Self.antonia) >= Self.storeB.productCount })
        #expect(Self.result.possiblyMissingInA.isEmpty)
    }

    @Test("título parecido com um anúncio da loja B cujas fotos não carregaram: não verificado, não ausente")
    func bloqueadoPorQuemNaoCarregou() {
        // 27 = "tornozeleira bolinhas prata 925 linha infantil"; o 17 da loja B ("… banho ouro") não carregou.
        let blocked = Self.result.unverifiedA.first { $0.product.id == idA(27) }
        #expect(blocked?.reasons.contains { if case .possibleUnverifiedCounterpart = $0 { true } else { false } } == true)
        #expect(!Self.result.possiblyMissingInB.contains { $0.id == idA(27) })
    }
}
