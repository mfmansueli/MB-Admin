import Foundation
import Testing
@testable import MB_Admin

@Suite("anúncios repetidos dentro da mesma loja")
struct StoreDuplicateFinderTests {
    typealias Fixtures = ComparisonFixtures

    private static let ring = Fixtures.signature(Fixtures.ring(1), quality: 0.9)
    /// A mesma foto reenviada — outra recompressão, outro id público.
    private static let ringAgain = Fixtures.signature(Fixtures.ring(1), quality: 0.6)
    private static let pendant = Fixtures.signature(.init(shape: .pendant, seed: 5))
    private static let chain = Fixtures.signature(.init(shape: .chain, seed: 8))
    private static let bracelet = Fixtures.signature(.init(shape: .bracelet, seed: 9))
    private static let earrings = Fixtures.signature(.init(shape: .earrings, seed: 11))
    /// Uma "tabela de medidas" — a mesma foto em vários anúncios, nunca a capa.
    private static let chart = Fixtures.signature(.init(shape: .pendant, seed: 40))
    /// O mesmo pingente em outro banho — a mesma pose, outra cor.
    private static let goldPendant: PhotoSignature = {
        var spec = PhotoSpec(shape: .pendant, seed: 5)
        spec.metal = .gold
        return Fixtures.signature(spec, quality: 0.6)
    }()
    private typealias PhotoSpec = DemoPhotoRenderer.Spec

    private func listing(
        _ id: Int,
        seller: Int = Fixtures.sellerA,
        title: String = "anel coração vazado",
        photos: [(id: String, signature: PhotoSignature?)],
        hasDetails: Bool = true,
        size: String? = nil,
        price: Double = 100
    ) -> ComparableListing {
        Fixtures.listing(seller: seller, id: id, title: title, photos: photos, hasDetails: hasDetails, size: size, price: price)
    }

    /// Uma loja B qualquer, sem nada a ver com os anúncios de A.
    private var unrelatedB: [ComparableListing] {
        [listing(500, seller: Fixtures.sellerB, title: "colar veneziana longo", photos: [("b500", Self.chain)])]
    }

    private func decision(
        _ verdict: ComparisonDecision.Verdict,
        _ first: ComparableListing,
        _ second: ComparableListing
    ) -> ComparisonDecision {
        ComparisonDecision(
            (first.key, ListingFingerprint(product: first.product)),
            (second.key, ListingFingerprint(product: second.product)),
            verdict: verdict,
            decidedAt: Date()
        )
    }

