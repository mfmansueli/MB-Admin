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
                description: DemoCatalog.description(sellerID: profile.user.id, position: position), fetchedAt: Date()
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

    @Test("os produtos comuns viram par forte pela foto, mesmo quando a capa é outra — e as versões do anel, pela descrição")
    func paresFortes() {
        let special: Set = [
            DemoPhotoCatalog.sizeConflictPosition, DemoPhotoCatalog.variantPosition, DemoPhotoCatalog.differentPhotoPosition,
            DemoPhotoCatalog.duplicatePosition, DemoPhotoCatalog.brokenPhotosPosition, 23
        ]
        let expected = (0..<Self.storeB.productCount).filter { !special.contains($0) }.map { "\(idA($0))-\(idB($0))" }
        #expect(Self.result.matches.map(\.id).sorted() == expected.sorted())
        #expect(Self.result.matches.allSatisfy { $0.status == .strong })
    }

    @Test("variante de cor e mesmo título com outra foto vão pra revisão; tamanho diferente no template é outra versão")
    func revisoes() {
        let size = DemoPhotoCatalog.sizeConflictPosition
        #expect(review(size, size) == nil)
        let note = Self.result.otherVersions[ListingKey(sellerID: Self.antonia.user.id, productID: idA(size))]
        #expect(note?.map(\.product.id) == [idB(size)])
        #expect(review(DemoPhotoCatalog.variantPosition, DemoPhotoCatalog.variantPosition)?.reasons.contains(.colorVariant) == true)
        #expect(review(DemoPhotoCatalog.differentPhotoPosition, DemoPhotoCatalog.differentPhotoPosition) != nil)
    }

    @Test("a mesma foto em dois anúncios da loja B, um com outro título e preço: o texto desempata, o outro fica pra revisar")
    func duplicata() {
        let duplicated = DemoPhotoCatalog.duplicatedPosition
        let pair = Self.result.matches.first { $0.productA.id == idA(duplicated) }
        #expect(pair?.productB.id == idB(duplicated))
        #expect(pair?.reasons.first.map { if case .versionResolved = $0 { true } else { false } } == true)
        let other = review(duplicated, DemoPhotoCatalog.duplicatePosition)
        #expect(other?.reasons.contains(.otherListingAlreadyPaired) == true)
        // Um anel com a foto do colar não é versão do colar.
        #expect(!Self.result.families.contains { family in family.versions.contains { $0.productA?.id == idA(duplicated) } })
    }

    @Test("a descrição padrão, igual em todo anúncio das duas lojas, não deixa título parecido virar texto quase idêntico")
    func descricaoPadrao() {
        // 26 = "brinco pérola shell 8mm prata 925 linha infantil" × 6 da loja B (o mesmo sem "linha
        // infantil"): com a descrição de exemplo contando, o texto passava de quase idêntico.
        #expect(!Self.result.reviews.contains { $0.productA.id == idA(26) })
        #expect(!Self.result.reviews.contains { $0.productA.id == idA(33) })
    }

    @Test("fotos que não carregam: não verificado, nunca possivelmente ausente")
    func fotosQuebradas() {
        let broken = DemoPhotoCatalog.brokenPhotosPosition
        #expect(Self.result.unverifiedB.contains { $0.product.id == idB(broken) } || review(broken, broken) != nil)
        #expect(!Self.result.possiblyMissingInB.contains { $0.id == idA(broken) })
        #expect(!Self.result.possiblyMissingInA.contains { $0.id == idB(broken) })
    }

    @Test("o que antonia tem a mais aparece como possivelmente ausente na loja B; da loja B, só as versões que antonia não tem")
    func ausentes() {
        let missing = Set(Self.result.possiblyMissingInB.map(\.id))
        // Peças só parecidas com uma da loja B que já tem par, sem texto parecido, não seguram nada.
        #expect(missing.isSuperset(of: [idA(26), idA(35), idA(45), idA(50)]))
        let versions: Set = [DemoPhotoCatalog.sizeConflictPosition, 23]
        #expect(missing.allSatisfy {
            let position = DemoCatalog.position(of: $0, in: Self.antonia)
            return position >= Self.storeB.productCount || versions.contains(position)
        })
        #expect(Set(Self.result.possiblyMissingInA.map(\.id)) == Set(versions.map(idB)))
    }

    @Test("o anel em três versões com a mesma foto e o mesmo título: a descrição separa aro e banho")
    func versoesDoAnel() {
        let pairs = Set(Self.result.matches.map(\.id))
        #expect(pairs.isSuperset(of: ["\(idA(22))-\(idB(22))", "\(idA(24))-\(idB(24))"]))
        #expect(!Self.result.reviews.contains { [idA(22), idA(23), idA(24)].contains($0.productA.id) })

        let aro18 = Self.result.otherVersions[ListingKey(sellerID: Self.antonia.user.id, productID: idA(23))]
        #expect(aro18?.first?.label == "aro 16" || aro18?.first?.label == "aro 20")
        let aro20 = Self.result.otherVersions[ListingKey(sellerID: Self.storeB.user.id, productID: idB(23))]
        #expect(aro20?.isEmpty == false)

        let family = Self.result.families.first { family in family.versions.contains { $0.productA?.id == idA(22) } }
        #expect(family?.dimensions == [.size, .finish])
        #expect(family?.versions.map(\.label) == ["aro 16 · ouro", "aro 16 · ródio", "aro 18 · ródio", "aro 20 · ródio"])
        #expect(family?.versions.map(\.presence) == [.both, .both, .onlyInA, .onlyInB])
    }

    @Test("o produto cadastrado duas vezes em antonia: repetido na loja, sem virar família de versões")
    func repetidoNaLoja() {
        let group = Self.result.duplicatesA.first
        #expect(Self.result.duplicatesA.count == 1)
        #expect(group?.products.map(\.id) == DemoPhotoCatalog.relistedPositions.flatMap { [idA($0.value), idA($0.key)] })
        #expect(group?.status == .repeated)
        #expect(Self.result.duplicatesB.isEmpty)
        #expect(!Self.result.families.contains { family in family.versions.contains { $0.productA?.id == idA(45) } })
        // As versões do anel (mesma foto, aro/banho só na descrição) não são repetidos.
        #expect(!Self.result.duplicatesA.contains { $0.products.contains { $0.id == idA(22) } })
    }

    @Test("título parecido com um anúncio da loja B cujas fotos não carregaram: não verificado, não ausente")
    func bloqueadoPorQuemNaoCarregou() {
        // 27 = "tornozeleira bolinhas prata 925 linha infantil"; o 17 da loja B ("… banho ouro") não carregou.
        let blocked = Self.result.unverifiedA.first { $0.product.id == idA(27) }
        #expect(blocked?.reasons.contains { if case .possibleUnverifiedCounterpart = $0 { true } else { false } } == true)
        #expect(!Self.result.possiblyMissingInB.contains { $0.id == idA(27) })
    }
}
