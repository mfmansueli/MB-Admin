import Foundation
import Testing
@testable import MB_Admin

/// Uma revisão sua mexe nas outras listas: ensina o índice (`ReviewLearning`) e explica os repetidos
/// do anúncio revisado.
@Suite("as suas revisões mexem nas outras listas")
struct ReviewDecisionImpactTests {
    typealias Fixtures = ComparisonFixtures
    private typealias Shape = DemoPhotoRenderer.Spec.Shape

    /// Sem a pulseira: o desenho sintético dela em ouro não fica "a mesma pose" que o em prata.
    private static let shapes: [Shape] = [.ring, .pendant, .earrings, .chain]
    private static let silver = Dictionary(uniqueKeysWithValues: shapes.map { ($0, Fixtures.signature(.init(shape: $0, seed: 3), quality: 0.9)) })
    /// A mesma pose em outro banho — par "precisa revisar" (variante de cor).
    private static let gold = Dictionary(uniqueKeysWithValues: shapes.map { shape in
        var spec = DemoPhotoRenderer.Spec(shape: shape, seed: 3)
        spec.metal = .gold
        return (shape, Fixtures.signature(spec, quality: 0.6))
    })
    private static let words = ["alfa", "beta", "gama", "delta"]

    private func listing(_ id: Int, seller: Int, title: String, photo: (id: String, signature: PhotoSignature?)?, price: Double = 100) -> ComparableListing {
        Fixtures.listing(seller: seller, id: id, title: title, photos: photo.map { [$0] } ?? [], price: price)
    }

    private func decision(_ verdict: ComparisonDecision.Verdict, _ first: ComparableListing, _ second: ComparableListing) -> ComparisonDecision {
        ComparisonDecision(
            (first.key, ListingFingerprint(product: first.product)),
            (second.key, ListingFingerprint(product: second.product)),
            verdict: verdict,
            decidedAt: Date()
        )
    }

    /// Um par "variante de cor" por forma: A em prata, B em ouro — todos com a mesma estrutura (e o
    /// mesmo índice), menos o título.
    private func colorPairs(sameTitle: Bool, samePrice: Bool) -> [(a: ComparableListing, b: ComparableListing)] {
        Self.shapes.enumerated().map { offset, shape in
            let word = Self.words[offset]
            return (
                listing(offset + 1, seller: Fixtures.sellerA, title: "peça \(word)", photo: ("a\(offset)", Self.silver[shape])),
                listing(
                    offset + 101, seller: Fixtures.sellerB,
                    title: sameTitle ? "peça \(word)" : "item \(word)x outro",
                    photo: ("b\(offset)", Self.gold[shape]),
                    price: samePrice ? 100 : 160
                )
            )
        }
    }

    /// Pares sem foto nenhuma, decididos por você só pra servir de exemplo.
    private func textPairs(_ count: Int, from start: Int, sameTitle: Bool, samePrice: Bool) -> [(a: ComparableListing, b: ComparableListing)] {
        (0..<count).map { offset in
            let id = start + offset
            return (
                listing(id, seller: Fixtures.sellerA, title: "colar exemplo\(id)", photo: nil),
                listing(id + 1000, seller: Fixtures.sellerB, title: sameTitle ? "colar exemplo\(id)" : "brinco outro\(id)", photo: nil,
                        price: samePrice ? 100 : 160)
            )
        }
    }

    @Test("sem revisões suficientes, os pares parecidos continuam em revisão")
    func semAprender() {
        let pairs = colorPairs(sameTitle: true, samePrice: true)
        let result = Fixtures.compare(pairs.map(\.a), pairs.map(\.b), decisions: [decision(.sameProduct, pairs[0].a, pairs[0].b)])
        #expect(result.reviews.count == 3)
        #expect(result.learning == .none)
    }

