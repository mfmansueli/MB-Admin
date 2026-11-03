import Foundation
import Testing
@testable import MB_Admin

/// Versões do mesmo produto que dividem a mesma foto (aro, banho, cor, medida — muitas vezes só na
/// descrição, ou só no preço inicial): qual versão de uma loja é qual da outra, quais faltam, as
/// famílias de versões e o índice de correspondência.
@Suite("versões do mesmo produto com a mesma foto")
struct ProductVariantMatchingTests {
    typealias Fixtures = ComparisonFixtures

    private static let ringA = Fixtures.signature(Fixtures.ring(1), quality: 0.9)
    private static let ringB = Fixtures.signature(Fixtures.ring(1), quality: 0.6)
    private static let pendant = Fixtures.signature(DemoPhotoRenderer.Spec(shape: .pendant, seed: 5), quality: 0.6)
    private static let title = "anel coração vazado prata 925"

    /// Um anúncio de A com a foto do anel (cada um com o seu id público, como um reenvio).
    private func ringA(_ id: Int, description: String = "", price: Double = 100, brand: String? = nil, title: String = title) -> ComparableListing {
        Fixtures.listing(
            seller: Fixtures.sellerA, id: id, title: title, photos: [("a\(id)", Self.ringA)],
            description: description, brand: brand, price: price
        )
    }

    private func ringB(_ id: Int, description: String = "", price: Double = 100, brand: String? = nil, title: String = title) -> ComparableListing {
        Fixtures.listing(
            seller: Fixtures.sellerB, id: id, title: title, photos: [("b\(id)", Self.ringB)],
            description: description, brand: brand, price: price
        )
    }

    private func keyA(_ id: Int) -> ListingKey { ListingKey(sellerID: Fixtures.sellerA, productID: id) }
    private func keyB(_ id: Int) -> ListingKey { ListingKey(sellerID: Fixtures.sellerB, productID: id) }

    // MARK: - Qual versão é qual

    @Test("três versões com a mesma foto e o mesmo título, aro e banho só na descrição: cada uma acha a sua")
    func versoesPelaDescricao() {
        let result = Fixtures.compare(
            [
                ringA(1, description: "aro 16, banho de ródio"), ringA(2, description: "aro 18, banho de ródio"),
                ringA(3, description: "aro 16, banho de ouro")
            ],
            [
                ringB(11, description: "aro 16, banho de ródio"), ringB(12, description: "aro 18, banho de ródio"),
                ringB(13, description: "aro 16, banho de ouro")
            ]
        )
        #expect(Set(result.matches.map(\.id)) == ["1-11", "2-12", "3-13"])
        #expect(result.matches.allSatisfy { $0.status == .strong })
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInA.isEmpty && result.possiblyMissingInB.isEmpty)
        #expect(result.matches.allSatisfy { $0.index.level == .high })

