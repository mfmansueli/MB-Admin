import Foundation
import Testing
@testable import MB_Admin

@Suite("par de produtos da comparação")
struct ProductMatchTests {
    typealias Fixtures = ComparisonFixtures

    @Test("só forte e confirmado contam como o mesmo produto; revisar e rejeitado não")
    func isMatch() {
        #expect(Fixtures.match(1, 2, status: .strong).isMatch)
        #expect(Fixtures.match(1, 2, status: .confirmed).isMatch)
        #expect(!Fixtures.match(1, 2, status: .needsReview).isMatch)
        #expect(!Fixtures.match(1, 2, status: .rejected).isMatch)
    }

    @Test("decisão sua: só confirmado e rejeitado — a sugestão automática nunca conta como decisão")
    func hasUserDecision() {
        #expect(!Fixtures.match(1, 2, status: .strong).hasUserDecision)
        #expect(!Fixtures.match(1, 2, status: .needsReview).hasUserDecision)
        #expect(Fixtures.match(1, 2, status: .confirmed).hasUserDecision)
        #expect(Fixtures.match(1, 2, status: .rejected).hasUserDecision)
    }

    @Test("o estado aparece em palavras, sem percentual")
    func statusText() {
        #expect(Fixtures.match(1, 2, status: .strong).statusText == "correspondência forte")
        #expect(Fixtures.match(1, 2, status: .confirmed).statusText == "confirmado por você")
        #expect(Fixtures.match(1, 2, status: .needsReview).statusText == "precisa revisar")
        #expect(Fixtures.match(1, 2, status: .rejected).statusText == "marcado como diferentes")
    }

    @Test("o resumo é o primeiro motivo; o id junta os dois produtos")
    func resumoEId() {
        let match = Fixtures.match(1, 2)
        #expect(match.summaryText == ComparisonReason.samePhoto.text)
        #expect(match.id == "1-2")
        #expect(match.pairKey == ListingPairKey(match.keyB, match.keyA))
    }

    @Test("em revisão, o resumo é a dúvida, não a evidência")
    func resumoDaRevisao() {
        let match = ProductMatch(
            productA: ComparisonFixtures.product(1, title: "anel", cover: "a"),
            productB: ComparisonFixtures.product(2, title: "anel", cover: "b"),
            keyA: ListingKey(sellerID: 1001, productID: 1),
            keyB: ListingKey(sellerID: 2002, productID: 2),
            status: .needsReview,
            reasons: [.samePhoto, .brandDiffers("vivara", "pandora")],
            photoEvidence: nil, photoA: nil, photoB: nil, textSimilarity: 1
        )
        #expect(match.summaryText == "marcas diferentes (vivara × pandora)")
        #expect(Fixtures.match(1, 2, status: .needsReview).summaryText == ComparisonReason.similarPhoto.text)
    }

    @Test("sem foto de evidência, a revisão mostra as capas")
    func fotoDeExibicao() {
        let match = Fixtures.match(1, 2)
        #expect(match.displayPhotoA == "cover-1")
        #expect(match.displayPhotoB == "cover-2")
    }
}
