import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MB_Admin

/// Os estados da comparação (forte, revisar, possivelmente ausente, não verificado) a partir de
/// fotos sintéticas. Transformações sintéticas não substituem amostras reais
/// (`PhotoSampleEvaluationTests`) — aqui garantem as regras.
@Suite("comparação de anúncios entre duas lojas")
struct AccountProductMatcherTests {
    typealias Fixtures = ComparisonFixtures
    typealias Spec = DemoPhotoRenderer.Spec

    private static let ringA = Fixtures.signature(Fixtures.ring(1), quality: 0.9)
    private static let ringB = Fixtures.signature(Fixtures.ring(1), quality: 0.6)
    private static let ringBOther = Fixtures.signature(Fixtures.ring(1), side: 260, quality: 0.7)
    private static let otherRing = Fixtures.signature(Fixtures.ring(2), quality: 0.6)
    private static let pendant = Fixtures.signature(Spec(shape: .pendant, seed: 5), quality: 0.6)
    private static let ambient: PhotoSignature = {
        var spec = Fixtures.ring(50)
        spec.background = .init(red: 0.6, green: 0.5, blue: 0.45)
        spec.backgroundGradient = 0.4
        spec.rotation = 0.3
        return Fixtures.signature(spec)
    }()
    private static let goldRing: PhotoSignature = {
        var spec = Fixtures.ring(1)
        spec.metal = .gold
        return Fixtures.signature(spec, quality: 0.6)
    }()

    private func listingA(
        _ id: Int,
        _ title: String,
        _ photos: [(id: String, signature: PhotoSignature?)],
        size: String? = nil,
        hasDetails: Bool = true
    ) -> ComparableListing {
        Fixtures.listing(seller: Fixtures.sellerA, id: id, title: title, photos: photos, hasDetails: hasDetails, size: size)
    }

    private func listingB(_ id: Int, _ title: String, _ photos: [(id: String, signature: PhotoSignature?)], size: String? = nil) -> ComparableListing {
        Fixtures.listing(seller: Fixtures.sellerB, id: id, title: title, photos: photos, size: size)
    }

    // MARK: - Correspondência forte