    @Test("a mesma foto reenviada, mesmo título e preço, com o template conferido: repetido")
    func mesmaFotoReenviada() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)]),
            listing(2, photos: [("a2", Self.ringAgain)])
        ], unrelatedB)

        let group = result.duplicatesA.first
        #expect(result.duplicatesA.count == 1)
        #expect(group?.products.map(\.id) == [1, 2])
        #expect(group?.status == .repeated)
        #expect(group?.reasons.contains(.samePhoto) == true)
        #expect(group?.reasons.contains(.samePrice(PriceRelation.format(100))) == true)
        #expect(result.duplicatesB.isEmpty)
        // Repetido não é versão: a capa igual não vira família.
        #expect(result.families.isEmpty)
    }

    @Test("o mesmo arquivo de foto em dois anúncios também é repetido")
    func mesmoArquivo() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)]),
            listing(2, photos: [("a1", Self.ring)])
        ], unrelatedB)
        #expect(result.duplicatesA.first?.reasons.first == .samePublicID)
        #expect(result.duplicatesA.first?.status == .repeated)
    }

    @Test("a mesma foto com aro diferente no template é outra versão, não repetido")
    func aroDiferenteEhVersao() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)], size: "16"),
            listing(2, photos: [("a2", Self.ringAgain)], size: "18")
        ], unrelatedB)
        #expect(result.duplicatesA.isEmpty)
        #expect(result.families.count == 1)
    }

    @Test("sem o template, fica \"talvez repetidos\" — e a comparação pede o template dos dois")
    func semTemplateFicaTalvez() {
        let first = listing(1, photos: [("a1", Self.ring)], hasDetails: false)
        let second = listing(2, photos: [("a2", Self.ringAgain)], hasDetails: false)
        let result = Fixtures.compare([first, second], unrelatedB)

        #expect(result.duplicatesA.first?.status == .possible)
        #expect(result.duplicatesA.first?.reasons.contains(.detailsMissing) == true)
        #expect(result.keysWantingDetails.isSuperset(of: [first.key, second.key]))
    }

    @Test("preço inicial bem diferente fica \"talvez\": pode ser outra versão que só o preço mostra")
    func precoBemDiferente() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)], price: 100),
            listing(2, photos: [("a2", Self.ringAgain)], price: 200)
        ], unrelatedB)
        let group = result.duplicatesA.first
        #expect(group?.status == .possible)
        #expect(group?.reasons.contains(.priceDiffers(PriceRelation.format(100), PriceRelation.format(200))) == true)
    }

    @Test("a mesma capa, mas outra foto do par em outra cor: fica \"talvez\" (pode ser outro banho)")
    func outraFotoEmOutraCor() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring), ("a1-detalhe", Self.pendant)]),
            listing(2, photos: [("a2", Self.ringAgain), ("a2-detalhe", Self.goldPendant)])
        ], unrelatedB)
        let group = result.duplicatesA.first
        #expect(group?.status == .possible)
        #expect(group?.reasons.contains(.colorVariant) == true)
    }

    @Test("fotos só parecidas (peças diferentes da mesma linha) não ligam anúncios da loja")
    func fotoParecidaNaoLiga() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)]),
            listing(2, photos: [("a2", Fixtures.signature(Fixtures.ring(2)))])
        ], unrelatedB)
        #expect(result.duplicatesA.isEmpty)
    }

    @Test("a mesma foto que não é a capa de nenhum dos dois (ambiente, embalagem) não liga")
    func fotoDeDentroNaoLiga() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.chain), ("a1-caixa", Self.ring)]),
            listing(2, photos: [("a2", Self.bracelet), ("a2-caixa", Self.ringAgain)])
        ], unrelatedB)
        #expect(result.duplicatesA.isEmpty)
    }

    @Test("a mesma foto num anúncio de outro produto (título base diferente) não é repetido")
    func outroProdutoComAMesmaFoto() {
        let result = Fixtures.compare([
            listing(1, title: "anel coração vazado", photos: [("a1", Self.ring)]),
            listing(2, title: "colar estrela pingente", photos: [("a2", Self.ringAgain)])
        ], unrelatedB)
        #expect(result.duplicatesA.isEmpty)
    }

    @Test("a tabela de medidas em vários anúncios (nunca a capa) não liga nenhum deles")
    func fotoGenericaNaoLiga() {
        let covers = [Self.ring, Self.pendant, Self.bracelet, Self.earrings]
        let listings = covers.enumerated().map { index, cover in
            listing(index + 1, title: "anel liso prata", photos: [("capa\(index)", cover), ("tabela\(index)", Self.chart)])
        }
        let result = Fixtures.compare(listings, unrelatedB)
        #expect(result.duplicatesA.isEmpty)
    }

    @Test("três anúncios do mesmo produto viram um grupo só")
    func tresAnuncios() {
        let result = Fixtures.compare([
            listing(1, photos: [("a1", Self.ring)]),
            listing(2, photos: [("a2", Self.ringAgain)]),
            listing(3, photos: [("a3", Self.ring)])
        ], unrelatedB)
        #expect(result.duplicatesA.map { $0.products.map(\.id) } == [[1, 2, 3]])
        #expect(result.duplicatesA.first?.statusText == "3 anúncios iguais")
    }

    @Test("\"não são repetidos\" tira o grupo (ele vai pros marcados, com desfazer); \"são repetidos\" confirma um talvez")
    func revisaoManual() {
        let first = listing(1, photos: [("a1", Self.ring)])
        let second = listing(2, photos: [("a2", Self.ringAgain)])
        let dismissed = Fixtures.compare([first, second], unrelatedB, decisions: [decision(.differentProducts, first, second)])
        #expect(dismissed.duplicatesA.isEmpty)
        #expect(dismissed.dismissedDuplicates.first?.status == .dismissed)
        #expect(dismissed.dismissedDuplicates.first?.reasons.contains(.dismissedByUser) == true)

        let possibleFirst = listing(1, photos: [("a1", Self.ring)], hasDetails: false)
        let possibleSecond = listing(2, photos: [("a2", Self.ringAgain)], hasDetails: false)
        let confirmed = Fixtures.compare(
            [possibleFirst, possibleSecond], unrelatedB, decisions: [decision(.sameProduct, possibleFirst, possibleSecond)]
        )
        #expect(confirmed.duplicatesA.first?.status == .confirmed)
    }

    @Test("uma revisão de um anúncio que mudou (outro título) deixa de valer")
    func revisaoVencida() {
        let first = listing(1, photos: [("a1", Self.ring)])
        let second = listing(2, photos: [("a2", Self.ringAgain)])
        let old = decision(.differentProducts, first, listing(2, title: "anel coração", photos: [("a2", Self.ringAgain)]))
        let result = Fixtures.compare([first, second], unrelatedB, decisions: [old])
        #expect(result.duplicatesA.first?.status == .repeated)
        #expect(result.dismissedDuplicates.isEmpty)
    }

    @Test("repetidos na loja B aparecem do lado dela")
    func lojaB() {
        let result = Fixtures.compare(
            [listing(1, title: "colar veneziana longo", photos: [("a1", Self.chain)])],
            [
                listing(10, seller: Fixtures.sellerB, photos: [("b10", Self.ring)]),
                listing(11, seller: Fixtures.sellerB, photos: [("b11", Self.ringAgain)])
            ]
        )
        #expect(result.duplicatesA.isEmpty)
        #expect(result.duplicatesB.first?.products.map(\.id) == [10, 11])
        #expect(result.duplicatesB.first?.storeName == "loja B")
    }

    @Test("repetido em A com o mesmo produto em B: o grupo aparece e ninguém vira ausente")
    func repetidoComParNaOutraLoja() {
        let result = Fixtures.compare(
            [listing(1, photos: [("a1", Self.ring)]), listing(2, photos: [("a2", Self.ringAgain)])],
            [listing(10, seller: Fixtures.sellerB, photos: [("b10", Self.ring)])]
        )
        #expect(result.duplicatesA.first?.products.map(\.id) == [1, 2])
        #expect(result.possiblyMissingInA.isEmpty)
        #expect(result.possiblyMissingInB.isEmpty)
    }

    @Test("cada par de anúncios da loja aparece uma vez, nunca o anúncio com ele mesmo")
    func cadaParUmaVez() {
        let pairs = StorePairEvidenceBuilder.build([
            listing(1, photos: [("a1", Self.ring), ("a1-detalhe", Self.pendant)]),
            listing(2, photos: [("a2", Self.ringAgain)]),
            listing(3, photos: [("a1", Self.ring)])
        ])
        #expect(pairs.map { "\($0.indexA)-\($0.indexB)" } == ["0-1", "0-2", "1-2"])
        #expect(pairs.allSatisfy { $0.photo?.level ?? .different >= .samePhoto })
    }
}
