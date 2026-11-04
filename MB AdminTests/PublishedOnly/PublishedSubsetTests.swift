import Foundation
import Testing
@testable import MB_Admin

/// O resolver só recebe anúncios publicados: o que sai da vitrine leva junto todo par dele, e o
/// recorte da evidência dá o mesmo resultado que montar a comparação só com os publicados.
@Suite("comparação recortada nos anúncios publicados")
struct PublishedSubsetTests {
    typealias Fixtures = ComparisonFixtures
    typealias Spec = DemoPhotoRenderer.Spec

    private static let ringA = Fixtures.signature(Fixtures.ring(1), quality: 0.9)
    private static let ringB = Fixtures.signature(Fixtures.ring(1), quality: 0.6)
    private static let ringBCopy = Fixtures.signature(Fixtures.ring(1), side: 260, quality: 0.7)
    private static let pendantA = Fixtures.signature(Spec(shape: .pendant, seed: 5), quality: 0.9)
    private static let pendantB = Fixtures.signature(Spec(shape: .pendant, seed: 5), quality: 0.6)
    private static let otherRing = Fixtures.signature(Fixtures.ring(2), quality: 0.6)

    private func listingA(_ id: Int, _ title: String, _ photoID: String, _ signature: PhotoSignature) -> ComparableListing {
        Fixtures.listing(seller: Fixtures.sellerA, id: id, title: title, photos: [(photoID, signature)])
    }

    private func listingB(_ id: Int, _ title: String, _ photoID: String, _ signature: PhotoSignature) -> ComparableListing {
        Fixtures.listing(seller: Fixtures.sellerB, id: id, title: title, photos: [(photoID, signature)])
    }

    /// A: anel (1), pingente (2), outro anel (3). B: anel (10), pingente (20).
    private var listingsA: [ComparableListing] {
        [
            listingA(1, "anel solitário", "a1", Self.ringA),
            listingA(2, "pingente gota", "a2", Self.pendantA),
            listingA(3, "anel trançado", "a3", Self.otherRing)
        ]
    }

    private var listingsB: [ComparableListing] {
        [listingB(10, "anel solitário", "b10", Self.ringB), listingB(20, "pingente gota", "b20", Self.pendantB)]
    }

    private func compare(unpublishedA: Set<Int> = [], unpublishedB: Set<Int> = []) -> AccountComparisonResult {
        AccountProductMatcher.compare(
            Fixtures.side(Fixtures.sellerA, listingsA),
            Fixtures.side(Fixtures.sellerB, listingsB),
            unpublishedA: unpublishedA,
            unpublishedB: unpublishedB
        )
    }

    @Test("sem nada fora da vitrine, o resultado é o de sempre")
    func semRecorte() {
        let result = compare()
        #expect(result.matches.map(\.id).sorted() == ["1-10", "2-20"])
        #expect(result.possiblyMissingInB.map(\.id) == [3])
    }

    @Test("o par da outra loja saiu da vitrine: o produto passa a ser possivelmente ausente lá")
    func parInativadoViraAusente() {
        let result = compare(unpublishedB: [10])
        #expect(result.matches.map(\.id) == ["2-20"])
        #expect(Set(result.possiblyMissingInB.map(\.id)) == [1, 3])
        #expect(result.possiblyMissingInA.isEmpty)
        #expect(result.storeB.listingCount == 1)
    }

    @Test("produto fora da vitrine não aparece em lugar nenhum — nem como ausente na outra loja")
    func foraDaVitrineSomeDeTudo() {
        let result = compare(unpublishedA: [3, 2])
        let everywhere = result.matches.map(\.productA.id) + result.reviews.map(\.productA.id)
            + result.possiblyMissingInB.map(\.id) + result.unverifiedA.map(\.product.id)
        #expect(!everywhere.contains(3) && !everywhere.contains(2))
        #expect(result.matches.map(\.id) == ["1-10"])
        // O pingente de B ficou sem par publicado em A.
        #expect(result.possiblyMissingInA.map(\.id) == [20])
        #expect(result.storeA.listingCount == 1)
    }

    @Test("recortar a evidência dá o mesmo resultado que comparar só os publicados")
    func recorteIgualAMontarSoComPublicados() {
        let recortado = compare(unpublishedA: [2], unpublishedB: [10])
        let soPublicados = AccountProductMatcher.compare(
            Fixtures.side(Fixtures.sellerA, listingsA.filter { $0.product.id != 2 }),
            Fixtures.side(Fixtures.sellerB, listingsB.filter { $0.product.id != 10 })
        )
        #expect(recortado.matches.map(\.id) == soPublicados.matches.map(\.id))
        #expect(recortado.reviews.map(\.id) == soPublicados.reviews.map(\.id))
        #expect(recortado.possiblyMissingInA.map(\.id) == soPublicados.possiblyMissingInA.map(\.id))
        #expect(recortado.possiblyMissingInB.map(\.id) == soPublicados.possiblyMissingInB.map(\.id))
        #expect(recortado.unverifiedA.map(\.product.id) == soPublicados.unverifiedA.map(\.product.id))
        #expect(recortado.unverifiedB.map(\.product.id) == soPublicados.unverifiedB.map(\.product.id))
    }

    @Test("repetido que saiu da vitrine deixa de formar grupo de repetidos")
    func repetidoForaDaVitrine() {
        let sideA = Fixtures.side(Fixtures.sellerA, [
            listingA(1, "anel solitário", "a1", Self.ringA),
            listingA(4, "anel solitário", "a4", Self.ringBCopy)
        ])
        let sideB = Fixtures.side(Fixtures.sellerB, [listingB(20, "pingente gota", "b20", Self.pendantB)])

        #expect(AccountProductMatcher.compare(sideA, sideB).duplicatesA.count == 1)
        #expect(AccountProductMatcher.compare(sideA, sideB, unpublishedA: [4]).duplicatesA.isEmpty)
    }

    @Test("o recorte renumera os pares dentro da loja e os grupos de capa, sem sobrar índice velho")
    func renumeraEvidencia() {
        let sideA = Fixtures.side(Fixtures.sellerA, [
            listingA(1, "pingente gota", "a1", Self.pendantA),
            listingA(2, "anel solitário", "a2", Self.ringA),
            listingA(3, "anel solitário", "a3", Self.ringBCopy)
        ])
        let sideB = Fixtures.side(Fixtures.sellerB, [listingB(10, "anel solitário", "b10", Self.ringB)])
        let evidence = ComparisonEvidenceBuilder.build(sideA.listings, sideB.listings)

        let published = PublishedSubset.restrict(sideA, sideB, evidence: evidence, unpublishedA: [1], unpublishedB: [])

        #expect(published.sideA.listings.map(\.product.id) == [2, 3])
        #expect(published.evidence.coverGroupsA == [[0, 1]])
        #expect(published.evidence.storePairsA.map { [$0.indexA, $0.indexB] } == [[0, 1]])
        #expect(Set(published.evidence.pairs.keys.map(\.indexA)) == [0, 1])
        #expect(published.evidence.pairs.values.allSatisfy { $0.indexA < published.sideA.listings.count })
    }
}