        let family = result.families.first
        #expect(result.families.count == 1)
        #expect(family?.dimensions == [.size, .finish])
        #expect(family?.versions.map(\.label) == ["aro 16 · ouro", "aro 16 · ródio", "aro 18 · ródio"])
        #expect(family?.versions.allSatisfy { $0.presence == .both } == true)
    }

    @Test("a outra loja não tem uma das versões: ela fica possivelmente ausente, com a nota das versões de lá")
    func versaoQueFalta() {
        let result = Fixtures.compare(
            [ringA(1, description: "aro 16"), ringA(2, description: "aro 18")],
            [ringB(11, description: "aro 16")]
        )
        #expect(result.matches.map(\.id) == ["1-11"])
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.map(\.id) == [2])
        let versions = result.otherVersions[keyA(2)] ?? []
        #expect(versions.map(\.product.id) == [11])
        #expect(OtherVersion.summary(versions, storeName: "loja B") == "loja B tem outra versão: aro 16 (aqui: aro 18)")
        #expect(result.families.first?.versions.map(\.presence) == [.both, .onlyInA])
        #expect(result.families.first?.summary(accountAName: "antonia", accountBName: "loja B") == "2 versões · 1 só em antonia")
    }

    @Test("1:1 com a mesma foto e o mesmo título, banho diferente só na descrição: outra versão, não par")
    func banhoDiferenteUmPraUm() {
        let result = Fixtures.compare([ringA(1, description: "banho de ouro 18k")], [ringB(11, description: "banho de ródio")])
        #expect(result.matches.isEmpty)
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.map(\.id) == [1])
        #expect(result.possiblyMissingInA.map(\.id) == [11])
        #expect(result.otherVersions[keyA(1)]?.first?.label == "ródio")
        #expect(result.otherVersions[keyB(11)]?.first?.label == "ouro")
        #expect(result.families.first?.versions.map(\.presence) == [.onlyInA, .onlyInB])
    }

    @Test("sem atributo no texto, o preço inicial desempata versões com a mesma foto")
    func precoDesempata() {
        let result = Fixtures.compare(
            [ringA(1, price: 100), ringA(2, price: 150)],
            [ringB(11, price: 100), ringB(12, price: 150)]
        )
        #expect(Set(result.matches.map(\.id)) == ["1-11", "2-12"])
        #expect(result.matches.allSatisfy { $0.reasons.first == .versionResolved(nil) })
        #expect(result.reviews.isEmpty)
        #expect(result.families.first?.versions.map(\.label) == ["preço inicial \(PriceRelation.format(100))", "preço inicial \(PriceRelation.format(150))"])
    }

    @Test("preços quase iguais não desempatam: as quatro ligações ficam pra revisar")
    func precoProximoNaoDesempata() {
        let result = Fixtures.compare(
            [ringA(1, price: 100), ringA(2, price: 105)],
            [ringB(11, price: 100), ringB(12, price: 105)]
        )
        #expect(result.matches.isEmpty)
        #expect(Set(result.reviews.map(\.id)) == ["1-11", "1-12", "2-11", "2-12"])
        #expect(result.reviews.allSatisfy { $0.reasons.contains(.photoUsedByManyListings(4)) })
        #expect(result.possiblyMissingInA.isEmpty && result.possiblyMissingInB.isEmpty)
    }

    @Test("atributo de um lado só não desempata sozinho contra quem não diz nada")
    func atributoDeUmLadoSo() {
        // B não diz o aro de nenhuma; A diz. Nada separa as duas de B: revisão.
        let result = Fixtures.compare([ringA(1, description: "aro 16"), ringA(2, description: "aro 18")], [ringB(11), ringB(12)])
        #expect(result.matches.isEmpty)
        #expect(result.reviews.count == 4)
    }

    // MARK: - Par 1:1 com dúvida

    @Test("1:1 com a mesma foto e preço inicial bem diferente: revisão, a não ser que o texto confirme")
    func precoBemDiferente() {
        let doubt = Fixtures.compare([ringA(1, price: 100)], [ringB(11, price: 200)])
        #expect(doubt.matches.isEmpty)
        #expect(doubt.reviews.first?.reasons.contains(.priceDiffers(PriceRelation.format(100), PriceRelation.format(200))) == true)

        let sameSize = Fixtures.compare([ringA(1, description: "aro 16", price: 100)], [ringB(11, description: "aro 16", price: 200)])
        #expect(sameSize.matches.first?.status == .strong)

        let description = "anel coração vazado com zircônias cravejadas, acompanha caixinha e certificado"
        let sameText = Fixtures.compare([ringA(1, description: description, price: 100)], [ringB(11, description: description, price: 200)])
        #expect(sameText.matches.first?.status == .strong)
    }

    @Test("preço um pouco diferente num 1:1 não pede revisão")
    func precoUmPoucoDiferente() {
        let result = Fixtures.compare([ringA(1, price: 100)], [ringB(11, price: 115)])
        #expect(result.matches.first?.status == .strong)
    }

    @Test("marcas diferentes com a mesma foto: revisão")
    func marcasDiferentes() {
        let result = Fixtures.compare([ringA(1, brand: "Vivara")], [ringB(11, brand: "Pandora")])
        #expect(result.matches.isEmpty)
        #expect(result.reviews.first?.reasons.contains(.brandDiffers("Vivara", "Pandora")) == true)
    }

    @Test("revisão manual vale acima da versão: confirmar um par com banho em conflito vira par confirmado, com o aviso")
    func confirmarVersaoEmConflito() {
        let first = ringA(1, description: "banho de ouro")
        let second = ringB(11, description: "banho de ródio")
        let decision = ComparisonDecision(
            (first.key, ListingFingerprint(product: first.product)),
            (second.key, ListingFingerprint(product: second.product)),
            verdict: .sameProduct,
            decidedAt: .now
        )
        let result = Fixtures.compare([first], [second], decisions: [decision])
        #expect(result.matches.first?.status == .confirmed)
        #expect(result.matches.first?.reasons.contains(.attributesDiffer("ouro × ródio")) == true)
        #expect(result.possiblyMissingInB.isEmpty)
    }

    // MARK: - Famílias

    @Test("duas versões numa loja só, nenhuma na outra: família com as duas 'só em', sem nota de outra versão")
    func familiaSoNumaLoja() {
        let pendantB = Fixtures.listing(seller: Fixtures.sellerB, id: 11, title: "pingente", photos: [("b11", Self.pendant)])
        let result = Fixtures.compare([ringA(1, description: "aro 16"), ringA(2, description: "aro 18")], [pendantB])
        #expect(result.possiblyMissingInB.map(\.id) == [1, 2])
        #expect(result.otherVersions.isEmpty)
        #expect(result.families.count == 1)
        #expect(result.families.first?.versions.map(\.label) == ["aro 16", "aro 18"])
        #expect(result.families.first?.versions.allSatisfy { $0.presence == .onlyInA } == true)
    }

    @Test("a mesma foto num anúncio de outro produto: o título e o preço desempatam, e ele não entra como versão")
    func fotoReaproveitadaEmOutroProduto() {
        let result = Fixtures.compare(
            [ringA(1)],
            [ringB(11), ringB(12, price: 300, title: "brinco argola grande")]
        )
        #expect(result.matches.map(\.id) == ["1-11"])
        #expect(result.matches.first?.reasons.first == .versionResolved(nil))
        let other = result.reviews.first { $0.productB.id == 12 }
        #expect(other?.reasons.contains(.otherListingAlreadyPaired) == true)
        #expect(result.families.isEmpty)
        #expect(result.otherVersions.isEmpty)
    }

    @Test("um par 1:1 comum não é família")
    func parComumNaoEFamilia() {
        let result = Fixtures.compare([ringA(1)], [ringB(11)])
        #expect(result.matches.map(\.id) == ["1-11"])
        #expect(result.families.isEmpty)
    }

    @Test("família com par já resolvido pelo título e sem template: pede o template desses pra conferir a versão")
    func templateDeQuemTemParNaFamilia() {
        let first = Fixtures.listing(seller: Fixtures.sellerA, id: 1, title: "anel aro 16", photos: [("a1", Self.ringA)], hasDetails: false)
        let second = Fixtures.listing(seller: Fixtures.sellerA, id: 2, title: "anel aro 18", photos: [("a2", Self.ringA)], hasDetails: false)
        let other = Fixtures.listing(seller: Fixtures.sellerB, id: 11, title: "anel aro 16", photos: [("b11", Self.ringB)], hasDetails: false)
        let result = Fixtures.compare([first, second], [other])
        #expect(result.matches.map(\.id) == ["1-11"])
        #expect(result.keysWantingDetails == [keyA(1), keyB(11)])
    }

    // MARK: - Índice

    @Test("índice: a mesma foto com tudo batendo fica alto; o atributo em conflito derruba; não passa de 0 a 100")
    func indice() {
        var evidence = ListingPairEvidence(indexA: 0, indexB: 0)
        evidence.consider(PhotoPairComparison.compare(Self.ringA, Self.ringB), photoA: "a1", photoB: "b11", linkedListingCount: 2)
        let same = PairAssessor.assess(
            ringA(1, description: "aro 16, banho de ródio", brand: "Vivara"),
            ringB(11, description: "aro 16, banho de ródio", brand: "vivara"),
            evidence: evidence, photosComplete: true
        )
        #expect(same.index.score == 95)
        #expect(same.index.components.first == MatchIndexComponent(kind: .photo, points: 55, text: "a mesma foto"))
        #expect(same.index.components.contains { $0.kind == .brand && $0.points == 5 })
        #expect(same.agreements == [.size, .finish])

        let variant = PairAssessor.assess(
            ringA(1, description: "aro 16"), ringB(11, description: "aro 18", price: 150), evidence: evidence, photosComplete: true
        )
        #expect(variant.isVariant)
        #expect(variant.conflicts.map(\.text) == ["aro 16 × aro 18"])
        #expect(variant.index.components.contains(MatchIndexComponent(kind: .attribute(.size), points: -35, text: "tamanho: aro 16 × aro 18")))
        #expect(variant.index.components.contains { $0.kind == .price && $0.points == -5 })
        #expect(variant.index.score < MatchIndexParameters.mediumIndex)

        let nothing = PairAssessor.assess(
            ringA(1, title: "anel ouro aro 16"), ringB(11, price: 300, title: "colar ródio 45cm"),
            evidence: ListingPairEvidence(indexA: 0, indexB: 0), photosComplete: true
        )
        #expect(nothing.index.score == 0)
        #expect(MatchIndexComponent(kind: .photo, points: -15, text: "").signedPoints == "−15")
        let over = MatchIndex(components: [.init(kind: .photo, points: 80, text: ""), .init(kind: .title, points: 40, text: "")])
        #expect(over.score == 100)
    }

    @Test("a linha da tabela lado a lado mostra o atributo dos dois e se batem")
    func tabelaLadoALado() {
        let rows = MatchAttributeRow.rows(
            ringA(1, description: "aro 16, banho de ouro", price: 100).attributes,
            ringB(11, description: "aro 18, banho de ouro", price: 100).attributes
        )
        #expect(rows.map(\.label) == ["tamanho", "banho", "preço inicial"])
        #expect(rows.first == MatchAttributeRow(label: "tamanho", valueA: "aro 16", valueB: "aro 18", relation: .conflicts))
        #expect(rows[1].relation == .agrees)
        #expect(rows[2].relation == .agrees)
    }
}