    @Test("a mesma foto em posições diferentes, com ids diferentes e nenhuma palavra em comum, é par forte")
    func mesmaFotoPosicaoDiferenteSemTexto() {
        let result = Fixtures.compare(
            [listingA(1, "anel aro 17 prata", [("a1-ambiente", Self.ambient), ("a1-branca", Self.ringA)])],
            [listingB(2, "joia linda presente", [("b2-branca", Self.ringB)])]
        )
        #expect(result.matches.map(\.id) == ["1-2"])
        #expect(result.matches.first?.status == .strong)
        #expect(result.matches.first?.reasons.contains(.samePhoto) == true)
        #expect(result.matches.first?.photoA == "a1-branca")
        #expect(result.matches.first?.photoB == "b2-branca")
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInA.isEmpty && result.possiblyMissingInB.isEmpty)
    }

    @Test("mesmo id público nas duas lojas é par forte mesmo sem conseguir baixar a foto")
    func mesmoIDPublico() {
        let result = Fixtures.compare(
            [listingA(1, "anel", [("mesmo-id", nil)])],
            [listingB(2, "outro nome", [("mesmo-id", nil)])]
        )
        #expect(result.matches.first?.status == .strong)
        #expect(result.matches.first?.reasons.contains(.samePublicID) == true)
    }

    // MARK: - Texto

    @Test("texto igual com fotos diferentes (todas analisadas) não é par — vai pra revisão")
    func textoIgualFotosDiferentes() {
        let result = Fixtures.compare(
            [listingA(1, "anel solitário zircônia rosa", [("a1", Self.ringA)])],
            [listingB(2, "anel solitário zircônia rosa", [("b2", Self.otherRing)])]
        )
        #expect(result.matches.isEmpty)
        #expect(result.reviews.first?.reasons.contains(.nearIdenticalTextDifferentPhotos) == true)
        #expect(result.possiblyMissingInB.isEmpty)
    }

    @Test("texto só parecido, com fotos diferentes analisadas, é descartado — os dois ficam possivelmente ausentes")
    func textoParecidoFotosDiferentes() {
        let result = Fixtures.compare(
            [listingA(1, "anel prata 925 zircônia", [("a1", Self.ringA)])],
            [listingB(2, "anel prata 925 cravejado", [("b2", Self.pendant)])]
        )
        #expect(result.matches.isEmpty)
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.map(\.id) == [1])
        #expect(result.possiblyMissingInA.map(\.id) == [2])
    }

    @Test("foto que falhou + título igual: revisão, nunca ausente")
    func fotoFalhouComTituloIgual() {
        let result = Fixtures.compare(
            [listingA(1, "pulseira elos portugueses 18cm", [("a1", nil)])],
            [listingB(2, "pulseira elos portugueses 18cm", [("b2", Self.pendant)])]
        )
        #expect(result.reviews.first?.reasons.contains(.photosUnavailable) == true)
        #expect(result.possiblyMissingInB.isEmpty)
    }

    // MARK: - Parecidos, variantes, objeto pequeno

    @Test("variante de cor (mesma pose, dourado × prateado) vai pra revisão como variante")
    func varianteDeCor() {
        let result = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)])],
            [listingB(2, "anel", [("b2", Self.goldRing)])]
        )
        #expect(result.matches.isEmpty)
        #expect(result.reviews.first?.reasons.contains(.colorVariant) == true)
    }

    @Test("objeto pequeno em muito branco: produtos diferentes não viram par")
    func objetoPequenoDiferente() {
        var first = Spec(shape: .earrings, seed: 1)
        first.scale = 0.12
        var second = first
        second.seed = 2
        let result = Fixtures.compare(
            [listingA(1, "brinco gota", [("a1", Fixtures.signature(first))])],
            [listingB(2, "brinco estrela", [("b2", Fixtures.signature(second))])]
        )
        #expect(result.matches.isEmpty)
        #expect(result.reviews.isEmpty)
    }

    @Test("candidato quase tão parecido quanto o par: os dois vão pra revisão")
    func candidatosProximos() {
        var shifted = Fixtures.ring(1)
        shifted.centerX = 0.53
        shifted.centerY = 0.52
        let result = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)])],
            [listingB(2, "anel b", [("b2", Self.ringB)]), listingB(3, "anel c", [("b3", Fixtures.signature(shifted))])]
        )
        #expect(result.matches.isEmpty)
        let review = result.reviews.first { $0.id == "1-2" }
        #expect(review?.reasons.contains(.closeCompetitor) == true)
        #expect(result.reviews.contains { $0.id == "1-3" })
    }

    /// Uma foto só parecida (levemente girada, bem abaixo da correlação do par) com um anúncio da
    /// outra loja que já é a mesma fotografia de outro — o caso das peças parecidas num catálogo de
    /// joias com fundo branco.
    private static let similarRing: PhotoSignature = {
        var spec = Fixtures.ring(1)
        spec.rotation = 0.03
        return Fixtures.signature(spec, quality: 0.8)
    }()

    @Test("foto só parecida com um anúncio que já tem par forte, e texto diferente: não vira revisão")
    func parecidaComQuemJaTemPar() {
        let evidence = PhotoPairComparison.compare(Self.similarRing, Self.ringB)
        #expect(evidence.level == .similar)
        let pairCorrelation = PhotoPairComparison.compare(Self.ringA, Self.ringB).contentCorrelation
        #expect(evidence.contentCorrelation < pairCorrelation - PhotoMatchingParameters.competitorCorrelationMargin)
        let result = Fixtures.compare(
            [listingA(1, "anel solitário", [("a1", Self.ringA)]), listingA(3, "pulseira elos", [("a3", Self.similarRing)])],
            [listingB(2, "anel solitário", [("b2", Self.ringB)])]
        )
        #expect(result.matches.map(\.id) == ["1-2"])
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.map(\.id) == [3])
    }

    @Test("foto parecida + texto parecido com quem já tem par: fica pra revisar, avisando do outro par")
    func parecidaComTextoParecido() {
        let result = Fixtures.compare(
            [listingA(1, "anel solitário zircônia", [("a1", Self.ringA)]), listingA(3, "anel solitário zircônia rosa", [("a3", Self.similarRing)])],
            [listingB(2, "anel solitário zircônia", [("b2", Self.ringB)])]
        )
        #expect(result.matches.map(\.id) == ["1-2"])
        let review = result.reviews.first { $0.id == "3-2" }
        #expect(review?.reasons.contains(.otherListingAlreadyPaired) == true)
        #expect(review?.reasons.contains(.similarText) == true)
        #expect(result.possiblyMissingInB.isEmpty)
    }

    @Test("a mesma foto com tamanhos diferentes no template vai pra revisão; tamanho faltando não conta")
    func tamanhoDiferente() {
        let conflict = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)], size: "17")],
            [listingB(2, "anel", [("b2", Self.ringB)], size: "16")]
        )
        #expect(conflict.matches.isEmpty)
        #expect(conflict.reviews.first?.reasons.contains(.sizeDiffers("17", "16")) == true)

        let missingSize = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)], size: "17")],
            [listingB(2, "anel", [("b2", Self.ringB)])]
        )
        #expect(missingSize.matches.first?.status == .strong)
    }

    // MARK: - Duplicatas e fotos genéricas

    @Test("a mesma foto em dois anúncios da outra loja: os dois pares vão pra revisão, sem forçar 1:1")
    func duplicataNaMesmaLoja() {
        let result = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)])],
            [listingB(2, "anel", [("b2", Self.ringB)]), listingB(3, "anel", [("b3", Self.ringBOther)])]
        )
        #expect(result.matches.isEmpty)
        #expect(Set(result.reviews.map(\.id)) == ["1-2", "1-3"])
        #expect(result.reviews.allSatisfy { $0.reasons.contains(.photoUsedByManyListings(3)) })
        #expect(result.possiblyMissingInA.isEmpty && result.possiblyMissingInB.isEmpty)
    }

    @Test("foto genérica (a mesma em vários anúncios das duas lojas) não liga ninguém")
    func fotoGenerica() {
        let chart = Fixtures.signature(Spec(shape: .bracelet, seed: 99), quality: 0.9)
        let shapes = Spec.Shape.allCases
        let listingsA = (0..<4).map { index in
            listingA(index, "produto a\(index)", [
                ("a\(index)-principal", Fixtures.signature(Spec(shape: shapes[index], seed: 10 + index))),
                ("a\(index)-tabela", chart)
            ])
        }
        let listingsB = (0..<4).map { index in
            listingB(100 + index, "outro b\(index)", [
                ("b\(index)-principal", Fixtures.signature(Spec(shape: shapes[(index + 1) % shapes.count], seed: 40 + index))),
                ("b\(index)-tabela", chart)
            ])
        }
        let result = Fixtures.compare(listingsA, listingsB)
        #expect(result.matches.isEmpty)
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.count == 4)
        #expect(result.possiblyMissingInA.count == 4)
    }

    // MARK: - Não verificado × ausente

    @Test("foto que não carregou: não verificado, nunca possivelmente ausente")
    func fotoFalhouNaoVerificado() {
        let result = Fixtures.compare(
            [listingA(1, "colar coração", [("a1", nil)])],
            [listingB(2, "tornozeleira bolinhas", [("b2", Self.pendant)])]
        )
        #expect(result.possiblyMissingInB.isEmpty)
        #expect(result.unverifiedA.first?.reasons == [.photosFailed(1)])
        #expect(result.storeA.listingsWithPhotoFailures == 1)
        #expect(result.hasProblems)
    }

    @Test("sem o template (só a capa conhecida): não verificado")
    func soCapa() {
        let result = Fixtures.compare(
            [listingA(1, "colar coração", [("a1", Self.ringA)], hasDetails: false)],
            [listingB(2, "tornozeleira", [("b2", Self.pendant)])]
        )
        #expect(result.unverifiedA.first?.reasons == [.detailsUnavailable])
    }

    @Test("fotos todas brancas não são evidência: não verificado, sem par")
    func fotosLisas() throws {
        let blankData = try #require(DemoPhotoRenderer.blank(side: 300).flatMap { DemoPhotoRenderer.encode($0, type: .jpeg) })
        let blank = try PhotoSignatureGenerator.makeSignature(from: blankData)
        let result = Fixtures.compare(
            [listingA(1, "produto um", [("a1", blank)])],
            [listingB(2, "outra coisa", [("b2", blank)])]
        )
        #expect(result.matches.isEmpty)
        #expect(result.unverifiedA.first?.reasons == [.noUsablePhoto])
        #expect(result.unverifiedB.first?.reasons == [.noUsablePhoto])
    }

    @Test("lista da outra loja falhou ou veio incompleta: nada é dado como ausente nela")
    func listaIncompleta() {
        let failed = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)])],
            [],
            statusB: .failed(loaded: 0, message: "sem conexão")
        )
        #expect(failed.possiblyMissingInB.isEmpty)
        #expect(failed.unverifiedA.first?.reasons == [.otherStoreListingIncomplete(storeName: "loja B")])
        #expect(failed.storeB.problems == ["a lista não carregou (sem conexão)"])

        let incomplete = Fixtures.compare(
            [listingA(1, "anel", [("a1", Self.ringA)])],
            [listingB(2, "pingente", [("b2", Self.pendant)])],
            statusB: .incomplete(loaded: 1, expected: 2)
        )
        #expect(incomplete.possiblyMissingInB.isEmpty)
        // A lista de A veio inteira: o que é de B pode sim estar ausente em A.
        #expect(incomplete.possiblyMissingInA.map(\.id) == [2])
    }

    @Test("um anúncio não verificado da outra loja com título parecido impede o 'ausente'")
    func bloqueadoPorNaoVerificado() {
        let result = Fixtures.compare(
            [listingA(1, "anel aro zircônia", [("a1", Self.ringA)])],
            [listingB(2, "anel zircônia rosa delicado", [("b2", nil)])]
        )
        #expect(result.possiblyMissingInB.isEmpty)
        #expect(result.unverifiedA.first?.reasons == [.possibleUnverifiedCounterpart(title: "anel zircônia rosa delicado")])
    }

    // MARK: - Revisões manuais

    private func decision(
        _ first: ComparableListing,
        _ second: ComparableListing,
        _ verdict: ComparisonDecision.Verdict,
        swapped: Bool = false
    ) -> ComparisonDecision {
        let sideA = (first.key, ListingFingerprint(product: first.product))
        let sideB = (second.key, ListingFingerprint(product: second.product))
        return swapped
            ? ComparisonDecision(sideB, sideA, verdict: verdict, decidedAt: .now)
            : ComparisonDecision(sideA, sideB, verdict: verdict, decidedAt: .now)
    }

    @Test("confirmar um par em revisão vira par confirmado — de qualquer lado que a decisão tenha sido salva")
    func confirmar() {
        let first = listingA(1, "anel solitário zircônia rosa", [("a1", Self.ringA)])
        let second = listingB(2, "anel solitário zircônia rosa", [("b2", Self.otherRing)])
        let result = Fixtures.compare([first], [second], decisions: [decision(first, second, .sameProduct, swapped: true)])
        #expect(result.matches.first?.status == .confirmed)
        #expect(result.matches.first?.reasons.first == .confirmedByUser)
        #expect(result.reviews.isEmpty)
    }

    @Test("rejeitar uma correspondência forte tira a ligação: os dois ficam possivelmente ausentes")
    func rejeitar() {
        let first = listingA(1, "anel", [("a1", Self.ringA)])
        let second = listingB(2, "outro", [("b2", Self.ringB)])
        let result = Fixtures.compare([first], [second], decisions: [decision(first, second, .differentProducts)])
        #expect(result.matches.isEmpty)
        #expect(result.rejected.map(\.id) == ["1-2"])
        #expect(result.possiblyMissingInB.map(\.id) == [1])
        #expect(result.possiblyMissingInA.map(\.id) == [2])
    }

    @Test("revisão de um anúncio que mudou de capa deixa de valer, e a tela é avisada")
    func decisaoDesatualizada() {
        let first = listingA(1, "anel", [("a1", Self.ringA)])
        let second = listingB(2, "outro", [("b2", Self.ringB)])
        let old = ComparisonDecision(
            (first.key, ListingFingerprint(coverPublicID: "capa-antiga", normalizedTitle: ListingFingerprint(product: first.product).normalizedTitle)),
            (second.key, ListingFingerprint(product: second.product)),
            verdict: .differentProducts,
            decidedAt: .now
        )
        let result = Fixtures.compare([first], [second], decisions: [old])
        #expect(result.matches.first?.status == .strong)
        #expect(result.matches.first?.reasons.contains(.staleDecision) == true)
        #expect(result.staleDecisionCount == 1)
    }

    @Test("par confirmado + a mesma foto num segundo anúncio da outra loja: o segundo fica pra revisar")
    func confirmadoComDuplicata() {
        let first = listingA(1, "anel", [("a1", Self.ringA)])
        let second = listingB(2, "anel", [("b2", Self.ringB)])
        let duplicate = listingB(3, "anel", [("b3", Self.ringBOther)])
        let result = Fixtures.compare([first], [second, duplicate], decisions: [decision(first, second, .sameProduct)])
        #expect(result.matches.map(\.id) == ["1-2"])
        #expect(result.reviews.map(\.id) == ["1-3"])
        #expect(result.reviews.first?.reasons.contains(.otherListingAlreadyPaired) == true)
    }

    // MARK: - Desempenho

    @Test("catálogo grande (1500 × 1500 anúncios, 3 fotos cada) compara em poucos segundos")
    func catalogoGrande() {
        var random = SystemRandomNumberGenerator()
        let base = Self.ringA
        func listing(seller: Int, id: Int) -> ComparableListing {
            let photos = (0..<3).map { index in
                let signature = PhotoSignature(
                    algorithmVersion: base.algorithmVersion, contentSHA256: "\(seller)-\(id)-\(index)",
                    byteCount: base.byteCount, pixelWidth: base.pixelWidth, pixelHeight: base.pixelHeight,
                    isInformative: true, hasUniformBackground: true, contentBox: base.contentBox,
                    contentAspectRatio: base.contentAspectRatio, contentHash: UInt64.random(in: 0...UInt64.max, using: &random),
                    contentLuma: base.contentLuma, fullLuma: base.fullLuma, contentColor: base.contentColor
                )
                return (id: "\(seller)-\(id)-\(index)", signature: Optional(signature))
            }
            let words = (0..<5).map { _ in "w\(Int.random(in: 0..<3000, using: &random))" }
            return Fixtures.listing(seller: seller, id: id, title: words.joined(separator: " "), photos: photos)
        }
        let listingsA = (0..<1500).map { listing(seller: Fixtures.sellerA, id: $0) }
        let listingsB = (0..<1500).map { listing(seller: Fixtures.sellerB, id: 10_000 + $0) }

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = Fixtures.compare(listingsA, listingsB)
        }
        #expect(elapsed < .seconds(20), "levou \(elapsed)")
    }
}