    @Test("três \"mesmo produto\" num tipo de par decidem o par igual que faltava — com o motivo")
    func aprendeMesmoProduto() throws {
        let pairs = colorPairs(sameTitle: true, samePrice: true)
        let examples = textPairs(3, from: 50, sameTitle: false, samePrice: false)
        let decisions = pairs.prefix(3).map { decision(.sameProduct, $0.a, $0.b) }
            + examples.map { decision(.differentProducts, $0.a, $0.b) }
        let dry = Fixtures.compare(pairs.map(\.a) + examples.map(\.a), pairs.map(\.b) + examples.map(\.b))
        try #require(dry.reviews.filter { $0.productA.id < 50 }.count == 4, "esperava as quatro variantes de cor em revisão")

        let result = Fixtures.compare(pairs.map(\.a) + examples.map(\.a), pairs.map(\.b) + examples.map(\.b), decisions: decisions)
        let learned = result.matches.filter(\.isLearned)
        #expect(learned.map(\.id) == ["4-104"])
        #expect(result.reviews.isEmpty)
        #expect(learned.first?.statusText == "mesmo produto pelas suas revisões")
        #expect(learned.first?.hasUserDecision == false)
        #expect(result.learning.learnedSame == 1)
    }

    @Test("três \"diferentes\" num tipo de par tiram o par igual da revisão — ele vira ausente")
    func aprendeDiferentes() throws {
        let pairs = colorPairs(sameTitle: false, samePrice: false)
        let examples = textPairs(3, from: 50, sameTitle: true, samePrice: true)
        let decisions = pairs.prefix(3).map { decision(.differentProducts, $0.a, $0.b) }
            + examples.map { decision(.sameProduct, $0.a, $0.b) }
        let dry = Fixtures.compare(pairs.map(\.a) + examples.map(\.a), pairs.map(\.b) + examples.map(\.b))
        try #require(dry.reviews.filter { $0.productA.id < 50 }.count == 4, "esperava as quatro variantes de cor em revisão")
        let reviewScore = try #require(dry.reviews.first?.index.score)
        let exampleScore = try #require(
            Fixtures.compare(examples.map(\.a), examples.map(\.b), decisions: examples.map { decision(.sameProduct, $0.a, $0.b) })
                .matches.first?.index.score
        )
        try #require(exampleScore > reviewScore, "os exemplos de \"mesmo\" precisam ficar acima das variantes")

        let result = Fixtures.compare(pairs.map(\.a) + examples.map(\.a), pairs.map(\.b) + examples.map(\.b), decisions: decisions)
        let learned = result.rejected.filter(\.isLearned)
        #expect(learned.map(\.id) == ["4-104"])
        #expect(result.reviews.isEmpty)
        #expect(result.possiblyMissingInB.map(\.id).contains(4))
        #expect(result.learning.learnedDifferent == 1)
    }

    @Test("confirmar A × B1 tira da revisão o B2 repetido de B1 — e ele não vira ausente")
    func repetidoDoPar() {
        let ring = Fixtures.signature(Fixtures.ring(1), quality: 0.9)
        let ringAgain = Fixtures.signature(Fixtures.ring(1), quality: 0.6)
        let ringOnceMore = Fixtures.signature(Fixtures.ring(1), quality: 0.75)
        let listingA = listing(1, seller: Fixtures.sellerA, title: "anel coração vazado", photo: ("a1", ring))
        let first = listing(10, seller: Fixtures.sellerB, title: "anel coração vazado", photo: ("b10", ringAgain))
        let second = listing(11, seller: Fixtures.sellerB, title: "anel coração vazado", photo: ("b11", ringOnceMore))

        let before = Fixtures.compare([listingA], [first, second])
        #expect(before.reviews.count == 2)
        #expect(before.duplicatesB.first?.products.map(\.id) == [10, 11])

        let after = Fixtures.compare([listingA], [first, second], decisions: [decision(.sameProduct, listingA, first)])
        #expect(after.matches.map(\.id) == ["1-10"])
        #expect(after.reviews.isEmpty)
        #expect(after.possiblyMissingInA.isEmpty)
        #expect(after.duplicatesB.first?.products.map(\.id) == [10, 11])
    }
}
